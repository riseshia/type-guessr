# frozen_string_literal: true

require "spec_helper"

RSpec.describe TypeGuessr::Core::NodeKeyGenerator do
  describe "module_function methods" do
    it "generates local_write key" do
      expect(described_class.local_write(:foo, 42)).to eq("local_write:foo:42")
    end

    it "generates local_read key" do
      expect(described_class.local_read(:bar, 100)).to eq("local_read:bar:100")
    end

    it "generates ivar_write key" do
      expect(described_class.ivar_write(:@name, 50)).to eq("ivar_write:@name:50")
    end

    it "generates ivar_read key" do
      expect(described_class.ivar_read(:@name, 75)).to eq("ivar_read:@name:75")
    end

    it "generates cvar_write key" do
      expect(described_class.cvar_write(:@@count, 30)).to eq("cvar_write:@@count:30")
    end

    it "generates cvar_read key" do
      expect(described_class.cvar_read(:@@count, 60)).to eq("cvar_read:@@count:60")
    end

    it "generates global_write key" do
      expect(described_class.global_write(:$global, 10)).to eq("global_write:$global:10")
    end

    it "generates global_read key" do
      expect(described_class.global_read(:$global, 20)).to eq("global_read:$global:20")
    end

    it "generates param key" do
      expect(described_class.param(:user, 80)).to eq("param:user:80")
    end

    it "generates bparam key" do
      expect(described_class.bparam(0, 90)).to eq("bparam:0:90")
    end

    it "generates call key" do
      expect(described_class.call(:each, 110)).to eq("call:each:110")
    end

    it "generates def_node key" do
      expect(described_class.def_node(:process, 120)).to eq("def:process:120")
    end

    it "generates self_node key" do
      expect(described_class.self_node("User", 130)).to eq("self:User:130")
    end

    it "generates return_node key" do
      expect(described_class.return_node(140)).to eq("return:140")
    end

    it "generates merge key" do
      expect(described_class.merge(150)).to eq("merge:150")
    end

    it "generates literal key" do
      expect(described_class.literal("String", 160)).to eq("lit:String:160")
    end

    it "generates constant key" do
      expect(described_class.constant("CONSTANT", 170)).to eq("const:CONSTANT:170")
    end

    it "generates class_module key" do
      expect(described_class.class_module("User", 180)).to eq("class:User:180")
    end
  end

  describe "edge cases" do
    it "handles nil offset" do
      expect(described_class.local_write(:foo, nil)).to eq("local_write:foo:")
    end

    it "handles symbol method name" do
      expect(described_class.call(:[], 100)).to eq("call:[]:100")
    end

    it "handles forwarding param" do
      expect(described_class.param(:"...", 200)).to eq("param:...:200")
    end
  end
end
