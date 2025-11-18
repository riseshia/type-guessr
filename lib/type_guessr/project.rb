# frozen_string_literal: true

module TypeGuessr
  # Represents a project-wide type inference context
  class Project
    attr_reader :root_path

    def initialize(root_path)
      @root_path = root_path
    end
  end
end
