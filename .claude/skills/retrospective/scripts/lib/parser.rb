# frozen_string_literal: true

require_relative "entry"

# Parses and formats the Knowledge Base section in CLAUDE.md
class Parser
  SECTION_START = "## Knowledge Base"
  SECTION_COMMENT = "<!-- Managed by /retro -->"
  CATEGORY_HEADERS = {
    "arch" => "### Architecture Knowledge",
    "pat" => "### Pattern Knowledge",
    "tool" => "### Tool Knowledge",
    "conv" => "### Convention Knowledge"
  }.freeze

  def self.parse(content)
    section = extract_section(content)
    return [] if section.nil?

    section.lines.filter_map { |line| Entry.from_markdown(line.strip) }
  end

  def self.format(entries)
    grouped = entries.group_by(&:category)

    lines = [SECTION_START, SECTION_COMMENT, ""]

    Entry::CATEGORIES.each do |cat|
      lines << CATEGORY_HEADERS[cat]
      (grouped[cat] || []).each do |entry|
        lines << entry.to_markdown
      end
      lines << ""
    end

    lines.join("\n")
  end

  def self.update_content(content, entries)
    new_section = format(entries)

    if content.include?(SECTION_START)
      # Replace existing section
      before, rest = content.split(SECTION_START, 2)
      after_section = find_next_section(rest)

      "#{before.rstrip}\n\n#{new_section}#{after_section}"
    else
      # Append new section
      "#{content.rstrip}\n\n#{new_section}"
    end
  end

  def self.extract_section(content)
    return nil unless content.include?(SECTION_START)

    _, rest = content.split(SECTION_START, 2)
    section_end = find_section_end_index(rest)

    rest[0...section_end]
  end

  def self.find_section_end_index(rest)
    # Find the next ## heading (same or higher level)
    match = rest.match(/\n## [^#]/)
    match ? match.begin(0) : rest.length
  end

  def self.find_next_section(rest)
    match = rest.match(/\n(## [^#].*)$/m)
    match ? "\n#{match[1]}" : ""
  end

  private_class_method :extract_section, :find_section_end_index, :find_next_section
end
