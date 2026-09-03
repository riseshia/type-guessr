# frozen_string_literal: true

# Main module for TypeGuessr
module TypeGuessr
  class Error < StandardError; end
end

require_relative "type_guessr/version"
require_relative "type_guessr/core"
