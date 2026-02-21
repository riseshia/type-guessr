# frozen_string_literal: true

module RubyLsp
  module TypeGuessr
    # Adapter wrapping RubyIndexer for Core layer consumption
    # Provides a stable interface isolating RubyIndexer API changes
    class CodeIndexAdapter
      # Public instance methods of Object (BasicObject + Kernel).
      # Every class inherits these, so they have zero discriminating power
      # for duck-type candidate search and should be excluded.
      OBJECT_METHOD_NAMES = %w[
        ! != !~ == === <=>
        __id__ __send__
        class clone define_singleton_method display dup
        enum_for eql? equal? extend
        freeze frozen? hash inspect
        instance_of? instance_variable_defined?
        instance_variable_get instance_variable_set instance_variables
        is_a? itself kind_of?
        method methods nil? object_id
        private_methods protected_methods public_method public_methods public_send
        remove_instance_variable respond_to? respond_to_missing?
        send singleton_class singleton_method singleton_methods
        tap then to_enum to_s yield_self
      ].to_set.freeze

      def initialize(index)
        @index = index
        @member_index = nil       # { method_name => [Entry] }
        @member_index_files = nil # { file_path => [Entry] } for removal
      end

      # Build reverse index: method_name → [Entry::Member]
      # One-time full scan of index entries, called after initial indexing.
      # Uses keys snapshot + point lookups to avoid Hash iteration conflict
      # with concurrent Index#add on the main LSP thread.
      def build_member_index!
        return unless @index

        mi = Hash.new { |h, k| h[k] = [] }
        fi = Hash.new { |h, k| h[k] = [] }

        entries_hash = @index.instance_variable_get(:@entries)
        keys = entries_hash.keys # atomic snapshot under GIL

        keys.each do |name|
          (entries_hash[name] || []).each do |entry|
            next unless entry.is_a?(RubyIndexer::Entry::Member) && entry.owner

            mi[entry.name] << entry
            fp = entry.file_path
            fi[fp] << entry if fp
          end
        end

        @member_index = mi
        @member_index_files = fi
      end

      # Incrementally update member_index for a single file.
      # Must be called AFTER RubyIndexer has re-indexed the file.
      # @param file_uri [URI::Generic] File URI (same format as RubyIndexer entries)
      def refresh_member_index!(file_uri)
        return unless @member_index

        file_path = file_uri.respond_to?(:full_path) ? file_uri.full_path : file_uri.path

        # Remove old entries
        old_entries = @member_index_files.delete(file_path) || []
        old_entries.each { |entry| @member_index[entry.name]&.delete(entry) }

        # Add new entries from RubyIndexer
        new_entries = @index.entries_for(file_uri, RubyIndexer::Entry::Member) || []
        new_entries = new_entries.select(&:owner)
        new_entries.each { |entry| @member_index[entry.name] << entry }
        @member_index_files[file_path] = new_entries unless new_entries.empty?
      end

      # Get all member entries indexed for a specific file
      # @param file_path [String] Absolute file path
      # @return [Array<RubyIndexer::Entry::Member>] Member entries for the file
      def member_entries_for_file(file_path)
        return [] unless @member_index_files

        @member_index_files[file_path] || []
      end

      # Find classes that define ALL given methods (intersection)
      # Each element responds to .name and .positional_count (duck typed)
      # @param called_methods [Array<#name, #positional_count>] Methods to search
      # @return [Array<String>] Class names defining all methods
      def find_classes_defining_methods(called_methods)
        return [] if called_methods.empty?
        return [] unless @index

        # Exclude Object methods — all classes have them, zero discriminating power
        called_methods = called_methods.reject { |cm| OBJECT_METHOD_NAMES.include?(cm.name.to_s) }
        return [] if called_methods.empty?

        # Pivot approach: 1 lookup + (N-1) resolve_method calls
        # Pick the longest method name as pivot (likely most specific → fewest candidates)
        pivot = called_methods.max_by { |cm| cm.name.to_s.length }
        rest = called_methods - [pivot]

        # O(1) member_index lookup when available, fuzzy_search fallback otherwise
        entries = if @member_index
                    @member_index[pivot.name.to_s] || []
                  else
                    @index.fuzzy_search(pivot.name.to_s) do |entry|
                      entry.is_a?(RubyIndexer::Entry::Member) && entry.name == pivot.name.to_s
                    end
                  end

        entries = filter_by_arity(entries, pivot.positional_count, pivot.keywords) if pivot.positional_count

        candidates = entries.filter_map do |entry|
          entry.owner.name if entry.respond_to?(:owner) && entry.owner
        end.uniq

        return [] if candidates.empty?
        return candidates if rest.empty?

        # Verify each candidate has ALL remaining methods via resolve_method
        # resolve_method walks the ancestor chain, so inherited methods are found
        candidates.select do |class_name|
          rest.all? do |cm|
            method_entries = @index.resolve_method(cm.name.to_s, class_name)
            next false if method_entries.nil? || method_entries.empty?
            next true unless cm.positional_count

            method_entries.any? { |e| accepts_arity?(e, cm.positional_count, cm.keywords) }
          rescue RubyIndexer::Index::NonExistingNamespaceError
            false
          end
        end
      end

      # Get linearized ancestor chain for a class
      # @param class_name [String] Fully qualified class name
      # @return [Array<String>] Ancestor names in MRO order
      def ancestors_of(class_name)
        return [] unless @index

        @index.linearized_ancestors_of(class_name)
      rescue RubyIndexer::Index::NonExistingNamespaceError
        []
      end

      # Get kind of a constant
      # @param constant_name [String] Fully qualified constant name
      # @return [Symbol, nil] :class, :module, or nil
      def constant_kind(constant_name)
        return nil unless @index

        entries = @index[constant_name]
        return nil if entries.nil? || entries.empty?

        case entries.first
        when RubyIndexer::Entry::Class then :class
        when RubyIndexer::Entry::Module then :module
        end
      end

      # Look up owner of a class method
      # @param class_name [String] Class name
      # @param method_name [String] Method name
      # @return [String, nil] Owner name or nil
      def class_method_owner(class_name, method_name)
        return nil unless @index

        unqualified_name = ::TypeGuessr::Core::IR.extract_last_name(class_name)
        singleton_name = "#{class_name}::<Class:#{unqualified_name}>"
        entries = @index.resolve_method(method_name, singleton_name)
        return nil if entries.nil? || entries.empty?

        entries.first.owner&.name
      rescue RubyIndexer::Index::NonExistingNamespaceError
        nil
      end

      # Resolve a short constant name to its fully qualified name using nesting context
      # @param short_name [String] Short constant name (e.g., "RuntimeAdapter")
      # @param nesting [Array<String>] Nesting context (e.g., ["RubyLsp", "TypeGuessr"])
      # @return [String, nil] Fully qualified name or nil if not found
      def resolve_constant_name(short_name, nesting)
        return nil unless @index

        entries = @index.resolve(short_name, nesting)
        entries&.first&.name
      rescue StandardError
        nil
      end

      # Look up owner of an instance method
      # @param class_name [String] Class name
      # @param method_name [String] Method name
      # @return [String, nil] Owner name or nil
      def instance_method_owner(class_name, method_name)
        return nil unless @index

        entries = @index.resolve_method(method_name, class_name)
        return nil if entries.nil? || entries.empty?

        entries.first.owner&.name
      rescue RubyIndexer::Index::NonExistingNamespaceError
        nil
      end

      private def filter_by_arity(entries, count, keywords)
        entries.select { |entry| accepts_arity?(entry, count, keywords) }
      end

      private def accepts_arity?(entry, count, keywords)
        sigs = entry.signatures
        # Accessor (reader) has no signatures → accepts 0 arguments only
        return count.zero? && keywords.empty? if sigs.empty?

        sigs.any? do |sig|
          required = 0
          optional = 0
          has_rest = false
          has_keyword_params = false

          sig.parameters.each do |p|
            case p
            when RubyIndexer::Entry::RequiredParameter then required += 1
            when RubyIndexer::Entry::OptionalParameter then optional += 1
            when RubyIndexer::Entry::RestParameter then has_rest = true
            when RubyIndexer::Entry::KeywordParameter,
                 RubyIndexer::Entry::OptionalKeywordParameter,
                 RubyIndexer::Entry::KeywordRestParameter
              has_keyword_params = true
            end
          end

          # When call has keywords but method has no keyword params,
          # keywords are implicitly converted to a Hash positional argument
          effective_count = count
          effective_count += 1 if keywords.any? && !has_keyword_params

          if has_rest
            effective_count >= required
          else
            effective_count.between?(required, required + optional)
          end
        end
      end
    end
  end
end
