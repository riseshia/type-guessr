# frozen_string_literal: true

module TypeGuessr
  module MCP
    # Watches a project directory for .rb file changes using mtime polling.
    # Detects modified, added, and deleted files and invokes a callback.
    #
    # Usage:
    #   watcher = FileWatcher.new(project_path: "/path/to/project", interval: 2) do |modified, added, removed|
    #     modified.each { |f| reindex(f) }
    #     removed.each { |f| remove(f) }
    #   end
    #   watcher.start
    class FileWatcher
      # @param project_path [String] Root directory to watch
      # @param interval [Numeric] Polling interval in seconds (default: 2)
      # @param on_change [Proc] Callback receiving (modified, added, removed) arrays
      def initialize(project_path:, on_change:, interval: 2)
        @project_path = project_path
        @interval = interval
        @on_change = on_change
        @thread = nil
        @running = false
      end

      def start
        @running = true
        @snapshot = take_snapshot
        @thread = Thread.new { poll_loop }
        @thread.abort_on_exception = true
      end

      def stop
        @running = false
        @thread&.join(5)
        @thread = nil
      end

      def running?
        @running && @thread&.alive?
      end

      private def poll_loop
        while @running
          sleep(@interval)
          check_changes
        end
      end

      private def check_changes
        current = take_snapshot
        previous = @snapshot

        modified = []
        added = []
        removed = []

        current.each do |path, mtime|
          if previous.key?(path)
            modified << path if mtime > previous[path]
          else
            added << path
          end
        end

        previous.each_key do |path|
          removed << path unless current.key?(path)
        end

        @snapshot = current

        return if modified.empty? && added.empty? && removed.empty?

        @on_change.call(modified, added, removed)
      end

      private def take_snapshot
        pattern = File.join(@project_path, "**", "*.rb")
        Dir.glob(pattern).each_with_object({}) do |path, hash|
          hash[path] = File.mtime(path)
        rescue Errno::ENOENT
          # File deleted between glob and mtime - skip
        end
      end
    end
  end
end
