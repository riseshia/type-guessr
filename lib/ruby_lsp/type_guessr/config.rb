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

      module_function def reset!
        @cached_config = nil
      end

      module_function def enabled?
        value = load_config.fetch("enabled", true)
        value != false
      end

      module_function def debug?
        load_config["debug"] == true
      end

      module_function def debug_server_enabled?
        config = load_config
        return config["debug_server"] if config.key?("debug_server")

        debug?
      end

      module_function def debug_server_port
        load_config.fetch("debug_server_port", 7010)
      end

      module_function def load_config
        return @cached_config if @cached_config

        path = File.join(Dir.pwd, CONFIG_FILENAME)
        if !File.exist?(path)
          @cached_config = default_config
          return @cached_config
        end

        require "yaml"

        raw = File.read(path)
        data = YAML.safe_load(raw, permitted_classes: [], permitted_symbols: [], aliases: false)
        data = {} unless data.is_a?(Hash)

        @cached_config = default_config.merge(data)
      rescue StandardError => e
        warn("[TypeGuessr] Error loading config file: #{e.message}")
        default_config
      end

      module_function def default_config
        {
          "enabled" => true,
          "debug" => false
        }
      end
      private_class_method :default_config
    end
  end
end
