# frozen_string_literal: true

require "json"

# Reads Claude Code session files from the filesystem
class SessionReader
  CLAUDE_DIR = File.expand_path("~/.claude")

  def self.encode_project_path(path)
    path.gsub("/", "-")
  end

  def self.find_latest_session(claude_dir = CLAUDE_DIR, project_path = Dir.pwd)
    encoded = encode_project_path(project_path)
    projects_dir = File.join(claude_dir, "projects", encoded)

    return nil unless Dir.exist?(projects_dir)

    session_files = Dir.glob(File.join(projects_dir, "*.jsonl"))
    return nil if session_files.empty?

    session_files.max_by { |f| File.mtime(f) }
  end

  def self.read_messages(session_path)
    messages = []

    File.foreach(session_path) do |line|
      data = JSON.parse(line)
      msg = extract_message(data)
      messages << msg if msg
    end

    messages
  end

  def self.format_for_display(messages)
    messages.map do |msg|
      role_label = msg[:role] == "user" ? "[User]" : "[Assistant]"
      "#{role_label}\n#{msg[:content]}"
    end.join("\n\n---\n\n")
  end

  def self.extract_message(data)
    return nil unless %w[user assistant].include?(data["type"])

    message = data["message"]
    role = message["role"]
    content = extract_content(message["content"])

    return nil if content.nil? || content.empty?

    { role: role, content: content }
  end

  def self.extract_content(content)
    return content if content.is_a?(String)
    return nil unless content.is_a?(Array)

    # Extract text blocks only, ignore thinking/tool_use
    text_parts = content
      .select { |block| block["type"] == "text" }
      .map { |block| block["text"] }

    text_parts.join("\n\n")
  end

  private_class_method :extract_message, :extract_content
end
