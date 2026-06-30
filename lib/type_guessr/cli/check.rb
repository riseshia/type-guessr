# frozen_string_literal: true

require "optparse"
require "json"
require_relative "../runtime/client"
require_relative "../runtime/index_adapter"

module TypeGuessr
  module CLI
    # Checks project source files for potential type errors.
    #
    # Default mode: full inference engine (PrismConverter → IR → Resolver).
    # --fast mode: lightweight method-set intersection (MethodCallCollector).
    module Check
      def self.run(argv)
        options = parse_options(argv)
        project_root = Dir.pwd
        t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        log(options, "=== type-guessr check ===")
        log(options, "Project: #{project_root}")
        log(options, "Mode: #{options[:fast] ? "fast (method-set intersection)" : "full (inference engine)"}")

        boot = detect_boot(project_root, options[:boot])
        case boot[:mode]
        when :rails
          log(options, "Boot: bin/rails runner")
        when :boot_file
          log(options, "Boot: #{boot[:file]}")
        else
          warn "Error: No boot method found."
          warn ""
          warn "type-guessr needs to load your app code. Use one of:"
          warn "  1. Create .type-guessr-boot.rb in project root"
          warn "  2. Use --boot=FILE to specify an entrypoint"
          warn "  3. Rails projects are auto-detected via bin/rails"
          exit 1
        end
        log(options, "")

        t_boot_detect = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        project_files = collect_project_files(project_root)
        log(options, "Project files: #{project_files.size}")
        log(options, "")

        t_collect = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        log(options, "Starting runtime server...")
        client = Runtime::Client.new(
          project_path: project_root,
          boot_file: boot[:file],
          rails: boot[:mode] == :rails
        )
        client.start
        log(options, "Runtime: #{client.module_count} modules, #{client.method_count} methods")
        log(options, "")

        t_runtime = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        findings = if options[:fast]
                     run_fast_mode(client, project_files, project_root, options)
                   else
                     run_full_mode(client, project_files, project_root, options)
                   end

        t_analyze = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        client.shutdown

        t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        if options[:json]
          output_json(findings, project_root)
        else
          output_text(findings, project_files.size, fast: options[:fast])
        end

        log(options, "--- Timing ---")
        log(options, "  Boot detect:    #{format("%.3f", t_boot_detect - t_start)}s")
        log(options, "  File collect:   #{format("%.3f", t_collect - t_boot_detect)}s")
        log(options, "  Runtime start:  #{format("%.3f", t_runtime - t_collect)}s")
        log(options, "  Analysis:       #{format("%.3f", t_analyze - t_runtime)}s")
        log(options, "  Shutdown:       #{format("%.3f", t_end - t_analyze)}s")
        log(options, "  Total:          #{format("%.3f", t_end - t_start)}s")
      end

      # Fast mode: lightweight MethodCallCollector + runtime Set intersection.
      def self.run_fast_mode(client, project_files, project_root, options)
        require_relative "../runtime/method_call_collector"

        log(options, "Analyzing source files (fast)...")
        collector = Runtime::MethodCallCollector.new
        all_findings = []
        project_files.each do |file_path|
          source = File.read(file_path)
          all_findings.concat(collector.collect(file_path, source))
        rescue StandardError => e
          log(options, "  Error: #{file_path}: #{e.message}")
        end
        log(options, "Found #{all_findings.size} variables/params with method calls")
        log(options, "")

        log(options, "Checking against runtime index...")
        find_zero_candidates(client, all_findings, project_root)
      end

      # Full mode: PrismConverter → IR → Resolver per file.
      def self.run_full_mode(client, project_files, project_root, options)
        require_relative "analyzer"

        code_index = Runtime::IndexAdapter.new(client)

        log(options, "Analyzing source files (full inference)...")
        result = Analyzer.analyze(
          project_files,
          code_index: code_index,
          on_error: ->(file, e) { log(options, "  Error: #{file}: #{e.message}") }
        )
        log(options, "Found #{result.findings.size} zero-candidate node(s)")
        log(options, "  (#{result.skipped_count} skipped: Unknown type — inference gap, not an error)")
        log(options, "")

        # Convert Analyzer::Finding to output hash
        result.findings.map do |f|
          rel_path = f.file.delete_prefix("#{project_root}/")
          {
            file: rel_path,
            line: f.line,
            node_type: f.node_type,
            name: f.name,
            reason: f.reason
          }
        end
      end

      def self.parse_options(argv)
        options = { boot: nil, json: false, fast: false }

        OptionParser.new do |opts|
          opts.banner = "Usage: type-guessr check [options]"

          opts.on("--boot=FILE", "Entrypoint file to load (e.g., config/environment.rb)") { |v| options[:boot] = v }
          opts.on("--fast", "Fast mode: method-set intersection (less precise)") { options[:fast] = true }
          opts.on("--json", "Output in JSON format") { options[:json] = true }
          opts.on("-h", "--help", "Show this help") do
            puts opts
            exit
          end
        end.parse!(argv)

        options
      end

      # Boot resolution order:
      # 1. --boot flag (explicit boot file)
      # 2. .type-guessr-boot.rb (project-specific boot script)
      # 3. bin/rails runner (Rails project)
      # Returns :none if nothing found (caller should abort).
      def self.detect_boot(project_root, explicit_boot)
        return { mode: :boot_file, file: File.expand_path(explicit_boot, project_root) } if explicit_boot

        custom_boot = File.join(project_root, ".type-guessr-boot.rb")
        return { mode: :boot_file, file: custom_boot } if File.exist?(custom_boot)

        rails_bin = File.join(project_root, "bin", "rails")
        return { mode: :rails, file: nil } if File.exist?(rails_bin)

        { mode: :none, file: nil }
      end

      def self.collect_project_files(project_root)
        Dir.glob(File.join(project_root, "**", "*.rb"))
           .reject { |f| f.include?("/vendor/") || f.include?("/node_modules/") }
           .reject { |f| f.include?("/spec/") || f.include?("/test/") }
           .sort
      end

      def self.find_zero_candidates(client, findings, project_root)
        cache = {}
        zero_candidates = []

        findings.each do |finding|
          key = finding.called_methods.sort
          cache[key] ||= client.find_classes(finding.called_methods)

          response = cache[key]
          next if response["filtered"] == "all_object_methods"

          classes = response["result"] || []
          next unless classes.empty?

          rel_path = finding.file.delete_prefix("#{project_root}/")
          zero_candidates << {
            file: rel_path,
            line: finding.line,
            node_type: finding.node_type,
            name: finding.name,
            called_methods: finding.called_methods
          }
        end

        zero_candidates
      end

      def self.output_text(findings, file_count, fast: false)
        if findings.empty?
          puts "No issues found in #{file_count} project files."
          return
        end

        label = "zero-candidate node"
        puts "Found #{findings.size} #{label}(s) in #{file_count} project files:"
        puts

        findings.group_by { |f| f[:file] }.each do |file, file_findings|
          puts "#{file}:"
          file_findings.each do |f|
            detail = if fast
                       "[#{f[:called_methods].join(", ")}]"
                     else
                       "(#{f[:reason]})"
                     end
            puts "  L#{f[:line]}  #{f[:node_type]}  #{f[:name]}  #{detail}"
          end
          puts
        end
      end

      def self.output_json(findings, project_root)
        puts JSON.pretty_generate({
                                    project: project_root,
                                    total: findings.size,
                                    findings: findings
                                  })
      end

      def self.log(options, msg = "")
        warn msg unless options[:json]
      end

      private_class_method :parse_options, :detect_boot, :collect_project_files,
                           :find_zero_candidates, :output_text, :output_json, :log,
                           :run_fast_mode, :run_full_mode
    end
  end
end
