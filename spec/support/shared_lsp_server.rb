# frozen_string_literal: true

require "open3"
require_relative "lsp_client"

# Singleton LSP server for E2E tests.
# Starts ruby-lsp once and reuses it across all E2E tests in a suite.
class SharedLspServer
  class << self
    def instance
      @mutex ||= Mutex.new
      @mutex.synchronize do
        @instance ||= new.tap(&:start)
      end
    end

    def shutdown!
      @mutex&.synchronize do
        @instance&.shutdown
        @instance = nil
      end
    end
  end

  attr_reader :indexing_complete

  def initialize
    @client = nil
    @stdin = nil
    @stdout = nil
    @stderr = nil
    @wait_thr = nil
    @opened_files = {}
    @indexing_complete = false
    @stderr_thread = nil
  end

  def start
    warn "[E2E] Starting ruby-lsp server..."
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(
      "bundle", "exec", "ruby-lsp",
      chdir: Dir.pwd
    )
    @client = LspClient.new(@stdin, @stdout)

    # Handle notifications from server
    @client.on_notification do |msg|
      handle_notification(msg)
    end

    # Start stderr reader thread
    @stderr_thread = Thread.new do
      while (line = @stderr.gets)
        warn "  [stderr] #{line.strip}" if ENV["DEBUG"]
      end
    rescue IOError
      # Expected when stream is closed during shutdown
    end

    initialize_server
    warn "[E2E] Server ready!"
  end

  def query_hover(file_path, line, column)
    absolute_path = File.expand_path(file_path, Dir.pwd)
    raise "File not found: #{absolute_path}" unless File.exist?(absolute_path)

    uri = "file://#{absolute_path}"
    open_file(uri, absolute_path) unless @opened_files[uri]

    # LSP uses 0-based line/column
    response = @client.send_request("textDocument/hover", {
                                      textDocument: { uri: uri },
                                      position: { line: line - 1, character: column - 1 }
                                    })

    return nil if response&.dig("error")

    result = response&.dig("result")
    return nil if result.nil?

    extract_hover_content(result["contents"])
  end

  def query_definition(file_path, line, column)
    absolute_path = File.expand_path(file_path, Dir.pwd)
    raise "File not found: #{absolute_path}" unless File.exist?(absolute_path)

    uri = "file://#{absolute_path}"
    open_file(uri, absolute_path) unless @opened_files[uri]

    # LSP uses 0-based line/column
    response = @client.send_request("textDocument/definition", {
                                      textDocument: { uri: uri },
                                      position: { line: line - 1, character: column - 1 }
                                    })

    return nil if response&.dig("error")

    response&.dig("result")
  end

  def shutdown
    return unless @client

    warn "[E2E] Shutting down server..."
    @client.send_request("shutdown", nil)
    @client.send_notification("exit", nil)
    @stdin&.close
    @stdout&.close
    @stderr&.close
    @stderr_thread&.kill
    @wait_thr&.value
  end

  private

  def initialize_server
    root_uri = "file://#{Dir.pwd}"
    response = @client.send_request("initialize", {
                                      processId: Process.pid,
                                      rootUri: root_uri,
                                      capabilities: {
                                        textDocument: {
                                          hover: {
                                            contentFormat: %w[markdown plaintext]
                                          },
                                          definition: {
                                            linkSupport: true
                                          }
                                        },
                                        window: {
                                          workDoneProgress: true
                                        }
                                      },
                                      initializationOptions: {}
                                    })

    raise "Initialize error: #{response["error"]}" if response&.dig("error")

    @client.send_notification("initialized", {})
    warn "[E2E] Server initialized, waiting for indexing..."

    wait_for_indexing
  end

  def wait_for_indexing
    timeout = Time.now + 120 # 2 minutes timeout

    @client.drain_notifications(timeout: 0.5) until @indexing_complete || Time.now > timeout

    if @indexing_complete
      warn "[E2E] TypeGuessr indexing complete!"
    else
      warn "[E2E] Timeout waiting for indexing, continuing anyway..."
    end
  end

  def handle_notification(msg)
    method = msg["method"]
    params = msg["params"]

    case method
    when "window/logMessage"
      message = params&.dig("message") || ""
      if message.include?("[TypeGuessr]")
        warn "  #{message}" if ENV["DEBUG"]
        @indexing_complete = true if message.include?("File indexing completed")
      end
    when "$/progress"
      # Progress notifications from ruby-lsp indexing
      if ENV["DEBUG"]
        value = params&.dig("value")
        warn "  Progress: #{value["title"]}" if value&.dig("kind") == "begin"
      end
    end
  end

  def open_file(uri, file_path)
    source = File.read(file_path)
    @client.send_notification("textDocument/didOpen", {
                                textDocument: {
                                  uri: uri,
                                  languageId: "ruby",
                                  version: 1,
                                  text: source
                                }
                              })
    @opened_files[uri] = true
    # Give server time to process the file
    sleep 0.3
  end

  def extract_hover_content(contents)
    if contents.is_a?(Hash)
      contents["value"]
    elsif contents.is_a?(Array)
      contents.map { |c| c.is_a?(Hash) ? c["value"] : c }.join("\n")
    else
      contents.to_s
    end
  end
end
