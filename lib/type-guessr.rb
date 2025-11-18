# frozen_string_literal: true

require "prism"

# Main module for TypeGuessr
module TypeGuessr
  class Error < StandardError; end

  # Analyze a single Ruby file and return type information
  # @param file_path [String] Path to the Ruby file
  # @return [FileAnalysisResult] Analysis result containing variable types
  # @raise [Error] If file doesn't exist
  def self.analyze_file(file_path)
    raise Error, "File not found: #{file_path}" unless File.exist?(file_path)

    source = File.read(file_path)
    parsed_result = Prism.parse(source)

    # Clear the singleton index for this file to ensure clean state
    variable_index = Core::VariableIndex.instance
    variable_index.clear_file(file_path)

    ast_analyzer = Core::ASTAnalyzer.new(file_path)
    ast_analyzer.visit(parsed_result.value)

    FileAnalysisResult.new(file_path, variable_index)
  end

  # Create a project-wide type inference context
  # @param root_path [String] Root directory of the project
  # @return [Project] Project instance
  # @raise [Error] If directory doesn't exist
  def self.create_project(root_path)
    raise Error, "Directory not found: #{root_path}" unless Dir.exist?(root_path)

    Project.new(root_path)
  end
end

# Load core components
require_relative "type_guessr/version"
require_relative "type_guessr/file_analysis_result"
require_relative "type_guessr/project"
require_relative "type_guessr/core/scope_resolver"
require_relative "type_guessr/core/models/parameter"
require_relative "type_guessr/core/models/method_signature"
require_relative "type_guessr/core/method_signature_index"
require_relative "type_guessr/core/rbs_indexer"
require_relative "type_guessr/core/variable_index"
require_relative "type_guessr/core/ast_analyzer"
require_relative "type_guessr/core/type_matcher"
require_relative "type_guessr/core/type_resolver"

# Load Ruby LSP integration
require_relative "type_guessr/integrations/ruby_lsp/index_adapter"
require_relative "type_guessr/integrations/ruby_lsp/type_matcher"
require_relative "type_guessr/integrations/ruby_lsp/variable_type_resolver"
require_relative "type_guessr/integrations/ruby_lsp/hover_content_builder"
require_relative "type_guessr/integrations/ruby_lsp/hover_provider"
require_relative "type_guessr/integrations/ruby_lsp/addon"

# Backward compatibility: Create aliases in old namespace
module RubyLsp
  module TypeGuessr
    # Version
    VERSION = ::TypeGuessr::VERSION

    # Core models
    Parameter = ::TypeGuessr::Core::Parameter
    MethodSignature = ::TypeGuessr::Core::MethodSignature

    # Core components
    ScopeResolver = ::TypeGuessr::Core::ScopeResolver
    MethodSignatureIndex = ::TypeGuessr::Core::MethodSignatureIndex
    VariableIndex = ::TypeGuessr::Core::VariableIndex
    RBSSignatureIndexer = ::TypeGuessr::Core::RBSIndexer
    ASTVisitor = ::TypeGuessr::Core::ASTAnalyzer

    # Integration components (for backward compatibility)
    RubyIndexAdapter = ::TypeGuessr::Integrations::RubyLsp::IndexAdapter
    TypeMatcher = ::TypeGuessr::Integrations::RubyLsp::TypeMatcher
    VariableTypeResolver = ::TypeGuessr::Integrations::RubyLsp::VariableTypeResolver
    HoverContentBuilder = ::TypeGuessr::Integrations::RubyLsp::HoverContentBuilder
    Hover = ::TypeGuessr::Integrations::RubyLsp::HoverProvider
    Addon = ::TypeGuessr::Integrations::RubyLsp::Addon
  end
end
