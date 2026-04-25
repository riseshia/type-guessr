# frozen_string_literal: true

require "json"
require "open3"

module TypeGuessr
  module Runtime
    # IPC client that communicates with the runtime index server subprocess.
    #
    # The server runs in the target project's Bundler environment, boots the
    # project code, and builds a method index via ObjectSpace. This client
    # sends JSON queries over stdin/stdout.
    class Client
      attr_reader :module_count, :method_count

      # @param project_path [String] Absolute path to the target project
      # @param boot_file [String, nil] Boot file for the server (e.g., config/environment.rb)
      def initialize(project_path:, boot_file: nil)
        @project_path = project_path
        @boot_file = boot_file
        @module_count = 0
        @method_count = 0
      end

      # Start the server subprocess and wait for it to become ready.
      # @raise [RuntimeError] if the server fails to start
      def start
        server_path = File.expand_path("server.rb", __dir__)

        cmd = ["bundle", "exec", "ruby", server_path]
        cmd << @boot_file if @boot_file

        env = ENV.to_h.reject { |k, _| k.start_with?("BUNDLE_", "RUBYGEMS_", "GEM_") }
        env["BUNDLE_GEMFILE"] = File.join(@project_path, "Gemfile")

        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(env, *cmd, chdir: @project_path)

        ready_line = @stdout.gets
        unless ready_line
          err_output = @stderr.read_nonblock(4096) rescue ""
          raise "Runtime server failed to start (no output).\nstderr: #{err_output}"
        end

        ready = JSON.parse(ready_line)
        unless ready["status"] == "ready"
          raise "Runtime server failed to start: #{ready_line}"
        end

        @module_count = ready["modules"]
        @method_count = ready["methods"]
      end

      # Find classes whose public instance methods include ALL given method names.
      # @param methods [Array<String>] Method names
      # @return [Hash] { "result" => [String], "filtered" => String? }
      def find_classes(methods)
        query_raw("find_classes", { "methods" => methods })
      end

      # Get linearized ancestor chain for a class.
      # @param class_name [String]
      # @return [Array<String>]
      def ancestors_of(class_name)
        query("ancestors", { "class_name" => class_name }) || []
      end

      # Get kind of a constant (:class, :module, or nil).
      # @param name [String]
      # @return [String, nil] "class", "module", or nil
      def constant_kind(name)
        query("constant_kind", { "name" => name })
      end

      # Check if a class defines an instance method.
      # @param class_name [String]
      # @param method_name [String]
      # @return [Boolean]
      def method_defined?(class_name, method_name)
        query("method_defined?", { "class_name" => class_name, "method_name" => method_name }) || false
      end

      # Find the owner of a class method.
      # @param class_name [String]
      # @param method_name [String]
      # @return [String, nil]
      def class_method_owner(class_name, method_name)
        query("class_method_owner", { "class_name" => class_name, "method_name" => method_name })
      end

      # Find the owner of an instance method.
      # @param class_name [String]
      # @param method_name [String]
      # @return [String, nil]
      def instance_method_owner(class_name, method_name)
        query("instance_method_owner", { "class_name" => class_name, "method_name" => method_name })
      end

      # Shut down the server subprocess.
      def shutdown
        query("shutdown")
        @stdin&.close
        @stdout&.close
        @stderr&.close
        @wait_thread&.join
      rescue StandardError
        # ignore
      end

      private

      def query_raw(method, args = {})
        request = { "method" => method, "args" => args }
        @stdin.puts JSON.generate(request)
        @stdin.flush

        response_line = @stdout.gets
        return {} unless response_line

        JSON.parse(response_line)
      end

      def query(method, args = {})
        query_raw(method, args)["result"]
      end
    end
  end
end
