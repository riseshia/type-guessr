# frozen_string_literal: true

require "spec_helper"
require "type_guessr/mcp/server"
require "tmpdir"
require "fileutils"

RSpec.describe TypeGuessr::MCP::FileWatcher do
  let(:tmpdir) { Dir.mktmpdir }
  let(:callback_log) { [] }
  let(:watcher) do
    described_class.new(
      project_path: tmpdir,
      on_change: lambda { |modified, added, removed|
        callback_log << { modified: modified.dup, added: added.dup, removed: removed.dup }
      },
      interval: 0.1
    )
  end

  after do
    watcher.stop
    FileUtils.rm_rf(tmpdir)
  end

  def wait_for_callback(timeout: 2)
    start = Time.now
    initial_count = callback_log.size
    sleep(0.05) while callback_log.size == initial_count && Time.now - start < timeout
  end

  describe "#start / #stop" do
    it "starts and stops without error" do
      # Create a .rb file so the watcher has something to snapshot
      File.write(File.join(tmpdir, "a.rb"), "x = 1")

      watcher.start
      expect(watcher).to be_running
      watcher.stop
      expect(watcher).not_to be_running
    end
  end

  describe "change detection" do
    before do
      File.write(File.join(tmpdir, "a.rb"), "x = 1")
      watcher.start
      sleep(0.15) # let initial poll complete
    end

    it "detects modified files" do
      # Touch the file to update mtime
      sleep(0.01)
      File.write(File.join(tmpdir, "a.rb"), "x = 2")

      wait_for_callback

      all_modified = callback_log.flat_map { |e| e[:modified] }
      expect(all_modified).to include(File.join(tmpdir, "a.rb"))
    end

    it "detects newly added files" do
      File.write(File.join(tmpdir, "b.rb"), "y = 1")

      wait_for_callback

      all_added = callback_log.flat_map { |e| e[:added] }
      expect(all_added).to include(File.join(tmpdir, "b.rb"))
    end

    it "detects deleted files" do
      File.delete(File.join(tmpdir, "a.rb"))

      wait_for_callback

      all_removed = callback_log.flat_map { |e| e[:removed] }
      expect(all_removed).to include(File.join(tmpdir, "a.rb"))
    end

    it "ignores non-ruby files" do
      File.write(File.join(tmpdir, "readme.md"), "# hello")

      sleep(0.3) # wait for a couple polls
      all_events = callback_log.flat_map { |e| e[:modified] + e[:added] + e[:removed] }
      expect(all_events).not_to include(File.join(tmpdir, "readme.md"))
    end
  end
end
