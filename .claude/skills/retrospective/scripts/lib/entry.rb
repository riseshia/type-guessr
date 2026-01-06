# frozen_string_literal: true

require "date"

# Represents a single knowledge entry in the Knowledge Base
class Entry
  ENTRY_REGEX = /^- \[\+(\d+), -(\d+), (\d{4}-\d{2}-\d{2})\] (arch|pat|tool|conv)-(\d{3}): (.+)$/
  CATEGORIES = %w[arch pat tool conv].freeze

  attr_accessor :id, :category, :content, :helpful, :harmful, :last_ref_date

  def initialize(id:, category:, content:, helpful: 0, harmful: 0, last_ref_date: nil)
    @id = id
    @category = category
    @content = content
    @helpful = helpful
    @harmful = harmful
    @last_ref_date = last_ref_date || Date.today.to_s
  end

  def to_markdown
    "- [+#{helpful}, -#{harmful}, #{last_ref_date}] #{id}: #{content}"
  end

  def stale?(max_age_days: 60)
    return false if helpful > 0

    age = (Date.today - Date.parse(last_ref_date)).to_i
    age > max_age_days
  end

  def too_harmful?(threshold: 3)
    harmful >= threshold
  end

  def self.from_markdown(line)
    match = ENTRY_REGEX.match(line)
    return nil unless match

    new(
      helpful: match[1].to_i,
      harmful: match[2].to_i,
      last_ref_date: match[3],
      category: match[4],
      id: "#{match[4]}-#{match[5]}",
      content: match[6]
    )
  end

  def self.next_id(category, existing_entries)
    max_num = existing_entries
      .select { |e| e.category == category }
      .map { |e| e.id.split("-").last.to_i }
      .max || 0

    format("%s-%03d", category, max_num + 1)
  end
end
