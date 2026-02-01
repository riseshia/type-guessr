# frozen_string_literal: true

require "json"

# JSON-RPC 2.0 client for communicating with LSP server.
# Extracted from bin/hover-repl for use in E2E tests.
class LspClient
  def initialize(stdin, stdout)
    @stdin = stdin
    @stdout = stdout
    @request_id = 0
    @notification_handler = nil
  end

  def on_notification(&block)
    @notification_handler = block
  end

  def send_request(method, params)
    @request_id += 1
    message = {
      jsonrpc: "2.0",
      id: @request_id,
      method: method,
      params: params
    }
    write_message(message)
    read_response(@request_id)
  end

  def send_notification(method, params)
    message = {
      jsonrpc: "2.0",
      method: method,
      params: params
    }
    write_message(message)
  end

  def read_response(expected_id = nil)
    loop do
      msg = read_message
      return nil unless msg

      # If it's a notification (no id), handle it and keep reading
      unless msg.key?("id")
        @notification_handler&.call(msg)
        next
      end

      # If we're waiting for a specific response, check id
      if expected_id && msg["id"] != expected_id
        # This shouldn't happen in normal flow, but handle it
        next
      end

      return msg
    end
  end

  # Read notifications without blocking (used during indexing wait)
  def drain_notifications(timeout: 0.1)
    start = Time.now
    while Time.now - start < timeout
      # Check if data is available using wait_readable for fiber scheduler compatibility
      break unless @stdout.wait_readable(0.05)

      msg = read_message
      break unless msg

      @notification_handler&.call(msg) unless msg.key?("id")
    end
  end

  private

  def read_message
    # Read Content-Length header
    header = ""
    loop do
      line = @stdout.gets
      return nil unless line
      break if line == "\r\n"

      header += line
    end

    content_length = header.match(/Content-Length: (\d+)/i)&.[](1)&.to_i
    return nil unless content_length

    # Read body
    body = @stdout.read(content_length)
    JSON.parse(body)
  end

  def write_message(message)
    json = JSON.generate(message)
    @stdin.write("Content-Length: #{json.bytesize}\r\n\r\n#{json}")
    @stdin.flush
  end
end
