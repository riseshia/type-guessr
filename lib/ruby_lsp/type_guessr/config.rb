# frozen_string_literal: true

module RubyLsp
  module TypeGuessr
    # Loads TypeGuessr settings from .type-guessr.yml in the current working directory.
    #
    # Defaults:
    # - enabled: true
    # - debug: false
    # - union_cutoff: 10
    # - hash_shape_max_fields: 15
    # - max_chain_depth: 5
    module Config
      CONFIG_FILENAME = ".type-guessr.yml"

      # Default values for type inference limits
      DEFAULT_UNION_CUTOFF = 10
      DEFAULT_HASH_SHAPE_MAX_FIELDS = 15
      DEFAULT_MAX_CHAIN_DEPTH = 5

      module_function

      def reset!
        @cached_config = nil
        @cached_mtime = nil
      end

      def enabled?
        value = load_config.fetch("enabled", true)
        value != false
      end

      def debug?
        load_config["debug"] == true
      end

      def debug_server_enabled?
        config = load_config
        return config["debug_server"] if config.key?("debug_server")

        debug?
      end

      def debug_server_port
        load_config.fetch("debug_server_port", 7010)
      end

      def union_cutoff
        load_config.fetch("union_cutoff", DEFAULT_UNION_CUTOFF)
      end

      def hash_shape_max_fields
        load_config.fetch("hash_shape_max_fields", DEFAULT_HASH_SHAPE_MAX_FIELDS)
      end

      def max_chain_depth
        load_config.fetch("max_chain_depth", DEFAULT_MAX_CHAIN_DEPTH)
      end

      def load_config
        path = File.join(Dir.pwd, CONFIG_FILENAME)
        return default_config if !File.exist?(path)

        mtime = File.mtime(path)
        return @cached_config if @cached_config && @cached_mtime == mtime

        require "yaml"

        raw = File.read(path)
        data = YAML.safe_load(raw, permitted_classes: [], permitted_symbols: [], aliases: false)
        data = {} unless data.is_a?(Hash)

        @cached_config = default_config.merge(data)
        @cached_mtime = mtime
        @cached_config
      rescue StandardError => e
        warn("[TypeGuessr] Error loading config file: #{e.message}")
        default_config
      end

      def default_config
        {
          "enabled" => true,
          "debug" => false
        }
      end
      private_class_method :default_config
    end
  end
end
