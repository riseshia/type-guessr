#!/usr/bin/env ruby
# frozen_string_literal: true

# Runtime index server — subprocess that runs inside the target project's environment.
#
# Boots the project, scans ObjectSpace to build a runtime method index,
# then serves queries over stdin/stdout JSON protocol.
#
# Protocol:
#   → {"method": "find_classes", "args": {"methods": ["map", "size"]}}
#   ← {"result": ["Array", "Hash"]}
#
#   → {"method": "ancestors", "args": {"class_name": "Array"}}
#   ← {"result": ["Array", "Enumerable", "Object", ...]}
#
#   → {"method": "constant_kind", "args": {"name": "Array"}}
#   ← {"result": "class"}
#
#   → {"method": "method_defined?", "args": {"class_name": "Array", "method_name": "map"}}
#   ← {"result": true}
#
#   → {"method": "shutdown"}
#   ← (exits)

require "json"

# --- Boot ---

boot_file = ARGV[0]

require "bundler/setup"

if boot_file
  boot_path = File.expand_path(boot_file)
  $stderr.puts "[runtime-server] Booting: #{boot_path}"
  require boot_path
else
  $stderr.puts "[runtime-server] No boot file — only bundler/setup loaded"
end

# --- Build index ---

$stderr.puts "[runtime-server] Building runtime index..."

OBJECT_METHODS = Object.public_instance_methods(true).to_set
METHOD_INDEX = Hash.new { |h, k| h[k] = Set.new } # method_name (Symbol) → Set[class_name]
CLASS_MAP = {} # class_name (String) → Module

ObjectSpace.each_object(Module) do |mod|
  mod_name = Module.instance_method(:name).bind_call(mod)
  next unless mod_name

  CLASS_MAP[mod_name] = mod

  mod.public_instance_methods(true).each do |m|
    METHOD_INDEX[m] << mod_name unless OBJECT_METHODS.include?(m)
  end
rescue StandardError
  # Skip modules that cause issues (e.g., overridden .name)
end

$stderr.puts "[runtime-server] Ready: #{CLASS_MAP.size} modules, #{METHOD_INDEX.size} methods"

$stdout.puts JSON.generate({ "status" => "ready", "modules" => CLASS_MAP.size, "methods" => METHOD_INDEX.size })
$stdout.flush

# --- Query loop ---

$stdin.each_line do |line|
  request = JSON.parse(line.strip)

  response = case request["method"]
  when "find_classes"
    methods = (request.dig("args", "methods") || []).map(&:to_sym)

    meaningful = methods.reject { |m| OBJECT_METHODS.include?(m) }

    if meaningful.empty?
      { "result" => [], "filtered" => "all_object_methods" }
    else
      candidates = meaningful.filter_map { |m| METHOD_INDEX.key?(m) ? METHOD_INDEX[m] : nil }
      result = if candidates.size < meaningful.size
                 []
               else
                 candidates.reduce(:&).to_a
               end

      result = result.grep_v(/::<Class:[^>]+>\z/)

      { "result" => result }
    end

  when "ancestors"
    class_name = request.dig("args", "class_name")
    klass = CLASS_MAP[class_name]
    if klass
      { "result" => klass.ancestors.filter_map(&:name) }
    else
      { "result" => [] }
    end

  when "constant_kind"
    name = request.dig("args", "name")
    mod = CLASS_MAP[name]
    kind = if mod.nil?
             nil
           elsif mod.is_a?(Class)
             "class"
           else
             "module"
           end
    { "result" => kind }

  when "method_defined?"
    class_name = request.dig("args", "class_name")
    method_name = request.dig("args", "method_name")
    klass = CLASS_MAP[class_name]
    { "result" => klass&.method_defined?(method_name.to_sym) || false }

  when "class_method_owner"
    class_name = request.dig("args", "class_name")
    method_name = request.dig("args", "method_name")
    klass = CLASS_MAP[class_name]
    owner = if klass&.respond_to?(method_name.to_sym)
              klass.method(method_name.to_sym).owner.name
            end
    { "result" => owner }

  when "instance_method_owner"
    class_name = request.dig("args", "class_name")
    method_name = request.dig("args", "method_name")
    klass = CLASS_MAP[class_name]
    owner = if klass&.method_defined?(method_name.to_sym)
              klass.instance_method(method_name.to_sym).owner.name
            end
    { "result" => owner }

  when "shutdown"
    $stdout.puts JSON.generate({ "result" => "bye" })
    $stdout.flush
    exit 0

  else
    { "error" => "unknown method: #{request["method"]}" }
  end

  $stdout.puts JSON.generate(response)
  $stdout.flush
rescue JSON::ParserError => e
  $stdout.puts JSON.generate({ "error" => "parse error: #{e.message}" })
  $stdout.flush
end
