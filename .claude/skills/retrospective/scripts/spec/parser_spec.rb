# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/entry"
require_relative "../lib/parser"

RSpec.describe Parser do
  let(:sample_claude_md) do
    <<~MD
      # Project Documentation

      Some content here.

      ## Knowledge Base
      <!-- Managed by /retro -->

      ### Architecture Knowledge
      - [+5, -0, 2026-01-06] arch-001: Two-layer architecture

      ### Pattern Knowledge
      - [+3, -1, 2026-01-05] pat-001: Use guard clauses

      ### Tool Knowledge

      ### Convention Knowledge
      - [+0, -0, 2026-01-04] conv-001: Use snake_case

      ## Other Section

      More content.
    MD
  end

  describe ".parse" do
    it "extracts entries from Knowledge Base section" do
      entries = Parser.parse(sample_claude_md)

      expect(entries.size).to eq(3)
      expect(entries.map(&:id)).to eq(%w[arch-001 pat-001 conv-001])
    end

    it "returns empty array when no Knowledge Base section" do
      content = "# Just a regular document\n\nNo knowledge here."
      entries = Parser.parse(content)

      expect(entries).to eq([])
    end

    it "handles empty Knowledge Base section" do
      content = <<~MD
        ## Knowledge Base
        <!-- Managed by /retro -->

        ### Architecture Knowledge

        ### Pattern Knowledge

        ### Tool Knowledge

        ### Convention Knowledge

        ## Next Section
      MD

      entries = Parser.parse(content)
      expect(entries).to eq([])
    end
  end

  describe ".format" do
    it "formats entries into Knowledge Base section" do
      entries = [
        Entry.new(id: "arch-001", category: "arch", content: "Arch content", helpful: 1, harmful: 0, last_ref_date: "2026-01-06"),
        Entry.new(id: "pat-001", category: "pat", content: "Pat content", helpful: 2, harmful: 1, last_ref_date: "2026-01-05")
      ]

      result = Parser.format(entries)

      expect(result).to include("## Knowledge Base")
      expect(result).to include("### Architecture Knowledge")
      expect(result).to include("- [+1, -0, 2026-01-06] arch-001: Arch content")
      expect(result).to include("### Pattern Knowledge")
      expect(result).to include("- [+2, -1, 2026-01-05] pat-001: Pat content")
    end

    it "groups entries by category" do
      entries = [
        Entry.new(id: "arch-001", category: "arch", content: "A1"),
        Entry.new(id: "arch-002", category: "arch", content: "A2"),
        Entry.new(id: "tool-001", category: "tool", content: "T1")
      ]

      result = Parser.format(entries)

      # arch entries should be together
      arch_section = result[/### Architecture Knowledge\n(.+?)(?=###|\z)/m, 1]
      expect(arch_section).to include("arch-001")
      expect(arch_section).to include("arch-002")
    end
  end

  describe ".update_content" do
    it "replaces Knowledge Base section with new entries" do
      entries = [
        Entry.new(id: "arch-002", category: "arch", content: "New arch content")
      ]

      result = Parser.update_content(sample_claude_md, entries)

      expect(result).to include("# Project Documentation")
      expect(result).to include("## Knowledge Base")
      expect(result).to include("arch-002: New arch content")
      expect(result).not_to include("arch-001")
      expect(result).to include("## Other Section")
    end

    it "adds Knowledge Base section if missing" do
      content = "# Doc\n\nSome content.\n"
      entries = [Entry.new(id: "arch-001", category: "arch", content: "First")]

      result = Parser.update_content(content, entries)

      expect(result).to include("# Doc")
      expect(result).to include("## Knowledge Base")
      expect(result).to include("arch-001: First")
    end
  end
end
