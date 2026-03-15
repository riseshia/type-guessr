# frozen_string_literal: true

require "digest/sha2"
require "json"
require "fileutils"

module RubyLsp
  module TypeGuessr
    module Dsl
      # Watches AR schema files (db/schema.rb, db/structure.sql) for changes
      # and manages a disk cache for DSL-generated type data.
      #
      # AR-specific: Mongoid has no schema file concept and needs a different strategy.
      class ArSchemaWatcher
        CACHE_VERSION = 1

        def initialize(project_root, cache_dir: nil)
          @project_root = project_root
          @cache_dir = cache_dir || default_cache_dir
          @last_hash = nil
        end

        def schema_files
          patterns = [
            File.join(@project_root, "db", "**", "schema.rb"),
            File.join(@project_root, "db", "**", "structure.sql"),
          ]
          patterns.flat_map { |p| Dir.glob(p) }.sort
        end

        def current_hash
          files = schema_files
          return "empty" if files.empty?

          digest = Digest::SHA256.new
          files.each do |f|
            digest.update(f)
            digest.update(File.read(f))
          end
          digest.hexdigest
        end

        def changed?
          hash = current_hash
          changed = @last_hash.nil? || @last_hash != hash
          @last_hash = hash
          changed
        end

        def load_cache
          path = cache_path
          return nil unless File.exist?(path)

          data = JSON.parse(File.read(path))
          return nil unless data["version"] == CACHE_VERSION

          hash = current_hash
          return nil unless data["schema_hash"] == hash

          @last_hash = hash
          data["models"]
        rescue JSON::ParserError, Errno::ENOENT
          nil
        end

        def save_cache(models_data)
          FileUtils.mkdir_p(File.dirname(cache_path))

          hash = current_hash
          data = {
            "version" => CACHE_VERSION,
            "schema_hash" => hash,
            "models" => models_data
          }

          File.write(cache_path, JSON.generate(data))
          @last_hash = hash
        end

        def clear_cache
          FileUtils.rm_f(cache_path)
        end

        private def cache_path
          project_dir = @project_root.gsub(%r{[/\\]}, "-").gsub(/\A-/, "")
          File.join(@cache_dir, project_dir, "cache.json")
        end

        private def default_cache_dir
          xdg_cache = ENV.fetch("XDG_CACHE_HOME", File.join(Dir.home, ".cache"))
          File.join(xdg_cache, "type-guessr", "dsl-cache")
        end
      end
    end
  end
end
