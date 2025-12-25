# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/type_db"
require "type_guessr/core/types"

RSpec.describe TypeGuessr::Core::TypeDB do
  let(:type_db) { described_class.new }
  let(:string_type) { TypeGuessr::Core::Types::ClassInstance.new("String") }
  let(:integer_type) { TypeGuessr::Core::Types::ClassInstance.new("Integer") }

  describe "#set_type and #get_type" do
    it "stores and retrieves type by file and range" do
      file_path = "/path/to/file.rb"
      range = { start: { line: 1, character: 0 }, end: { line: 1, character: 10 } }

      type_db.set_type(file_path, range, string_type)
      result = type_db.get_type(file_path, range)

      expect(result).to eq(string_type)
    end

    it "returns nil for non-existent file and range" do
      file_path = "/path/to/file.rb"
      range = { start: { line: 1, character: 0 }, end: { line: 1, character: 10 } }

      result = type_db.get_type(file_path, range)

      expect(result).to be_nil
    end

    it "stores different types for different ranges in the same file" do
      file_path = "/path/to/file.rb"
      range1 = { start: { line: 1, character: 0 }, end: { line: 1, character: 10 } }
      range2 = { start: { line: 2, character: 0 }, end: { line: 2, character: 10 } }

      type_db.set_type(file_path, range1, string_type)
      type_db.set_type(file_path, range2, integer_type)

      expect(type_db.get_type(file_path, range1)).to eq(string_type)
      expect(type_db.get_type(file_path, range2)).to eq(integer_type)
    end

    it "updates type when setting the same file and range again" do
      file_path = "/path/to/file.rb"
      range = { start: { line: 1, character: 0 }, end: { line: 1, character: 10 } }

      type_db.set_type(file_path, range, string_type)
      type_db.set_type(file_path, range, integer_type)

      expect(type_db.get_type(file_path, range)).to eq(integer_type)
    end
  end

  describe "#clear_file" do
    it "removes all types for the specified file" do
      file_path = "/path/to/file.rb"
      range1 = { start: { line: 1, character: 0 }, end: { line: 1, character: 10 } }
      range2 = { start: { line: 2, character: 0 }, end: { line: 2, character: 10 } }

      type_db.set_type(file_path, range1, string_type)
      type_db.set_type(file_path, range2, integer_type)

      type_db.clear_file(file_path)

      expect(type_db.get_type(file_path, range1)).to be_nil
      expect(type_db.get_type(file_path, range2)).to be_nil
    end

    it "does not affect types in other files" do
      file_path1 = "/path/to/file1.rb"
      file_path2 = "/path/to/file2.rb"
      range = { start: { line: 1, character: 0 }, end: { line: 1, character: 10 } }

      type_db.set_type(file_path1, range, string_type)
      type_db.set_type(file_path2, range, integer_type)

      type_db.clear_file(file_path1)

      expect(type_db.get_type(file_path1, range)).to be_nil
      expect(type_db.get_type(file_path2, range)).to eq(integer_type)
    end
  end

  describe "#clear" do
    it "removes all types from all files" do
      file_path1 = "/path/to/file1.rb"
      file_path2 = "/path/to/file2.rb"
      range = { start: { line: 1, character: 0 }, end: { line: 1, character: 10 } }

      type_db.set_type(file_path1, range, string_type)
      type_db.set_type(file_path2, range, integer_type)

      type_db.clear

      expect(type_db.get_type(file_path1, range)).to be_nil
      expect(type_db.get_type(file_path2, range)).to be_nil
    end
  end
end
