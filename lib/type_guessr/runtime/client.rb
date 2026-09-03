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
      # Raised when the server subprocess dies mid-session. Must abort the
      # whole analysis — swallowing it would turn every later query into a
      # fake zero-candidate result.
      class ServerDiedError < StandardError; end

      # Raised when the server answers a query with an error. Callers must not
      # interpret it as an empty result — that would fake a zero-candidate.
      class QueryError < StandardError; end

      attr_reader :module_count, :method_count

      # @param project_path [String] Absolute path to the target project
      # @param boot_file [String, nil] Boot file for the server
      # @param rails [Boolean] Use `bin/rails runner` to launch the server
      def initialize(project_path:, boot_file: nil, rails: false)
        @project_path = project_path
        @boot_file = boot_file
        @rails = rails
        @module_count = 0
        @method_count = 0
      end

      # Start the server subprocess and wait for it to become ready.
      # @raise [RuntimeError] if the server fails to start
      def start
        server_path = File.expand_path("server.rb", __dir__)

        if @rails
          cmd = ["bin/rails", "runner", server_path]
        else
          cmd = ["bundle", "exec", "ruby", server_path]
          cmd << @boot_file if @boot_file
        end

        # The analyzer's own bundler/ruby env (BUNDLE_*, GEM_*, RUBYOPT, RUBYLIB)
        # must not leak into the child, which may run a different Ruby version.
        # popen3 MERGES the env hash into ENV, so removed keys are still
        # inherited — unsetting requires an explicit nil value.
        env = {}
        ENV.each_key do |k|
          env[k] = nil if k.start_with?("BUNDLE_", "RUBYGEMS_", "GEM_", "RUBYOPT", "RUBYLIB")
        end
        env["BUNDLE_GEMFILE"] = File.join(@project_path, "Gemfile")

        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(env, *cmd, chdir: @project_path)

        # Drain stderr continuously: a chatty boot (bundler warnings, SQL logs)
        # can fill the pipe buffer and deadlock the server if left unread.
        @stderr_buffer = +""
        @stderr_thread = Thread.new do
          @stderr.each_line { |l| @stderr_buffer << l }
        rescue IOError
          # Pipe closed during shutdown
        end

        # The target app may print non-protocol noise to stdout before the
        # server takes over (e.g. Rails boot logging via `bin/rails runner`).
        # Skip lines that are not the JSON ready handshake until we find it.
        ready = nil
        while (line = @stdout.gets)
          parsed = begin
            JSON.parse(line)
          rescue JSON::ParserError
            next
          end
          next unless parsed.is_a?(Hash) && parsed.key?("status")

          ready = parsed
          break
        end

        unless ready
          sleep 0.2 # Let the drain thread catch up after child exit
          raise "Runtime server failed to start (no ready handshake).\nstderr (last 4KB): #{@stderr_buffer[-4096..] || @stderr_buffer}"
        end

        raise "Runtime server failed to start: #{ready.inspect}" unless ready["status"] == "ready"

        @module_count = ready["modules"]
        @method_count = ready["methods"]
      end

      # Find classes whose public instance methods include ALL given method names.
      # @param methods [Array<String>] Method names
      # @param calls [Array<Hash>, nil] call shapes ({"name", "positional_count",
      #   "keywords"}); when given, candidates are also filtered by call arity
      # @return [Hash] { "result" => [String], "filtered" => String? }
      def find_classes(methods, calls: nil)
        args = { "methods" => methods }
        args["calls"] = calls if calls
        query_raw("find_classes", args)
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

      # Check if a method is callable on a class (instance level by default,
      # class level with singleton: true).
      # @param class_name [String]
      # @param method_name [String]
      # @param singleton [Boolean] check the class object instead of its instances
      # @param positional_count [Integer, nil] call-site positional args (nil = splat/unknown)
      # @param keywords [Array<String>] call-site keyword names
      # @return [Boolean, String, nil] true (callable), false (absent),
      #   "arity" (exists but the call does not fit), nil (class unknown here)
      def method_defined?(class_name, method_name, singleton: false, positional_count: nil, keywords: [])
        query("method_defined?",
              { "class_name" => class_name, "method_name" => method_name, "singleton" => singleton,
                "positional_count" => positional_count, "keywords" => keywords })
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

      private def query_raw(method, args = {})
        request = { "method" => method, "args" => args }
        @stdin.puts JSON.generate(request)
        @stdin.flush

        response_line = @stdout.gets
        # EOF means the server process died — an empty response here would be
        # indistinguishable from a real zero-candidate result downstream.
        server_died!(request) unless response_line

        response = JSON.parse(response_line)
        raise QueryError, "#{request["method"]} #{request["args"].inspect}: #{response["error"]}" if response.key?("error")

        response
      rescue Errno::EPIPE
        server_died!(request)
      end

      private def server_died!(request)
        @stderr_thread&.join(0.5)
        status = @wait_thread.join(2) && @wait_thread.value
        raise ServerDiedError, "Runtime server died (during #{request["method"]} #{request["args"].inspect}). " \
                               "exit: #{status.inspect}\nstderr (last 4KB): #{@stderr_buffer[-4096..] || @stderr_buffer}"
      end

      private def query(method, args = {})
        query_raw(method, args)["result"]
      end
    end
  end
end
