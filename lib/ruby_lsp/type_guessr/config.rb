# frozen_string_literal: true

module RubyLsp
  module TypeGuessr
    # Loads TypeGuessr settings from .type-guessr.yml in the current working directory.
    #
    # Defaults:
    # - enabled: true
    # - debug: false
    module Config
      CONFIG_FILENAME = ".type-guessr.yml"

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
        return true if %w[1 true].include?(ENV["TYPE_GUESSR_DEBUG"])

        load_config["debug"] == true
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
