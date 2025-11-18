# frozen_string_literal: true

module TypeGuessr
  # Represents the result of analyzing a single file
  class FileAnalysisResult
    attr_reader :file_path, :variable_index

    def initialize(file_path, variable_index)
      @file_path = file_path
      @variable_index = variable_index
    end
  end
end
