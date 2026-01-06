# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/signature_provider"
require "type_guessr/core/types"

RSpec.describe TypeGuessr::Core::SignatureProvider do
  let(:string_type) { TypeGuessr::Core::Types::ClassInstance.new("String") }
  let(:integer_type) { TypeGuessr::Core::Types::ClassInstance.new("Integer") }
  let(:unknown_type) { TypeGuessr::Core::Types::Unknown.instance }

  # Mock provider for testing
  let(:mock_provider) do
    Class.new do
      def initialize(responses = {})
        @responses = responses
      end

      def get_method_return_type(class_name, method_name, _arg_types = [])
        @responses.dig(:instance, class_name, method_name) || TypeGuessr::Core::Types::Unknown.instance
      end

      def get_class_method_return_type(class_name, method_name, _arg_types = [])
        @responses.dig(:class, class_name, method_name) || TypeGuessr::Core::Types::Unknown.instance
      end

      def get_block_param_types(class_name, method_name)
        @responses.dig(:block, class_name, method_name) || []
      end
    end
  end

  describe "#initialize" do
    it "accepts an array of providers" do
      provider = described_class.new([])
      expect(provider).to be_a(described_class)
    end

    it "defaults to empty providers array" do
      provider = described_class.new
      expect(provider.get_method_return_type("String", "upcase")).to eq(unknown_type)
    end
  end

  describe "#add_provider" do
    it "adds provider with low priority by default" do
      provider1 = mock_provider.new({ instance: { "String" => { "foo" => string_type } } })
      provider2 = mock_provider.new({ instance: { "String" => { "foo" => integer_type } } })

      sig_provider = described_class.new([provider1])
      sig_provider.add_provider(provider2)

      # provider1 should be checked first (added first)
      expect(sig_provider.get_method_return_type("String", "foo")).to eq(string_type)
    end

    it "adds provider with high priority when specified" do
      provider1 = mock_provider.new({ instance: { "String" => { "foo" => string_type } } })
      provider2 = mock_provider.new({ instance: { "String" => { "foo" => integer_type } } })

      sig_provider = described_class.new([provider1])
      sig_provider.add_provider(provider2, priority: :high)

      # provider2 should be checked first (high priority)
      expect(sig_provider.get_method_return_type("String", "foo")).to eq(integer_type)
    end
  end

  describe "#get_method_return_type" do
    context "with single provider" do
      it "returns type from provider" do
        provider = mock_provider.new({ instance: { "String" => { "upcase" => string_type } } })
        sig_provider = described_class.new([provider])

        result = sig_provider.get_method_return_type("String", "upcase")
        expect(result).to eq(string_type)
      end

      it "returns Unknown when provider returns Unknown" do
        provider = mock_provider.new({})
        sig_provider = described_class.new([provider])

        result = sig_provider.get_method_return_type("String", "nonexistent")
        expect(result).to eq(unknown_type)
      end

      it "passes arg_types to provider" do
        call_args = nil
        provider = Class.new do
          define_method(:get_method_return_type) do |_class_name, _method_name, arg_types|
            call_args = arg_types
            TypeGuessr::Core::Types::Unknown.instance
          end
        end.new

        sig_provider = described_class.new([provider])
        sig_provider.get_method_return_type("String", "foo", [string_type, integer_type])

        expect(call_args).to eq([string_type, integer_type])
      end
    end

    context "with multiple providers" do
      it "returns first non-Unknown result" do
        provider1 = mock_provider.new({}) # Returns Unknown for everything
        provider2 = mock_provider.new({ instance: { "String" => { "foo" => string_type } } })

        sig_provider = described_class.new([provider1, provider2])

        result = sig_provider.get_method_return_type("String", "foo")
        expect(result).to eq(string_type)
      end

      it "stops at first non-Unknown result" do
        provider1 = mock_provider.new({ instance: { "String" => { "foo" => string_type } } })
        provider2_called = false
        provider2 = Class.new do
          define_method(:get_method_return_type) do |_class_name, _method_name, _arg_types|
            provider2_called = true
            TypeGuessr::Core::Types::ClassInstance.new("Integer")
          end
        end.new

        sig_provider = described_class.new([provider1, provider2])
        sig_provider.get_method_return_type("String", "foo")

        expect(provider2_called).to be false
      end

      it "returns Unknown when all providers return Unknown" do
        provider1 = mock_provider.new({})
        provider2 = mock_provider.new({})

        sig_provider = described_class.new([provider1, provider2])

        result = sig_provider.get_method_return_type("String", "nonexistent")
        expect(result).to eq(unknown_type)
      end
    end
  end

  describe "#get_class_method_return_type" do
    it "returns type from provider" do
      provider = mock_provider.new({ class: { "File" => { "read" => string_type } } })
      sig_provider = described_class.new([provider])

      result = sig_provider.get_class_method_return_type("File", "read")
      expect(result).to eq(string_type)
    end

    it "returns first non-Unknown result from multiple providers" do
      provider1 = mock_provider.new({})
      provider2 = mock_provider.new({ class: { "Array" => { "new" => string_type } } })

      sig_provider = described_class.new([provider1, provider2])

      result = sig_provider.get_class_method_return_type("Array", "new")
      expect(result).to eq(string_type)
    end

    it "returns Unknown when no provider has the method" do
      provider = mock_provider.new({})
      sig_provider = described_class.new([provider])

      result = sig_provider.get_class_method_return_type("Foo", "bar")
      expect(result).to eq(unknown_type)
    end
  end

  describe "#get_block_param_types" do
    it "returns block param types from provider" do
      provider = mock_provider.new({ block: { "Array" => { "each" => [string_type] } } })
      sig_provider = described_class.new([provider])

      result = sig_provider.get_block_param_types("Array", "each")
      expect(result).to eq([string_type])
    end

    it "returns first non-empty result from multiple providers" do
      provider1 = mock_provider.new({}) # Returns empty array
      provider2 = mock_provider.new({ block: { "Array" => { "map" => [integer_type] } } })

      sig_provider = described_class.new([provider1, provider2])

      result = sig_provider.get_block_param_types("Array", "map")
      expect(result).to eq([integer_type])
    end

    it "returns empty array when no provider has block params" do
      provider = mock_provider.new({})
      sig_provider = described_class.new([provider])

      result = sig_provider.get_block_param_types("String", "upcase")
      expect(result).to eq([])
    end
  end
end
