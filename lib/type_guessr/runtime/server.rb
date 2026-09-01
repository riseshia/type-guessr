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

# --- Protocol channel isolation ---

# Reserve the real stdout for the JSON IPC protocol, then redirect $stdout to
# stderr. The target app may log to stdout (e.g. Logger "E, [..] ERROR" lines)
# during boot/eager_load; without this, that output corrupts the protocol
# stream and the client fails to parse the ready handshake.
PROTOCOL_OUT = $stdout.dup
$stdout.reopen($stderr)
$stdout.sync = true

# --- Boot ---

# When launched via `rails runner`, the app is already loaded.
# Otherwise, require bundler/setup and optionally a boot file.
unless defined?(Rails)
  boot_file = ARGV[0]

  require "bundler/setup"

  if boot_file
    boot_path = File.expand_path(boot_file)
    warn "[runtime-server] Booting: #{boot_path}"
    require boot_path
  end
end

# --- Eager load ---

if defined?(Rails)
  Rails.application.eager_load!
  warn "[runtime-server] Eager loaded Rails application"
end

# --- Materialize lazy-defined methods ---

# ActiveRecord defines column accessors lazily (on first attribute access),
# so a freshly eager-loaded app has none of them in public_instance_methods.
# Force definition before building the index; requires a schema connection,
# so skip models whose connection/table is unavailable.
if defined?(ActiveRecord::Base)
  defined_count = 0
  ActiveRecord::Base.descendants.each do |model|
    model.define_attribute_methods
    defined_count += 1
  rescue StandardError
    # No connection, missing table, abstract class, etc.
  end
  warn "[runtime-server] Defined attribute methods for #{defined_count} ActiveRecord models"
end

# --- Build index ---

warn "[runtime-server] Building runtime index..."

OBJECT_METHODS = Object.public_instance_methods(true).to_set
OBJECT_CLASS_METHODS = Object.singleton_class.public_instance_methods(true).to_set
METHOD_INDEX = Hash.new { |h, k| h[k] = Set.new } # method_name (Symbol) → Set[class_name]
CLASS_MAP = {} # rubocop:disable Style/MutableConstant -- populated below

# Apps may override Module#name (or define a conflicting instance method on a
# module, e.g. Paperclip::Interpolations); always go through the original.
MODULE_NAME = Module.instance_method(:name)

ObjectSpace.each_object(Module) do |mod|
  mod_name = MODULE_NAME.bind_call(mod)
  next unless mod_name

  CLASS_MAP[mod_name] = mod

  # Instance methods
  mod.public_instance_methods(true).each do |m|
    METHOD_INDEX[m] << mod_name unless OBJECT_METHODS.include?(m)
  end

  # Class methods (singleton class) — scopes, class_methods blocks, etc.
  if mod.is_a?(Class)
    mod.singleton_class.public_instance_methods(true).each do |m|
      METHOD_INDEX[m] << mod_name unless OBJECT_CLASS_METHODS.include?(m)
    end
  end
rescue StandardError
  # Skip modules that cause issues (e.g., overridden .name)
end

warn "[runtime-server] Ready: #{CLASS_MAP.size} modules, #{METHOD_INDEX.size} methods"

PROTOCOL_OUT.puts JSON.generate({ "status" => "ready", "modules" => CLASS_MAP.size, "methods" => METHOD_INDEX.size })
PROTOCOL_OUT.flush

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
                 { "result" => klass.ancestors.filter_map { |m| MODULE_NAME.bind_call(m) } }
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
               owner = (klass.method(method_name.to_sym).owner.name if klass.respond_to?(method_name.to_sym))
               { "result" => owner }

             when "instance_method_owner"
               class_name = request.dig("args", "class_name")
               method_name = request.dig("args", "method_name")
               klass = CLASS_MAP[class_name]
               owner = (klass.instance_method(method_name.to_sym).owner.name if klass&.method_defined?(method_name.to_sym))
               { "result" => owner }

             when "shutdown"
               PROTOCOL_OUT.puts JSON.generate({ "result" => "bye" })
               PROTOCOL_OUT.flush
               exit 0

             else
               { "error" => "unknown method: #{request["method"]}" }
             end

  PROTOCOL_OUT.puts JSON.generate(response)
  PROTOCOL_OUT.flush
rescue SystemExit
  raise
rescue StandardError => e
  # A single bad query (e.g. app code raising from an ancestors walk) must not
  # kill the server — exactly one response per request keeps the protocol in sync.
  PROTOCOL_OUT.puts JSON.generate({ "error" => "#{e.class}: #{e.message}" })
  PROTOCOL_OUT.flush
end
