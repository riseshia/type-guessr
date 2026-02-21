# frozen_string_literal: true

require "bundler"

module TypeGuessr
  module Core
    module Cache
      # Resolves gem dependencies from Gemfile.lock and partitions files by gem.
      # Provides topological ordering for dependency-aware cache building.
      class GemDependencyResolver
        GEM_PATH_PATTERN = %r{/gems/([^/]+)-(\d[^/]*)/}

        # @param lockfile_path [String] Path to Gemfile.lock
        def initialize(lockfile_path)
          @lockfile_path = lockfile_path
          @lockfile = parse_lockfile
        end

        # Partition file paths into gem files and project files
        # @param file_paths [Array<String>] All indexable file paths
        # @return [Hash] { gems: { name => { version:, files:, transitive_deps: {} } }, project_files: [] }
        def partition(file_paths)
          gems = {}
          project_files = []

          file_paths.each do |path|
            match = path.match(GEM_PATH_PATTERN)
            if match
              gem_name = match[1]
              gem_version = match[2]

              # Only include gems from the lockfile
              if @lockfile.key?(gem_name)
                gems[gem_name] ||= {
                  version: gem_version,
                  files: [],
                  transitive_deps: resolve_transitive_deps(gem_name)
                }
                gems[gem_name][:files] << path
              else
                project_files << path
              end
            else
              project_files << path
            end
          end

          { gems: gems, project_files: project_files }
        end

        # Return gem names in topological order (leaves first, roots last)
        # @param gem_names [Array<String>] Gem names to sort
        # @return [Array<String>] Sorted gem names
        def topological_order(gem_names)
          visited = {}
          order = []

          gem_names.each do |name|
            visit(name, gem_names, visited, order)
          end

          order
        end

        private def parse_lockfile
          return {} unless File.exist?(@lockfile_path)

          content = File.read(@lockfile_path)
          parser = Bundler::LockfileParser.new(content)

          parser.specs.to_h do |spec|
            deps = spec.dependencies.map(&:name)
            [spec.name, { version: spec.version.to_s, deps: deps }]
          end
        end

        private def resolve_transitive_deps(gem_name)
          result = {}
          queue = (@lockfile.dig(gem_name, :deps) || []).dup
          visited = Set.new

          while (dep_name = queue.shift)
            next if visited.include?(dep_name)

            visited << dep_name

            dep_info = @lockfile[dep_name]
            next unless dep_info

            result[dep_name] = dep_info[:version]
            queue.concat(dep_info[:deps] || [])
          end

          result
        end

        private def visit(name, valid_names, visited, order)
          return if visited[name]

          visited[name] = true

          # Visit dependencies first
          deps = @lockfile.dig(name, :deps) || []
          deps.each do |dep|
            visit(dep, valid_names, visited, order) if valid_names.include?(dep)
          end

          order << name
        end
      end
    end
  end
end
