# frozen_string_literal: true

require "json"
require "digest/sha2"
require "fileutils"

module TypeGuessr
  module Core
    module Cache
      # Manages disk-based cache of gem method signatures.
      # Cache key = gem name + version + hash of transitive dependencies.
      # Files stored at: ~/.cache/type-guessr/gem-signatures/{name}-{version}-{dep_hash}.json
      class GemSignatureCache
        CACHE_FORMAT_VERSION = 1

        # @param cache_dir [String, nil] Override cache directory (for testing)
        def initialize(cache_dir: nil)
          @cache_dir = cache_dir || default_cache_dir
        end

        # Check if a cached file exists for the given gem
        # @param gem_name [String]
        # @param gem_version [String]
        # @param transitive_deps [Hash{String => String}] { dep_name => dep_version }
        # @return [Boolean]
        def cached?(gem_name, gem_version, transitive_deps)
          File.exist?(cache_path(gem_name, gem_version, transitive_deps))
        end

        # Load cached signatures
        # @param gem_name [String]
        # @param gem_version [String]
        # @param transitive_deps [Hash{String => String}]
        # @return [Hash, nil] { "instance_methods" => {...}, "class_methods" => {...} } or nil on failure
        def load(gem_name, gem_version, transitive_deps)
          path = cache_path(gem_name, gem_version, transitive_deps)
          return nil unless File.exist?(path)

          data = JSON.parse(File.read(path))
          return nil unless data["version"] == CACHE_FORMAT_VERSION

          {
            "instance_methods" => data["instance_methods"] || {},
            "class_methods" => data["class_methods"] || {},
            "fully_inferred" => data.fetch("fully_inferred", true),
            "lazy_only" => data.fetch("lazy_only", false)
          }
        rescue JSON::ParserError, Errno::ENOENT
          nil
        end

        # Save signatures to cache
        # @param gem_name [String]
        # @param gem_version [String]
        # @param transitive_deps [Hash{String => String}]
        # @param instance_methods [Hash] { class_name => { method_name => serialized_entry } }
        # @param class_methods [Hash] { class_name => { method_name => serialized_entry } }
        # @param fully_inferred [Boolean] Whether types are fully inferred (false = Unguessed placeholders)
        def save(gem_name, gem_version, transitive_deps,
                 instance_methods:, class_methods:, fully_inferred: true, lazy_only: false)
          path = cache_path(gem_name, gem_version, transitive_deps)
          FileUtils.mkdir_p(File.dirname(path))

          data = {
            "version" => CACHE_FORMAT_VERSION,
            "fully_inferred" => fully_inferred,
            "lazy_only" => lazy_only,
            "instance_methods" => instance_methods,
            "class_methods" => class_methods
          }

          File.write(path, JSON.generate(data))
        end

        # Delete all cached files
        def clear!
          FileUtils.rm_rf(@cache_dir)
        end

        private def default_cache_dir
          xdg_cache = ENV.fetch("XDG_CACHE_HOME", File.join(Dir.home, ".cache"))
          File.join(xdg_cache, "type-guessr", "gem-signatures")
        end

        private def cache_path(gem_name, gem_version, transitive_deps)
          dep_hash = compute_dep_hash(transitive_deps)
          File.join(@cache_dir, "#{gem_name}-#{gem_version}-#{dep_hash}.json")
        end

        private def compute_dep_hash(transitive_deps)
          sorted_pairs = transitive_deps.sort.map { |name, version| "#{name}:#{version}" }.join(",")
          Digest::SHA256.hexdigest("v1:#{sorted_pairs}")[0..5]
        end
      end
    end
  end
end
