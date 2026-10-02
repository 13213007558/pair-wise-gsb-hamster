require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  let(:ordered) { OH["A" => "aye", "B" => "bee"] }

  describe "#get and #[]" do
    it "return the associated value" do
      expect(ordered.get("A")).to eq("aye")
      expect(ordered["B"]).to eq("bee")
    end

    it "return nil for missing keys" do
      expect(ordered.get("Z")).to be_nil
      expect(ordered["Z"]).to be_nil
    end
  end

  describe "#fetch" do
    it "returns the associated value when the key is present" do
      expect(ordered.fetch("A")).to eq("aye")
    end

    it "returns the default when the key is missing" do
      expect(ordered.fetch("Z", "zee")).to eq("zee")
    end

    it "yields the key to the block when the key is missing" do
      expect(ordered.fetch("Z") { |key| key.downcase }).to eq("z")
    end

    it "raises KeyError when the key is missing and no default is given" do
      expect { ordered.fetch("Z") }.to raise_error(KeyError, /key not found/)
    end
  end

  describe "#key?" do
    it "checks for key presence" do
      expect(ordered.key?("A")).to be(true)
      expect(ordered.key?("Z")).to be(false)
      expect(ordered).to include("B")
    end
  end

  describe "#value?" do
    it "checks for value presence" do
      expect(ordered.value?("aye")).to be(true)
      expect(ordered.value?("zee")).to be(false)
    end
  end

  describe "#clear" do
    it "returns an empty OrderedHash" do
      expect(ordered.clear).to be_empty
    end
  end
end
