# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/type_guessr/core/constant_index"

RSpec.describe TypeGuessr::Core::ConstantIndex do
  let(:index) { described_class.instance }

  before do
    index.clear
  end

  describe "#add_alias" do
    it "stores a constant alias mapping" do
      index.add_alias(
        file_path: "/fake.rb",
        constant_fqn: "MyApp::Types",
        target_fqn: "::TypeGuessr::Core::Types",
        line: 5,
        column: 2
      )

      data = index.to_h
      expect(data["/fake.rb"]).to eq(
        "MyApp::Types" => {
          target: "::TypeGuessr::Core::Types",
          line: 5,
          column: 2
        }
      )
    end

    it "stores multiple aliases in the same file" do
      index.add_alias(
        file_path: "/fake.rb",
        constant_fqn: "Types",
        target_fqn: "::TypeGuessr::Core::Types",
        line: 1,
        column: 0
      )

      index.add_alias(
        file_path: "/fake.rb",
        constant_fqn: "Analyzer",
        target_fqn: "::TypeGuessr::Core::ASTAnalyzer",
        line: 2,
        column: 0
      )

      data = index.to_h
      expect(data["/fake.rb"].keys).to contain_exactly("Types", "Analyzer")
    end

    it "stores aliases across multiple files" do
      index.add_alias(
        file_path: "/file1.rb",
        constant_fqn: "Types",
        target_fqn: "::A",
        line: 1,
        column: 0
      )

      index.add_alias(
        file_path: "/file2.rb",
        constant_fqn: "Types",
        target_fqn: "::B",
        line: 1,
        column: 0
      )

      data = index.to_h
      expect(data.keys).to contain_exactly("/file1.rb", "/file2.rb")
    end
  end

  describe "#resolve_alias" do
    it "resolves a simple alias" do
      index.add_alias(
        file_path: "/fake.rb",
        constant_fqn: "Types",
        target_fqn: "::TypeGuessr::Core::Types",
        line: 1,
        column: 0
      )

      resolved = index.resolve_alias("Types")
      expect(resolved).to eq("::TypeGuessr::Core::Types")
    end

    it "returns nil for unknown constant" do
      resolved = index.resolve_alias("UnknownConstant")
      expect(resolved).to be_nil
    end

    it "resolves chained aliases" do
      index.add_alias(
        file_path: "/fake.rb",
        constant_fqn: "Original",
        target_fqn: "::SomeModule",
        line: 1,
        column: 0
      )

      index.add_alias(
        file_path: "/fake.rb",
        constant_fqn: "Alias1",
        target_fqn: "Original",
        line: 2,
        column: 0
      )

      index.add_alias(
        file_path: "/fake.rb",
        constant_fqn: "Alias2",
        target_fqn: "Alias1",
        line: 3,
        column: 0
      )

      resolved = index.resolve_alias("Alias2")
      expect(resolved).to eq("::SomeModule")
    end

    it "prevents infinite loops with circular aliases" do
      index.add_alias(
        file_path: "/fake.rb",
        constant_fqn: "A",
        target_fqn: "B",
        line: 1,
        column: 0
      )

      index.add_alias(
        file_path: "/fake.rb",
        constant_fqn: "B",
        target_fqn: "C",
        line: 2,
        column: 0
      )

      index.add_alias(
        file_path: "/fake.rb",
        constant_fqn: "C",
        target_fqn: "A",
        line: 3,
        column: 0
      )

      # Should stop at MAX_ALIAS_DEPTH and return the last resolved value
      resolved = index.resolve_alias("A")
      expect(resolved).not_to be_nil
    end

    it "handles very deep alias chains within MAX_ALIAS_DEPTH" do
      # Create a chain of 4 aliases (within limit of 5)
      index.add_alias(file_path: "/fake.rb", constant_fqn: "A", target_fqn: "B", line: 1, column: 0)
      index.add_alias(file_path: "/fake.rb", constant_fqn: "B", target_fqn: "C", line: 2, column: 0)
      index.add_alias(file_path: "/fake.rb", constant_fqn: "C", target_fqn: "D", line: 3, column: 0)
      index.add_alias(file_path: "/fake.rb", constant_fqn: "D", target_fqn: "::Final", line: 4, column: 0)

      resolved = index.resolve_alias("A")
      expect(resolved).to eq("::Final")
    end
  end

  describe "#clear_file" do
    it "clears aliases for a specific file" do
      index.add_alias(
        file_path: "/file1.rb",
        constant_fqn: "Types",
        target_fqn: "::A",
        line: 1,
        column: 0
      )

      index.add_alias(
        file_path: "/file2.rb",
        constant_fqn: "Types",
        target_fqn: "::B",
        line: 1,
        column: 0
      )

      index.clear_file("/file1.rb")

      data = index.to_h
      expect(data.keys).to eq(["/file2.rb"])
    end
  end

  describe "#clear" do
    it "clears all aliases" do
      index.add_alias(
        file_path: "/file1.rb",
        constant_fqn: "Types",
        target_fqn: "::A",
        line: 1,
        column: 0
      )

      index.clear

      data = index.to_h
      expect(data).to be_empty
    end
  end

  describe "#stats" do
    it "returns statistics about indexed aliases" do
      index.add_alias(
        file_path: "/file1.rb",
        constant_fqn: "Types",
        target_fqn: "::A",
        line: 1,
        column: 0
      )

      index.add_alias(
        file_path: "/file1.rb",
        constant_fqn: "Analyzer",
        target_fqn: "::B",
        line: 2,
        column: 0
      )

      index.add_alias(
        file_path: "/file2.rb",
        constant_fqn: "Types",
        target_fqn: "::C",
        line: 1,
        column: 0
      )

      stats = index.stats
      expect(stats).to eq(
        total_aliases: 3,
        files_count: 2
      )
    end
  end

  describe "thread safety" do
    it "handles concurrent access" do
      threads = 10.times.map do |i|
        Thread.new do
          index.add_alias(
            file_path: "/file#{i}.rb",
            constant_fqn: "Const#{i}",
            target_fqn: "::Target#{i}",
            line: 1,
            column: 0
          )
        end
      end

      threads.each(&:join)

      stats = index.stats
      expect(stats[:total_aliases]).to eq(10)
      expect(stats[:files_count]).to eq(10)
    end
  end
end
