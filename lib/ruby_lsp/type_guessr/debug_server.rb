# frozen_string_literal: true

require "socket"

module RubyLsp
  module TypeGuessr
    # Debug web server for inspecting TypeGuessr index data
    # Only runs when debug mode is enabled
    # Currently outputs empty page - will be rewritten for new IR-based design
    class DebugServer
      DEFAULT_PORT = 7010

      def initialize(global_state, port: DEFAULT_PORT)
        @global_state = global_state
        @port = port
        @server = nil
        @thread = nil
        @running = false
      end

      def start
        return if @running

        @running = true
        @thread = Thread.new { run_server }
      end

      def stop
        @running = false
        @server&.close
        @thread&.kill
        @thread = nil
        @server = nil
      end

      private

      def run_server
        @server = TCPServer.new("127.0.0.1", @port)

        while @running
          begin
            client = @server.accept
            handle_request(client)
          rescue IOError, Errno::EBADF
            # Server closed, exit gracefully
            break
          rescue StandardError => e
            warn("[TypeGuessr DebugServer] Error: #{e.message}")
          end
        end
      rescue Errno::EADDRINUSE
        warn("[TypeGuessr DebugServer] Port #{@port} is already in use")
      end

      def handle_request(client)
        request_line = client.gets
        return client.close if request_line.nil?

        method, path, = request_line.split
        return client.close if method != "GET"

        # Read headers (discard them)
        while (line = client.gets) && line != "\r\n"
          # skip headers
        end

        response = route_request(path)
        send_response(client, response)
      ensure
        client.close
      end

      def route_request(_path)
        index_page
      end

      def send_response(client, response)
        client.print "HTTP/1.1 #{response[:status]}\r\n"
        client.print "Content-Type: #{response[:content_type]}\r\n"
        client.print "Content-Length: #{response[:body].bytesize}\r\n"
        client.print "Connection: close\r\n"
        client.print "\r\n"
        client.print response[:body]
      end

      def index_page
        {
          status: "200 OK",
          content_type: "text/html; charset=utf-8",
          body: <<~HTML
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>TypeGuessr Debug Console</title>
              <style>
                body {
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
                  margin: 0;
                  padding: 40px;
                  background: #1e1e1e;
                  color: #d4d4d4;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  min-height: 100vh;
                }
                .container {
                  text-align: center;
                  max-width: 600px;
                }
                h1 { color: #569cd6; margin-bottom: 20px; }
                p { color: #808080; line-height: 1.6; }
              </style>
            </head>
            <body>
              <div class="container">
                <h1>🔍 TypeGuessr Debug Console</h1>
                <p>Debug server is running on port #{@port}</p>
                <p>Will be implemented based on new IR-based architecture</p>
              </div>
            </body>
            </html>
          HTML
        }
      end
    end
  end
end
