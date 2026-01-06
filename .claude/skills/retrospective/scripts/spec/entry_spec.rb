# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/entry"

RSpec.describe Entry do
  describe "#initialize" do
    it "creates entry with all fields" do
      entry = Entry.new(
        id: "arch-001",
        category: "arch",
        content: "Two-layer architecture",
        helpful: 5,
        harmful: 1,
        last_ref_date: "2026-01-06"
      )

      expect(entry.id).to eq("arch-001")
      expect(entry.category).to eq("arch")
      expect(entry.content).to eq("Two-layer architecture")
      expect(entry.helpful).to eq(5)
      expect(entry.harmful).to eq(1)
      expect(entry.last_ref_date).to eq("2026-01-06")
    end

    it "defaults helpful and harmful to 0" do
      entry = Entry.new(id: "pat-001", category: "pat", content: "Use guard clauses")

      expect(entry.helpful).to eq(0)
      expect(entry.harmful).to eq(0)
    end

    it "defaults last_ref_date to today" do
      entry = Entry.new(id: "tool-001", category: "tool", content: "Use rspec")

      expect(entry.last_ref_date).to eq(Date.today.to_s)
    end
  end

  describe "#to_markdown" do
    it "formats entry as markdown bullet" do
      entry = Entry.new(
        id: "arch-001",
        category: "arch",
        content: "Two-layer architecture",
        helpful: 5,
        harmful: 1,
        last_ref_date: "2026-01-06"
      )

      expect(entry.to_markdown).to eq("- [+5, -1, 2026-01-06] arch-001: Two-layer architecture")
    end
  end

  describe "#stale?" do
    it "returns false if helpful > 0" do
      entry = Entry.new(
        id: "arch-001",
        category: "arch",
        content: "content",
        helpful: 1,
        last_ref_date: (Date.today - 100).to_s
      )

      expect(entry.stale?).to be false
    end

    it "returns false if age <= 60 days" do
      entry = Entry.new(
        id: "arch-001",
        category: "arch",
        content: "content",
        helpful: 0,
        last_ref_date: (Date.today - 30).to_s
      )

      expect(entry.stale?).to be false
    end

    it "returns true if helpful == 0 and age > 60 days" do
      entry = Entry.new(
        id: "arch-001",
        category: "arch",
        content: "content",
        helpful: 0,
        last_ref_date: (Date.today - 61).to_s
      )

      expect(entry.stale?).to be true
    end
  end

  describe "#too_harmful?" do
    it "returns false if harmful < 3" do
      entry = Entry.new(id: "arch-001", category: "arch", content: "content", harmful: 2)

      expect(entry.too_harmful?).to be false
    end

    it "returns true if harmful >= 3" do
      entry = Entry.new(id: "arch-001", category: "arch", content: "content", harmful: 3)

      expect(entry.too_harmful?).to be true
    end
  end

  describe ".from_markdown" do
    it "parses markdown bullet into entry" do
      line = "- [+5, -1, 2026-01-06] arch-001: Two-layer architecture"
      entry = Entry.from_markdown(line)

      expect(entry.id).to eq("arch-001")
      expect(entry.category).to eq("arch")
      expect(entry.content).to eq("Two-layer architecture")
      expect(entry.helpful).to eq(5)
      expect(entry.harmful).to eq(1)
      expect(entry.last_ref_date).to eq("2026-01-06")
    end

    it "returns nil for non-matching lines" do
      expect(Entry.from_markdown("Some random text")).to be_nil
      expect(Entry.from_markdown("- Regular bullet")).to be_nil
    end
  end

  describe ".next_id" do
    it "generates next id for category" do
      existing = [
        Entry.new(id: "arch-001", category: "arch", content: "a"),
        Entry.new(id: "arch-002", category: "arch", content: "b"),
        Entry.new(id: "pat-001", category: "pat", content: "c"),
      ]

      expect(Entry.next_id("arch", existing)).to eq("arch-003")
      expect(Entry.next_id("pat", existing)).to eq("pat-002")
      expect(Entry.next_id("tool", existing)).to eq("tool-001")
    end
  end

  describe "#score" do
    it "returns helpful minus harmful" do
      entry = Entry.new(id: "arch-001", category: "arch", content: "a", helpful: 5, harmful: 2)

      expect(entry.score).to eq(3)
    end

    it "can be negative" do
      entry = Entry.new(id: "arch-001", category: "arch", content: "a", helpful: 1, harmful: 4)

      expect(entry.score).to eq(-3)
    end
  end

  describe ".trim_to_limit" do
    it "returns entries unchanged when under limit" do
      entries = [
        Entry.new(id: "arch-001", category: "arch", content: "a"),
      ]

      result = Entry.trim_to_limit(entries, max_count: 200)

      expect(result).to eq(entries)
    end

    it "removes lowest score entries first when over limit" do
      entries = [
        Entry.new(id: "arch-001", category: "arch", content: "a", helpful: 5, harmful: 0),
        Entry.new(id: "arch-002", category: "arch", content: "b", helpful: 1, harmful: 0),
        Entry.new(id: "arch-003", category: "arch", content: "c", helpful: 3, harmful: 0),
      ]

      result = Entry.trim_to_limit(entries, max_count: 2)

      expect(result.map(&:id)).to eq(%w[arch-001 arch-003])
    end

    it "removes older entries when scores are equal" do
      entries = [
        Entry.new(id: "arch-001", category: "arch", content: "a", helpful: 1, last_ref_date: "2026-01-05"),
        Entry.new(id: "arch-002", category: "arch", content: "b", helpful: 1, last_ref_date: "2026-01-06"),
        Entry.new(id: "arch-003", category: "arch", content: "c", helpful: 1, last_ref_date: "2026-01-04"),
      ]

      result = Entry.trim_to_limit(entries, max_count: 2)

      expect(result.map(&:id)).to eq(%w[arch-002 arch-001])
    end

    it "removes by id when scores and dates are equal" do
      entries = [
        Entry.new(id: "arch-002", category: "arch", content: "b", helpful: 1, last_ref_date: "2026-01-05"),
        Entry.new(id: "arch-001", category: "arch", content: "a", helpful: 1, last_ref_date: "2026-01-05"),
        Entry.new(id: "arch-003", category: "arch", content: "c", helpful: 1, last_ref_date: "2026-01-05"),
      ]

      result = Entry.trim_to_limit(entries, max_count: 2)

      expect(result.map(&:id)).to eq(%w[arch-003 arch-002])
    end

    it "uses combined sort order: score desc, date desc, id desc" do
      entries = [
        Entry.new(id: "arch-001", category: "arch", content: "low score old", helpful: 0, last_ref_date: "2026-01-01"),
        Entry.new(id: "arch-002", category: "arch", content: "high score", helpful: 5, last_ref_date: "2026-01-01"),
        Entry.new(id: "arch-003", category: "arch", content: "low score new", helpful: 0, last_ref_date: "2026-01-06"),
        Entry.new(id: "arch-004", category: "arch", content: "mid score", helpful: 2, last_ref_date: "2026-01-03"),
      ]

      result = Entry.trim_to_limit(entries, max_count: 2)

      # Keep: arch-002 (score 5), arch-004 (score 2)
      # Remove: arch-001 (score 0, old), arch-003 (score 0, new but still low)
      expect(result.map(&:id)).to eq(%w[arch-002 arch-004])
    end
  end
end
