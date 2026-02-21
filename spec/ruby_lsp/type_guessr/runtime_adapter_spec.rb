# frozen_string_literal: true

# rubocop:disable RSpec/VerifiedDoubles -- ruby-lsp internals (GlobalState, Index) not available as constants
RSpec.describe RubyLsp::TypeGuessr::RuntimeAdapter do
  describe "#wait_for_index_stabilization" do
    let(:adapter) do
      global_state = double("global_state", index: nil)
      described_class.new(global_state)
    end

    before do
      allow(adapter).to receive(:sleep)
      allow(adapter).to receive(:log_message)
    end

    it "returns after stable_threshold consecutive checks with no growth" do
      index = double("index", length: 500)

      adapter.send(:wait_for_index_stabilization, index)

      expect(adapter).to have_received(:sleep).with(1).exactly(3).times
    end

    it "waits longer when entry count is still growing" do
      index = double("index")
      allow(index).to receive(:length).and_return(100, 200, 300, 300, 300, 300)

      adapter.send(:wait_for_index_stabilization, index)

      expect(adapter).to have_received(:sleep).with(1).exactly(5).times
    end

    it "resets stability counter when count increases after brief stable period" do
      index = double("index")
      allow(index).to receive(:length).and_return(100, 100, 100, 200, 200, 200, 200)

      adapter.send(:wait_for_index_stabilization, index)

      expect(adapter).to have_received(:sleep).with(1).exactly(6).times
    end
  end
end
# rubocop:enable RSpec/VerifiedDoubles
