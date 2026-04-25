# frozen_string_literal: true

require "optparse"
require "json"
require_relative "../runtime/client"
require_relative "../runtime/method_call_collector"

module TypeGuessr
  module CLI
    # Zero-candidate checker: finds variables/parameters where no class
    # defines ALL called methods (potential NoMethodError sites).
    #
    # Uses RuntimeClient (ObjectSpace) for method index — no ruby-lsp dependency.
    module Check
      def self.run(argv)
        options = parse_options(argv)
        project_root = File.expand_path(options[:path] || Dir.pwd)

        log(options, "=== type-guessr check ===")
        log(options, "Project: #{project_root}")

        boot_file = options[:boot] || detect_boot_file(project_root)
        log(options, "Boot: #{boot_file || "(bundler/setup only)"}")
        log(options, "")

        project_files = collect_project_files(project_root)
        log(options, "Project files: #{project_files.size}")
        log(options, "")

        log(options, "Starting runtime server...")
        client = Runtime::Client.new(project_path: project_root, boot_file: boot_file)
        client.start
        log(options, "Runtime: #{client.module_count} modules, #{client.method_count} methods")
        log(options, "")

        log(options, "Analyzing source files...")
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
        zero_candidates = find_zero_candidates(client, all_findings, project_root)
        client.shutdown

        if options[:json]
          output_json(zero_candidates, project_root)
        else
          output_text(zero_candidates, project_files.size)
        end
      end

      def self.parse_options(argv)
        options = { path: nil, boot: nil, json: false }

        OptionParser.new do |opts|
          opts.banner = "Usage: type-guessr check [options]"

          opts.on("--path=PATH", "Project directory to analyze") { |v| options[:path] = v }
          opts.on("--boot=FILE", "Boot file for runtime server") { |v| options[:boot] = v }
          opts.on("--json", "Output in JSON format") { options[:json] = true }
          opts.on("-h", "--help", "Show this help") do
            puts opts
            exit
          end
        end.parse!(argv)

        options
      end

      def self.detect_boot_file(project_root)
        rails_env = File.join(project_root, "config", "environment.rb")
        File.exist?(rails_env) ? rails_env : nil
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
            called_methods: finding.called_methods,
          }
        end

        zero_candidates
      end

      def self.output_text(findings, file_count)
        if findings.empty?
          puts "No zero-candidate nodes found in #{file_count} project files."
          return
        end

        puts "Found #{findings.size} zero-candidate node(s) in #{file_count} project files:"
        puts

        findings.group_by { |f| f[:file] }.each do |file, file_findings|
          puts "#{file}:"
          file_findings.each do |f|
            puts "  L#{f[:line]}  #{f[:node_type]}  #{f[:name]}  [#{f[:called_methods].join(", ")}]"
          end
          puts
        end
      end

      def self.output_json(findings, project_root)
        puts JSON.pretty_generate({
          project: project_root,
          total: findings.size,
          findings: findings,
        })
      end

      def self.log(options, msg = "")
        $stderr.puts msg unless options[:json]
      end

      private_class_method :parse_options, :detect_boot_file, :collect_project_files,
                           :find_zero_candidates, :output_text, :output_json, :log
    end
  end
end
