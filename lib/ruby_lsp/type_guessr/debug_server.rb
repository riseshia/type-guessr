# frozen_string_literal: true

require "socket"
require "json"
require "uri"
require_relative "../../type_guessr/core/variable_index"

module RubyLsp
  module TypeGuessr
    # Debug web server for inspecting TypeGuessr index data
    # Only runs when debug mode is enabled
    class DebugServer
      # Core layer shortcut
      VariableIndex = ::TypeGuessr::Core::VariableIndex
      private_constant :VariableIndex

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

      def route_request(path)
        uri = URI(path)
        params = parse_query_string(uri.query)

        case uri.path
        when "/"
          index_page
        when "/api/search"
          api_search(params["q"])
        when "/api/stats"
          api_stats
        else
          not_found_page
        end
      end

      def parse_query_string(query)
        return {} if query.nil? || query.empty?

        query.split("&").each_with_object({}) do |pair, hash|
          key, value = pair.split("=", 2)
          hash[URI.decode_www_form_component(key)] = URI.decode_www_form_component(value || "")
        end
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
          body: build_html_page
        }
      end

      def api_search(query)
        index = VariableIndex.instance
        result = query && !query.empty? ? index.search(query) : { index: {}, types: {} }
        {
          status: "200 OK",
          content_type: "application/json; charset=utf-8",
          body: JSON.pretty_generate(result)
        }
      end

      def api_stats
        index = VariableIndex.instance
        stats = index.stats
        {
          status: "200 OK",
          content_type: "application/json; charset=utf-8",
          body: JSON.pretty_generate(stats)
        }
      end

      def not_found_page
        {
          status: "404 Not Found",
          content_type: "text/html; charset=utf-8",
          body: "<html><body><h1>404 Not Found</h1></body></html>"
        }
      end

      def build_html_page
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>TypeGuessr Debug Console</title>
            <style>
              * { box-sizing: border-box; }
              body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
                margin: 0;
                padding: 20px;
                background: #1e1e1e;
                color: #d4d4d4;
              }
              h1 { color: #569cd6; margin-bottom: 10px; }
              h2 { color: #4ec9b0; margin-top: 30px; }
              .stats {
                display: flex;
                gap: 20px;
                margin: 20px 0;
                flex-wrap: wrap;
              }
              .stat-card {
                background: #2d2d2d;
                border: 1px solid #404040;
                border-radius: 8px;
                padding: 15px 25px;
                min-width: 150px;
              }
              .stat-card h3 {
                margin: 0 0 5px 0;
                color: #9cdcfe;
                font-size: 14px;
              }
              .stat-card .value {
                font-size: 32px;
                font-weight: bold;
                color: #ce9178;
              }
              .controls {
                margin: 20px 0;
              }
              button {
                background: #0e639c;
                color: white;
                border: none;
                padding: 10px 20px;
                border-radius: 4px;
                cursor: pointer;
                margin-right: 10px;
              }
              button:hover { background: #1177bb; }
              .filter-input {
                background: #3c3c3c;
                border: 1px solid #404040;
                color: #d4d4d4;
                padding: 10px 15px;
                border-radius: 4px;
                width: 300px;
              }
              .index-tree {
                background: #252526;
                border: 1px solid #404040;
                border-radius: 8px;
                padding: 15px;
                max-height: 600px;
                overflow: auto;
              }
              .file-entry {
                margin: 10px 0;
              }
              .file-path {
                color: #dcdcaa;
                cursor: pointer;
                padding: 5px;
                border-radius: 4px;
              }
              .file-path:hover { background: #3c3c3c; }
              .scope-entry {
                margin-left: 20px;
                padding: 5px 0;
              }
              .scope-id { color: #4ec9b0; }
              .var-entry {
                margin-left: 40px;
                padding: 3px 0;
              }
              .var-name { color: #9cdcfe; }
              .var-type { color: #4fc1ff; }
              .method-calls {
                color: #ce9178;
                font-size: 12px;
                margin-left: 10px;
              }
              .collapsed { display: none; }
              .toggle { cursor: pointer; user-select: none; }
              .toggle::before { content: '▼ '; color: #808080; }
              .toggle.closed::before { content: '▶ '; }
              pre {
                background: #252526;
                padding: 15px;
                border-radius: 8px;
                overflow: auto;
                max-height: 400px;
              }
              code { color: #ce9178; }
              .hint {
                color: #808080;
                font-size: 13px;
                margin: 5px 0 15px 0;
              }
              .placeholder {
                color: #6a6a6a;
                font-style: italic;
              }
              .result-count {
                color: #4ec9b0;
                margin-bottom: 10px;
              }
            </style>
          </head>
          <body>
            <h1>🔍 TypeGuessr Debug Console</h1>
            <p>Variable index inspection for TypeGuessr LSP addon</p>

            <h2>Statistics</h2>
            <div class="stats" id="stats">
              <div class="stat-card">
                <h3>Loading...</h3>
                <div class="value">-</div>
              </div>
            </div>

            <h2>Variable Index</h2>
            <div class="controls">
              <input type="text" class="filter-input" id="filter" placeholder="Search by file path (e.g., models/user)...">
              <button onclick="searchIndex()">Search</button>
              <button onclick="expandAll()">Expand All</button>
              <button onclick="collapseAll()">Collapse All</button>
            </div>
            <p class="hint">Enter a file path pattern and click Search to load matching results.</p>
            <div class="index-tree" id="indexTree">
              <p class="placeholder">Enter a search query above to find indexed variables.</p>
            </div>

            <script>
              let indexData = {};

              async function fetchStats() {
                try {
                  const res = await fetch('/api/stats');
                  const stats = await res.json();
                  renderStats(stats);
                } catch (e) {
                  document.getElementById('stats').innerHTML = '<p>Error loading stats</p>';
                }
              }

              async function searchIndex() {
                const query = document.getElementById('filter').value.trim();
                if (!query) {
                  document.getElementById('indexTree').innerHTML = '<p class="placeholder">Please enter a search query.</p>';
                  return;
                }

                document.getElementById('indexTree').innerHTML = '<p>Searching...</p>';

                try {
                  const res = await fetch('/api/search?q=' + encodeURIComponent(query));
                  indexData = await res.json();
                  renderIndex(indexData);
                } catch (e) {
                  document.getElementById('indexTree').innerHTML = '<p>Error loading index</p>';
                }
              }

              function renderStats(stats) {
                const html = `
                  <div class="stat-card">
                    <h3>Total Definitions</h3>
                    <div class="value">${stats.total_definitions}</div>
                  </div>
                  <div class="stat-card">
                    <h3>Files Indexed</h3>
                    <div class="value">${stats.files_count}</div>
                  </div>
                  <div class="stat-card">
                    <h3>Local Variables</h3>
                    <div class="value">${stats.local_variables_count}</div>
                  </div>
                  <div class="stat-card">
                    <h3>Instance Variables</h3>
                    <div class="value">${stats.instance_variables_count}</div>
                  </div>
                  <div class="stat-card">
                    <h3>Class Variables</h3>
                    <div class="value">${stats.class_variables_count}</div>
                  </div>
                `;
                document.getElementById('stats').innerHTML = html;
              }

              function renderIndex(data) {
                let html = '';
                const uniqueFiles = new Set();

                for (const [scopeType, files] of Object.entries(data.index || {})) {
                  if (Object.keys(files).length === 0) continue;

                  html += `<div class="scope-type"><h3 style="color:#c586c0">${scopeType}</h3>`;

                  for (const [filePath, scopes] of Object.entries(files)) {
                    uniqueFiles.add(filePath);
                    const shortPath = filePath.split('/').slice(-3).join('/');
                    html += `<div class="file-entry">`;
                    html += `<span class="toggle file-path" onclick="toggleCollapse(this)">${shortPath}</span>`;
                    html += `<div class="file-content">`;

                    for (const [scopeId, vars] of Object.entries(scopes)) {
                      html += `<div class="scope-entry"><span class="scope-id">${scopeId || '(top-level)'}</span>`;

                      for (const [varName, defs] of Object.entries(vars)) {
                        html += `<div class="var-entry">`;
                        html += `<span class="var-name">${varName}</span>`;

                        const type = data.types?.[scopeType]?.[filePath]?.[scopeId]?.[varName];
                        if (type) {
                          const typeStr = Object.values(type)[0];
                          html += ` : <span class="var-type">${typeStr}</span>`;
                        }

                        for (const [defKey, calls] of Object.entries(defs)) {
                          if (calls.length > 0) {
                            const methodNames = calls.map(c => c.method).join(', ');
                            html += `<span class="method-calls">[${defKey}] → ${methodNames}</span>`;
                          }
                        }

                        html += `</div>`;
                      }

                      html += `</div>`;
                    }

                    html += `</div></div>`;
                  }

                  html += `</div>`;
                }

                if (uniqueFiles.size > 0) {
                  html = `<p class="result-count">Found ${uniqueFiles.size} matching file(s)</p>` + html;
                }

                document.getElementById('indexTree').innerHTML = html || '<p class="placeholder">No matching files found.</p>';
              }

              function toggleCollapse(el) {
                el.classList.toggle('closed');
                const content = el.nextElementSibling;
                if (content) content.classList.toggle('collapsed');
              }

              function expandAll() {
                document.querySelectorAll('.toggle').forEach(el => {
                  el.classList.remove('closed');
                  const content = el.nextElementSibling;
                  if (content) content.classList.remove('collapsed');
                });
              }

              function collapseAll() {
                document.querySelectorAll('.toggle').forEach(el => {
                  el.classList.add('closed');
                  const content = el.nextElementSibling;
                  if (content) content.classList.add('collapsed');
                });
              }

              // Allow Enter key to trigger search
              document.getElementById('filter').addEventListener('keypress', (e) => {
                if (e.key === 'Enter') searchIndex();
              });

              // Initial stats load only
              fetchStats();
            </script>
          </body>
          </html>
        HTML
      end
    end
  end
end
