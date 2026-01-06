# frozen_string_literal: true

require "socket"
require "json"
require "cgi"
require_relative "graph_builder"

module RubyLsp
  module TypeGuessr
    # Debug web server for inspecting TypeGuessr index data
    # Only runs when debug mode is enabled
    # Provides search and IR graph visualization
    class DebugServer
      DEFAULT_PORT = 7010

      def initialize(global_state, runtime_adapter, port: DEFAULT_PORT)
        @global_state = global_state
        @runtime_adapter = runtime_adapter
        @graph_builder = GraphBuilder.new(runtime_adapter)
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
        warn("[TypeGuessr DebugServer] Listening on 127.0.0.1:#{@port}")

        while @running
          begin
            client = @server.accept
            handle_request(client)
          rescue IOError, Errno::EBADF
            # Server closed, exit gracefully
            break
          rescue StandardError => e
            warn("[TypeGuessr DebugServer] Request error: #{e.class}: #{e.message}")
            warn("[TypeGuessr DebugServer] #{e.backtrace&.first(3)&.join("\n")}")
          end
        end
      rescue Errno::EADDRINUSE
        warn("[TypeGuessr DebugServer] Port #{@port} is already in use")
      rescue StandardError => e
        warn("[TypeGuessr DebugServer] Server error: #{e.class}: #{e.message}")
        warn("[TypeGuessr DebugServer] #{e.backtrace&.first(5)&.join("\n")}")
      end

      def handle_request(client)
        request_line = client.gets
        return client.close if request_line.nil?

        method, full_path, = request_line.split
        return client.close if method != "GET"

        # Read headers (discard them)
        while (line = client.gets) && line != "\r\n"
          # skip headers
        end

        # Parse path and query string
        path, query_string = full_path.split("?", 2)
        params = parse_query_string(query_string)

        response = route_request(path, params)
        send_response(client, response)
      ensure
        client.close
      end

      def parse_query_string(query_string)
        return {} unless query_string

        query_string.split("&").to_h do |pair|
          key, value = pair.split("=", 2)
          [key, CGI.unescape(value || "")]
        end
      end

      def route_request(path, params)
        case path
        when "/"
          index_page
        when "/api/search"
          search_api(params["q"] || "")
        when "/api/graph"
          graph_api(params["node_key"] || "")
        when "/api/keys"
          keys_api(params["q"] || "")
        when "/graph"
          graph_page(params["node_key"] || "")
        else
          not_found
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

      # API Endpoints

      def search_api(query)
        return json_response({ query: query, results: [] }) if query.empty?

        results = @runtime_adapter.search_project_methods(query)
        json_response({ query: query, results: results })
      end

      def keys_api(query)
        all_keys = @runtime_adapter.instance_variable_get(:@location_index)
                                   .instance_variable_get(:@key_index).keys
        keys = if query.empty?
                 all_keys.first(100)
               else
                 all_keys.select { |k| k.include?(query) }.first(100)
               end
        json_response({ query: query, total: all_keys.size, keys: keys })
      end

      def graph_api(node_key)
        return json_error("node_key parameter required", 400) if node_key.empty?

        begin
          warn("[TypeGuessr DebugServer] graph_api called with: #{node_key}")
          graph_data = @graph_builder.build(node_key)
          warn("[TypeGuessr DebugServer] graph_data built: #{graph_data ? "success" : "nil"}")

          unless graph_data
            # Debug: show available keys that start with similar prefix
            all_keys = @runtime_adapter.instance_variable_get(:@location_index)
                                       .instance_variable_get(:@key_index).keys
            similar = all_keys.select { |k| k.include?(node_key.split(":").first) }.first(10)
            return json_error("Node not found: #{node_key}. Similar keys: #{similar}", 404)
          end

          json_response(graph_data)
        rescue StandardError => e
          warn("[TypeGuessr DebugServer] graph_api error: #{e.class}: #{e.message}")
          warn("[TypeGuessr DebugServer] #{e.backtrace&.first(5)&.join("\n")}")
          json_error("Internal error: #{e.message}", 500)
        end
      end

      def json_response(data)
        {
          status: "200 OK",
          content_type: "application/json; charset=utf-8",
          body: JSON.generate(data)
        }
      end

      def json_error(message, status_code)
        status_text = status_code == 404 ? "Not Found" : "Bad Request"
        {
          status: "#{status_code} #{status_text}",
          content_type: "application/json; charset=utf-8",
          body: JSON.generate({ error: message })
        }
      end

      def not_found
        {
          status: "404 Not Found",
          content_type: "text/html; charset=utf-8",
          body: "<h1>404 Not Found</h1>"
        }
      end

      # HTML Pages

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
                * { box-sizing: border-box; }
                body {
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
                  margin: 0;
                  padding: 20px;
                  background: #1e1e1e;
                  color: #d4d4d4;
                }
                .container { max-width: 900px; margin: 0 auto; }
                h1 { color: #569cd6; margin-bottom: 10px; }
                .subtitle { color: #808080; margin-bottom: 30px; }
                .search-box { margin-bottom: 20px; }
                .search-box input {
                  width: 100%;
                  padding: 12px 16px;
                  font-size: 16px;
                  background: #2d2d2d;
                  border: 1px solid #3e3e3e;
                  color: #d4d4d4;
                  border-radius: 6px;
                  outline: none;
                }
                .search-box input:focus { border-color: #569cd6; }
                .search-box input::placeholder { color: #808080; }
                .results { margin-top: 20px; }
                .result-item {
                  padding: 14px 16px;
                  margin: 8px 0;
                  background: #2d2d2d;
                  border-left: 3px solid #569cd6;
                  border-radius: 0 6px 6px 0;
                  cursor: pointer;
                  transition: background 0.15s, transform 0.1s;
                  display: flex;
                  justify-content: space-between;
                  align-items: center;
                }
                .result-item:hover { background: #3e3e3e; transform: translateX(4px); }
                .class-name { color: #4ec9b0; font-weight: 600; }
                .method-name { color: #dcdcaa; }
                .location { color: #808080; font-size: 0.9em; }
                .empty-state {
                  text-align: center;
                  padding: 40px;
                  color: #808080;
                }
                .stats {
                  margin-top: 30px;
                  padding: 15px;
                  background: #2d2d2d;
                  border-radius: 6px;
                  font-size: 0.9em;
                  color: #808080;
                }
              </style>
            </head>
            <body>
              <div class="container">
                <h1>TypeGuessr Debug Console</h1>
                <p class="subtitle">Search for classes and methods to visualize their IR dependency graphs</p>

                <div class="search-box">
                  <input type="text" id="search" placeholder="Search methods (e.g., User#save, Recipe, save)" autofocus>
                </div>

                <div id="results" class="results">
                  <div class="empty-state">Type to search for methods...</div>
                </div>

                <div class="stats" id="stats">Loading stats...</div>
              </div>

              <script>
                const searchInput = document.getElementById('search');
                const resultsDiv = document.getElementById('results');
                const statsDiv = document.getElementById('stats');
                let debounceTimer;

                // Load stats
                const stats = #{JSON.generate(@runtime_adapter.stats)};
                statsDiv.textContent = `Indexed: ${stats.files_count} files, ${stats.total_nodes} nodes`;

                searchInput.addEventListener('input', (e) => {
                  clearTimeout(debounceTimer);
                  debounceTimer = setTimeout(() => search(e.target.value), 300);
                });

                async function search(query) {
                  if (query.length < 1) {
                    resultsDiv.innerHTML = '<div class="empty-state">Type to search for methods...</div>';
                    return;
                  }

                  try {
                    const response = await fetch(`/api/search?q=${encodeURIComponent(query)}`);
                    const data = await response.json();
                    displayResults(data.results);
                  } catch (error) {
                    resultsDiv.innerHTML = '<div class="empty-state">Error searching...</div>';
                  }
                }

                function displayResults(results) {
                  if (results.length === 0) {
                    resultsDiv.innerHTML = '<div class="empty-state">No results found</div>';
                    return;
                  }

                  resultsDiv.innerHTML = results.map(r => `
                    <div class="result-item" onclick="viewGraph('${encodeURIComponent(r.node_key)}')">
                      <div>
                        <span class="class-name">${escapeHtml(r.class_name)}</span>#<span class="method-name">${escapeHtml(r.method_name)}</span>
                      </div>
                      <span class="location">Line ${r.location.line || '?'}</span>
                    </div>
                  `).join('');
                }

                function escapeHtml(text) {
                  const div = document.createElement('div');
                  div.textContent = text;
                  return div.innerHTML;
                }

                function viewGraph(nodeKey) {
                  window.location.href = `/graph?node_key=${nodeKey}`;
                }
              </script>
            </body>
            </html>
          HTML
        }
      end

      def graph_page(node_key)
        return not_found if node_key.empty?

        {
          status: "200 OK",
          content_type: "text/html; charset=utf-8",
          body: <<~HTML
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>IR Graph - TypeGuessr</title>
              <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
              <style>
                * { box-sizing: border-box; }
                body {
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
                  margin: 0;
                  padding: 20px;
                  background: #1e1e1e;
                  color: #d4d4d4;
                }
                .container { max-width: 1400px; margin: 0 auto; }
                h1 { color: #569cd6; margin: 10px 0; font-size: 1.5em; }
                .back-link {
                  color: #569cd6;
                  text-decoration: none;
                  display: inline-block;
                  margin-bottom: 10px;
                }
                .back-link:hover { text-decoration: underline; }
                .graph-container {
                  position: relative;
                }
                .zoom-controls {
                  position: absolute;
                  top: 10px;
                  right: 10px;
                  z-index: 10;
                  display: flex;
                  gap: 4px;
                }
                .zoom-btn {
                  width: 32px;
                  height: 32px;
                  border: 1px solid #ccc;
                  background: #fff;
                  border-radius: 4px;
                  cursor: pointer;
                  font-size: 18px;
                  font-weight: bold;
                  color: #333;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                }
                .zoom-btn:hover { background: #f0f0f0; }
                .zoom-btn:active { background: #e0e0e0; }
                #graph {
                  background: #ffffff;
                  padding: 20px;
                  border-radius: 6px;
                  overflow: auto;
                  min-height: 600px;
                  cursor: grab;
                }
                #graph.dragging {
                  cursor: grabbing;
                  user-select: none;
                }
                #graph svg {
                  transform-origin: top left;
                  transition: transform 0.1s ease;
                }
                .node-details {
                  margin-top: 20px;
                  padding: 16px;
                  background: #2d2d2d;
                  border-radius: 6px;
                  display: none;
                }
                .node-details.visible { display: block; }
                .def-inspect {
                  margin-top: 20px;
                  padding: 16px;
                  background: #2d2d2d;
                  border-radius: 6px;
                }
                .def-inspect h3 { color: #4ec9b0; margin: 0 0 12px 0; font-size: 1.1em; }
                .def-inspect pre {
                  background: #1e1e1e;
                  padding: 12px;
                  border-radius: 4px;
                  overflow-x: auto;
                  font-size: 0.85em;
                  white-space: pre-wrap;
                  word-break: break-all;
                  color: #d4d4d4;
                  margin: 0;
                }
                .node-details h3 { color: #4ec9b0; margin: 0 0 12px 0; font-size: 1.1em; }
                .detail-row { margin: 6px 0; font-size: 0.95em; }
                .detail-label { color: #808080; display: inline-block; width: 120px; }
                .detail-value { color: #d4d4d4; }
                .error-state {
                  text-align: center;
                  padding: 60px;
                  color: #f48771;
                }
                .loading-state {
                  text-align: center;
                  padding: 60px;
                  color: #808080;
                }
              </style>
            </head>
            <body>
              <div class="container">
                <a href="/" class="back-link">&larr; Back to search</a>
                <h1>IR Dependency Graph</h1>

                <div class="graph-container">
                  <div class="zoom-controls">
                    <button class="zoom-btn" onclick="zoomIn()" title="Zoom In">+</button>
                    <button class="zoom-btn" onclick="zoomOut()" title="Zoom Out">−</button>
                    <button class="zoom-btn" onclick="resetZoom()" title="Reset">⟲</button>
                  </div>
                  <div id="graph">
                    <div class="loading-state">Loading graph...</div>
                  </div>
                </div>

                <div id="node-details" class="node-details">
                  <h3>Node Details</h3>
                  <div id="details-content"></div>
                </div>

                <div id="def-inspect" class="def-inspect">
                  <h3>DefNode Inspect</h3>
                  <pre id="inspect-content"></pre>
                </div>
              </div>

              <script>
                const nodeKey = #{JSON.generate(node_key)};
                let graphData = null;

                mermaid.initialize({
                  startOnLoad: false,
                  theme: 'default',
                  securityLevel: 'loose',
                  flowchart: { curve: 'basis' }
                });

                // Zoom functionality
                let currentZoom = 1;
                const ZOOM_STEP = 0.2;
                const MIN_ZOOM = 0.3;
                const MAX_ZOOM = 3;

                function zoomIn() {
                  currentZoom = Math.min(currentZoom + ZOOM_STEP, MAX_ZOOM);
                  applyZoom();
                }

                function zoomOut() {
                  currentZoom = Math.max(currentZoom - ZOOM_STEP, MIN_ZOOM);
                  applyZoom();
                }

                function resetZoom() {
                  currentZoom = 1;
                  applyZoom();
                }

                function applyZoom() {
                  const svg = document.querySelector('#graph svg');
                  if (svg) {
                    svg.style.transform = `scale(${currentZoom})`;
                  }
                }

                // Drag to pan functionality
                let isDragging = false;
                let startX, startY, scrollLeft, scrollTop;

                function initDrag() {
                  const graphDiv = document.getElementById('graph');

                  // Mouse wheel zoom
                  graphDiv.addEventListener('wheel', (e) => {
                    e.preventDefault();
                    if (e.deltaY < 0) {
                      zoomIn();
                    } else {
                      zoomOut();
                    }
                  }, { passive: false });

                  graphDiv.addEventListener('mousedown', (e) => {
                    if (e.target.closest('.node')) return; // Don't drag when clicking nodes
                    isDragging = true;
                    graphDiv.classList.add('dragging');
                    startX = e.pageX - graphDiv.offsetLeft;
                    startY = e.pageY - graphDiv.offsetTop;
                    scrollLeft = graphDiv.scrollLeft;
                    scrollTop = graphDiv.scrollTop;
                  });

                  graphDiv.addEventListener('mouseleave', () => {
                    isDragging = false;
                    graphDiv.classList.remove('dragging');
                  });

                  graphDiv.addEventListener('mouseup', () => {
                    isDragging = false;
                    graphDiv.classList.remove('dragging');
                  });

                  graphDiv.addEventListener('mousemove', (e) => {
                    if (!isDragging) return;
                    e.preventDefault();
                    const x = e.pageX - graphDiv.offsetLeft;
                    const y = e.pageY - graphDiv.offsetTop;
                    const walkX = (x - startX) * 1.5;
                    const walkY = (y - startY) * 1.5;
                    graphDiv.scrollLeft = scrollLeft - walkX;
                    graphDiv.scrollTop = scrollTop - walkY;
                  });
                }

                async function loadGraph() {
                  const graphDiv = document.getElementById('graph');

                  try {
                    const response = await fetch(`/api/graph?node_key=${encodeURIComponent(nodeKey)}`);
                    const data = await response.json();

                    if (data.error) {
                      graphDiv.innerHTML = `<div class="error-state">Error: ${data.error}</div>`;
                      return;
                    }

                    graphData = data;
                    renderGraph();
                    showDefInspect(data.def_node_inspect);
                  } catch (error) {
                    graphDiv.innerHTML = `<div class="error-state">Failed to load graph: ${error.message}</div>`;
                  }
                }

                function showDefInspect(inspectStr) {
                  const inspectDiv = document.getElementById('def-inspect');
                  const contentPre = document.getElementById('inspect-content');
                  if (inspectStr) {
                    contentPre.textContent = inspectStr;
                    inspectDiv.style.display = 'block';
                  } else {
                    inspectDiv.style.display = 'none';
                  }
                }

                async function renderGraph() {
                  const mermaidCode = generateMermaidCode(graphData);

                  const graphDiv = document.getElementById('graph');
                  graphDiv.innerHTML = '';

                  try {
                    const { svg } = await mermaid.render('mermaid-graph', mermaidCode);
                    graphDiv.innerHTML = svg;
                    // Add click handlers to nodes
                    addNodeClickHandlers();
                  } catch (error) {
                    graphDiv.innerHTML = `<div class="error-state">Failed to render graph: ${error.message}</div>`;
                  }
                }

                function generateMermaidCode(data) {
                  let code = `graph BT\\n`;

                  // Add class definitions for styling
                  code += `  classDef defNode fill:#569cd6,stroke:#333,color:#fff\\n`;
                  code += `  classDef callNode fill:#a3be8c,stroke:#333,color:#000\\n`;
                  code += `  classDef varWriteNode fill:#d08770,stroke:#333,color:#fff\\n`;
                  code += `  classDef varReadNode fill:#e5ac6b,stroke:#333,color:#000\\n`;
                  code += `  classDef paramNode fill:#b48ead,stroke:#333,color:#fff\\n`;
                  code += `  classDef literalNode fill:#808080,stroke:#333,color:#fff\\n`;
                  code += `  classDef mergeNode fill:#ebcb8b,stroke:#333,color:#000\\n`;
                  code += `  classDef blockParamNode fill:#88c0d0,stroke:#333,color:#000\\n`;
                  code += `  classDef returnNode fill:#c586c0,stroke:#333,color:#fff\\n`;
                  code += `  classDef constNode fill:#4ec9b0,stroke:#333,color:#000\\n`;
                  code += `  classDef otherNode fill:#4c566a,stroke:#333,color:#fff\\n`;

                  // Categorize nodes
                  const defNode = data.nodes.find(n => n.type === 'DefNode');
                  const defNodeKey = defNode?.key;
                  const paramNodes = data.nodes.filter(n => n.type === 'ParamNode');
                  const callNodes = data.nodes.filter(n => n.type === 'CallNode');

                  // Build edge lookup: which nodes point to which
                  const edgesFrom = new Map(); // from -> [to, ...]
                  data.edges.forEach(edge => {
                    if (!edgesFrom.has(edge.from)) edgesFrom.set(edge.from, []);
                    edgesFrom.get(edge.from).push(edge.to);
                  });

                  // Track nodes already rendered in subgraphs
                  const renderedInSubgraph = new Set();

                  // 1. Add DefNode at top
                  if (defNode) {
                    const id = sanitizeId(defNode.key);
                    const label = formatNodeLabel(defNode);
                    code += `  ${id}["${label}"]:::defNode\\n`;
                  }

                  // 2. Add params subgraph
                  if (paramNodes.length > 0) {
                    code += `  subgraph params\\n`;
                    code += `    direction TB\\n`;
                    paramNodes.forEach(node => {
                      const id = sanitizeId(node.key);
                      const label = formatNodeLabel(node);
                      code += `    ${id}["${label}"]:::paramNode\\n`;
                      renderedInSubgraph.add(node.key);
                    });
                    code += `  end\\n`;
                  }

                  // 3. Add CallNode subgraphs with receiver and args
                  callNodes.forEach(callNode => {
                    const deps = edgesFrom.get(callNode.key) || [];
                    if (deps.length === 0) {
                      // No dependencies, render as simple node
                      const id = sanitizeId(callNode.key);
                      const label = formatNodeLabel(callNode);
                      code += `  ${id}["${label}"]:::callNode\\n`;
                      return;
                    }

                    // Create subgraph for call with its dependencies
                    const subgraphId = sanitizeId(callNode.key) + '_sub';
                    const receiver = callNode.details?.receiver || '';
                    const method = callNode.details?.method || '';
                    const subgraphLabel = receiver ? `${receiver}.${method}` : method;
                    code += `  subgraph ${subgraphId} ["${escapeForMermaid(subgraphLabel)}"]\\n`;
                    code += `    direction TB\\n`;

                    // Add CallNode itself
                    const callId = sanitizeId(callNode.key);
                    const callLabel = formatNodeLabel(callNode);
                    code += `    ${callId}["${callLabel}"]:::callNode\\n`;

                    // Add direct dependencies (receiver, args) inside subgraph
                    deps.forEach(depKey => {
                      if (renderedInSubgraph.has(depKey)) return;
                      const depNode = data.nodes.find(n => n.key === depKey);
                      if (depNode && depNode.type !== 'DefNode' && depNode.type !== 'ParamNode') {
                        const depId = sanitizeId(depKey);
                        const depLabel = formatNodeLabel(depNode);
                        const depStyle = getNodeStyleClass(depNode.type, depNode);
                        code += `    ${depId}["${depLabel}"]:::${depStyle}\\n`;
                        renderedInSubgraph.add(depKey);
                      }
                    });

                    code += `  end\\n`;
                    renderedInSubgraph.add(callNode.key);
                  });

                  // 4. Add remaining nodes (not in any subgraph)
                  data.nodes.forEach(node => {
                    if (node.type === 'DefNode') return; // Already added
                    if (renderedInSubgraph.has(node.key)) return;
                    const id = sanitizeId(node.key);
                    const label = formatNodeLabel(node);
                    const styleClass = getNodeStyleClass(node.type, node);
                    code += `  ${id}["${label}"]:::${styleClass}\\n`;
                  });

                  // 5. Add edges (reversed direction: to --> from for BT layout)
                  // In IR: from depends on to, so arrow should be to --> from
                  data.edges.forEach(edge => {
                    const fromId = sanitizeId(edge.from);
                    const toId = sanitizeId(edge.to);
                    code += `  ${toId} --> ${fromId}\\n`;
                  });

                  return code;
                }

                function addNodeClickHandlers() {
                  const nodes = document.querySelectorAll('#graph .node');
                  nodes.forEach(nodeEl => {
                    nodeEl.style.cursor = 'pointer';
                    nodeEl.addEventListener('click', () => {
                      const nodeId = nodeEl.id;
                      const nodeData = graphData.nodes.find(n => sanitizeId(n.key) === nodeId);
                      if (nodeData) showNodeDetails(nodeData);
                    });
                  });
                }

                function showNodeDetails(node) {
                  const detailsDiv = document.getElementById('node-details');
                  const contentDiv = document.getElementById('details-content');

                  let html = `<div class="detail-row"><span class="detail-label">Type:</span><span class="detail-value">${node.type}</span></div>`;
                  html += `<div class="detail-row"><span class="detail-label">Key:</span><span class="detail-value" style="font-size:0.85em">${node.key}</span></div>`;
                  html += `<div class="detail-row"><span class="detail-label">Line:</span><span class="detail-value">${node.line || '-'}</span></div>`;
                  html += `<div class="detail-row"><span class="detail-label">Inferred Type:</span><span class="detail-value">${node.inferred_type || 'Unknown'}</span></div>`;

                  if (node.details) {
                    html += '<hr style="border-color:#3e3e3e;margin:12px 0">';
                    Object.entries(node.details).forEach(([key, value]) => {
                      const displayValue = Array.isArray(value) ? value.join(', ') || '(none)' :
                                          typeof value === 'object' ? JSON.stringify(value) : value;
                      html += `<div class="detail-row"><span class="detail-label">${key}:</span><span class="detail-value">${displayValue}</span></div>`;
                    });
                  }

                  contentDiv.innerHTML = html;
                  detailsDiv.classList.add('visible');
                }

                function formatNodeLabel(node) {
                  const d = node.details || {};

                  // Format based on node type
                  if (node.type === 'DefNode') {
                    // Show full method signature: def name(param: Type, ...) -> ReturnType
                    const params = (d.param_signatures || []).join(', ');
                    const returnType = node.inferred_type || 'untyped';
                    return escapeForMermaid(`def ${d.name}(${params})\\n-> ${returnType}`);
                  }

                  if (node.type === 'ParamNode') {
                    // param_name: Type
                    const type = node.inferred_type || 'Unknown';
                    return escapeForMermaid(`${d.name}: ${type}\\n(${d.kind} param)`);
                  }

                  if (node.type.endsWith('WriteNode')) {
                    // var_name: Type (name already includes @ or @@ prefix)
                    const type = node.inferred_type || 'Unknown';
                    return escapeForMermaid(`${d.name}: ${type}\\n(write, L${node.line})`);
                  }

                  if (node.type.endsWith('ReadNode')) {
                    // var_name: Type (name already includes @ or @@ prefix)
                    const type = node.inferred_type || 'Unknown';
                    return escapeForMermaid(`${d.name}: ${type}\\n(read, L${node.line})`);
                  }

                  if (node.type === 'CallNode') {
                    const type = node.inferred_type && node.inferred_type !== 'Unknown' ? ` -> ${node.inferred_type}` : '';
                    const block = d.has_block ? ' { }' : '';
                    const receiver = d.receiver ? `${d.receiver}.` : '';
                    return escapeForMermaid(`${receiver}${d.method}${block}${type}\\n(L${node.line})`);
                  }

                  if (node.type === 'LiteralNode') {
                    return escapeForMermaid(`${d.literal_type}\\n(L${node.line})`);
                  }

                  if (node.type === 'MergeNode') {
                    return escapeForMermaid(`Merge (${d.branches_count} branches)\\n(L${node.line})`);
                  }

                  // Default format for other nodes
                  let label = node.type;
                  if (d.name) label += `: ${d.name}`;
                  else if (d.method) label += `: ${d.method}`;
                  else if (d.index !== undefined) label += ` [${d.index}]`;
                  if (node.line) label += ` (L${node.line})`;
                  if (node.inferred_type && node.inferred_type !== 'Unknown') {
                    label += `\\n-> ${node.inferred_type}`;
                  }
                  return escapeForMermaid(label);
                }

                function escapeForMermaid(text) {
                  return text
                    .replace(/"/g, "'")
                    .replace(/\\[/g, '#91;')
                    .replace(/\\]/g, '#93;')
                    .replace(/</g, '#lt;')
                    .replace(/>/g, '#gt;');
                }

                function getNodeStyleClass(nodeType, node) {
                  if (nodeType.endsWith('WriteNode')) return 'varWriteNode';
                  if (nodeType.endsWith('ReadNode')) return 'varReadNode';
                  const styles = {
                    DefNode: 'defNode',
                    CallNode: 'callNode',
                    ParamNode: 'paramNode',
                    LiteralNode: 'literalNode',
                    MergeNode: 'mergeNode',
                    BlockParamSlot: 'blockParamNode'
                  };
                  return styles[nodeType] || 'otherNode';
                }

                function sanitizeId(key) {
                  return 'n_' + key.replace(/[^a-zA-Z0-9]/g, '_');
                }

                // Initial load
                loadGraph();
                initDrag();
              </script>
            </body>
            </html>
          HTML
        }
      end
    end
  end
end
