# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLsp::TypeGuessr::ScopeResolver do
  describe ".determine_scope_type" do
    context "with local variables" do
      it "returns :local_variables for user" do
        expect(described_class.determine_scope_type("user")).to eq(:local_variables)
      end

      it "returns :local_variables for some_var" do
        expect(described_class.determine_scope_type("some_var")).to eq(:local_variables)
      end

      it "returns :local_variables for single character variable" do
        expect(described_class.determine_scope_type("x")).to eq(:local_variables)
      end
    end

    context "with instance variables" do
      it "returns :instance_variables for @user" do
        expect(described_class.determine_scope_type("@user")).to eq(:instance_variables)
      end

      it "returns :instance_variables for @some_var" do
        expect(described_class.determine_scope_type("@some_var")).to eq(:instance_variables)
      end
    end

    context "with class variables" do
      it "returns :class_variables for @@user" do
        expect(described_class.determine_scope_type("@@user")).to eq(:class_variables)
      end

      it "returns :class_variables for @@counter" do
        expect(described_class.determine_scope_type("@@counter")).to eq(:class_variables)
      end
    end
  end

  describe ".generate_scope_id" do
    context "for local variables" do
      it "generates scope_id with method and class" do
        scope_id = described_class.generate_scope_id(
          :local_variables,
          class_path: "User",
          method_name: "initialize"
        )
        expect(scope_id).to eq("User#initialize")
      end

      it "generates scope_id with method only" do
        scope_id = described_class.generate_scope_id(
          :local_variables,
          class_path: "",
          method_name: "process"
        )
        expect(scope_id).to eq("process")
      end

      it "generates scope_id with nested class" do
        scope_id = described_class.generate_scope_id(
          :local_variables,
          class_path: "Api::User",
          method_name: "create"
        )
        expect(scope_id).to eq("Api::User#create")
      end

      it "generates (top-level) when no class or method" do
        scope_id = described_class.generate_scope_id(
          :local_variables,
          class_path: "",
          method_name: nil
        )
        expect(scope_id).to eq("(top-level)")
      end
    end

    context "for instance variables" do
      it "generates scope_id with class" do
        scope_id = described_class.generate_scope_id(
          :instance_variables,
          class_path: "User"
        )
        expect(scope_id).to eq("User")
      end

      it "generates scope_id with nested class" do
        scope_id = described_class.generate_scope_id(
          :instance_variables,
          class_path: "Api::User"
        )
        expect(scope_id).to eq("Api::User")
      end

      it "generates (top-level) for empty class path" do
        scope_id = described_class.generate_scope_id(
          :instance_variables,
          class_path: ""
        )
        expect(scope_id).to eq("(top-level)")
      end
    end

    context "for class variables" do
      it "generates scope_id with class" do
        scope_id = described_class.generate_scope_id(
          :class_variables,
          class_path: "User"
        )
        expect(scope_id).to eq("User")
      end
    end
  end
end
