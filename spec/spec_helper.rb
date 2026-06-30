# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "type-guessr"
require "uri"

# Load all support files dynamically
Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  # Preload RBS signatures once before all tests
  config.before(:suite) do
    registry = TypeGuessr::Core::Registry::SignatureRegistry.new
    registry.preload
    TypeGuessr::Core::Registry::SignatureRegistry.instance = registry
  end

  # Disable debug logging for all tests
  config.before do
    allow(TypeGuessr::Core::Config).to receive_messages(
      debug?: false,
      debug_server_enabled?: false,
      debug_server_port: 7010
    )
  end

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.order = ENV["GENERATE_DOCS"] ? :defined : :random
  Kernel.srand config.seed
end
