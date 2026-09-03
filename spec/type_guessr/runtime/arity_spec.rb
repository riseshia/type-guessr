# frozen_string_literal: true

require "type_guessr/runtime/arity"

RSpec.describe TypeGuessr::Runtime::Arity do
  let(:target) do
    Class.new do
      def self.build(name); end

      def admin?; end

      def rename(name); end

      def slice(from, to = nil); end

      def push(*items); end

      def find_by(id:, scope: nil); end

      def with_options(**opts); end
    end
  end

  def accepts?(name, positional_count, keywords = [], singleton: false)
    described_class.accepts_arity?(target, name, singleton, positional_count, keywords)
  end

  it "accepts a call matching a zero-arity method" do
    expect(accepts?(:admin?, 0)).to be(true)
  end

  it "rejects extra positional arguments" do
    expect(accepts?(:admin?, 1)).to be(false)
    expect(accepts?(:rename, 2)).to be(false)
  end

  it "rejects too few positional arguments" do
    expect(accepts?(:rename, 0)).to be(false)
    expect(accepts?(:slice, 0)).to be(false)
  end

  it "honours optional parameters" do
    expect(accepts?(:slice, 1)).to be(true)
    expect(accepts?(:slice, 2)).to be(true)
    expect(accepts?(:slice, 3)).to be(false)
  end

  it "accepts any count for a rest parameter" do
    expect(accepts?(:push, 0)).to be(true)
    expect(accepts?(:push, 5)).to be(true)
  end

  it "skips the positional check when the count is unknown (splat)" do
    expect(accepts?(:admin?, nil)).to be(true)
    expect(accepts?(:slice, nil)).to be(true)
  end

  it "counts keywords as one trailing Hash positional when the method takes none" do
    expect(accepts?(:admin?, 0, %w[force])).to be(false)
    expect(accepts?(:rename, 0, %w[force])).to be(true)
    expect(accepts?(:rename, 1, %w[force])).to be(false)
  end

  it "rejects keywords the method does not declare" do
    expect(accepts?(:find_by, 0, %w[id scope])).to be(true)
    expect(accepts?(:find_by, 0, %w[id oops])).to be(false)
  end

  it "does not require every declared keyword to be supplied" do
    expect(accepts?(:find_by, 0, %w[scope])).to be(true)
  end

  it "accepts unknown keywords when the method has a keyword rest" do
    expect(accepts?(:with_options, 0, %w[anything at_all])).to be(true)
  end

  it "checks the singleton side when asked" do
    expect(accepts?(:build, 1, [], singleton: true)).to be(true)
    expect(accepts?(:build, 2, [], singleton: true)).to be(false)
  end

  it "accepts when reflection cannot find the method" do
    expect(accepts?(:no_such_method, 3)).to be(true)
  end

  it "accepts C-implemented methods that report only a rest parameter" do
    expect(described_class.accepts_arity?(Array, :push, false, 3, [])).to be(true)
  end
end
