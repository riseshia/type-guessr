# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/session_reader"
require "json"
require "tempfile"
require "fileutils"

RSpec.describe SessionReader do
  let(:project_path) { "/home/shia/repos/riseshia/type-guessr" }
  let(:encoded_path) { "-home-shia-repos-riseshia-type-guessr" }

  describe ".encode_project_path" do
    it "encodes path by replacing / with -" do
      expect(SessionReader.encode_project_path(project_path)).to eq(encoded_path)
    end
  end

  describe ".read_messages" do
    it "extracts user and assistant messages from JSONL" do
      messages = [
        { "type" => "user", "message" => { "role" => "user", "content" => "Hello" } },
        { "type" => "assistant", "message" => { "role" => "assistant", "content" => [{ "type" => "text", "text" => "Hi there!" }] } },
        { "type" => "summary", "summary" => "Ignored" },
        { "type" => "user", "message" => { "role" => "user", "content" => "How are you?" } }
      ]

      Tempfile.create("session.jsonl") do |f|
        messages.each { |m| f.puts(JSON.generate(m)) }
        f.flush

        result = SessionReader.read_messages(f.path)

        expect(result.size).to eq(3)
        expect(result[0]).to eq({ role: "user", content: "Hello" })
        expect(result[1]).to eq({ role: "assistant", content: "Hi there!" })
        expect(result[2]).to eq({ role: "user", content: "How are you?" })
      end
    end

    it "handles assistant messages with multiple content blocks" do
      messages = [
        {
          "type" => "assistant",
          "message" => {
            "role" => "assistant",
            "content" => [
              { "type" => "thinking", "thinking" => "Let me think..." },
              { "type" => "text", "text" => "First part." },
              { "type" => "tool_use", "name" => "Bash" },
              { "type" => "text", "text" => "Second part." }
            ]
          }
        }
      ]

      Tempfile.create("session.jsonl") do |f|
        messages.each { |m| f.puts(JSON.generate(m)) }
        f.flush

        result = SessionReader.read_messages(f.path)

        expect(result.size).to eq(1)
        expect(result[0][:content]).to eq("First part.\n\nSecond part.")
      end
    end
  end

  describe ".format_for_display" do
    it "formats messages as readable text" do
      messages = [
        { role: "user", content: "What is 2+2?" },
        { role: "assistant", content: "The answer is 4." }
      ]

      result = SessionReader.format_for_display(messages)

      expect(result).to include("[User]")
      expect(result).to include("What is 2+2?")
      expect(result).to include("[Assistant]")
      expect(result).to include("The answer is 4.")
    end
  end

  describe ".find_latest_session" do
    it "finds the most recently modified session file" do
      Dir.mktmpdir do |dir|
        projects_dir = File.join(dir, "projects", encoded_path)
        FileUtils.mkdir_p(projects_dir)

        # Create two session files with different modification times
        old_file = File.join(projects_dir, "old-session.jsonl")
        new_file = File.join(projects_dir, "new-session.jsonl")

        File.write(old_file, '{"type":"user"}')
        sleep 0.1
        File.write(new_file, '{"type":"user"}')

        result = SessionReader.find_latest_session(dir, project_path)

        expect(result).to eq(new_file)
      end
    end

    it "returns nil if no sessions exist" do
      Dir.mktmpdir do |dir|
        result = SessionReader.find_latest_session(dir, project_path)

        expect(result).to be_nil
      end
    end
  end
end
