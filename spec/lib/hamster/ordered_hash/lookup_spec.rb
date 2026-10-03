require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  let(:hash) { OH["A" => "aye", "B" => "bee", "C" => "see"] }

  describe "#get (and #[])" do
    [:get, :[]].each do |method|
      it "returns the value for a present key" do
        expect(hash.send(method, "B")).to eq("bee")
      end

      it "returns nil for a missing key" do
        expect(hash.send(method, "Z")).to be_nil
      end

      it "calls the default block for a missing key" do
        with_default = OH.new("A" => 1) { |key| key.size }
        expect(with_default.send(method, "A")).to eq(1)
        expect(with_default.send(method, "missing")).to eq(7)
      end
    end
  end

  describe "#fetch" do
    it "returns the value for a present key" do
      expect(hash.fetch("B")).to eq("bee")
    end

    it "raises KeyError for a missing key" do
      expect { hash.fetch("Z") }.to raise_error(KeyError)
    end

    it "returns the given default for a missing key" do
      expect(hash.fetch("Z", 99)).to eq(99)
    end

    it "yields the missing key to the block" do
      expect(hash.fetch("Z") { |key| key.size }).to eq(1)
    end
  end

  describe "#key?" do
    [:key?, :has_key?, :include?, :member?].each do |method|
      it "returns true for a present key and false otherwise" do
        expect(hash.send(method, "A")).to be(true)
        expect(hash.send(method, "Z")).to be(false)
      end
    end
  end

  describe "#value?" do
    it "returns true if any key maps to the value" do
      expect(hash.value?("bee")).to be(true)
      expect(hash.value?("zebra")).to be(false)
    end
  end

  describe "#size and #empty?" do
    it "reports the number of live pairs" do
      expect(hash.size).to eq(3)
      expect(hash.length).to eq(3)
      expect(hash.delete("A").size).to eq(2)
      expect(hash.empty?).to be(false)
      expect(OH.empty.empty?).to be(true)
    end
  end

  describe "#default_proc" do
    it "returns the default block" do
      block = proc { |key| key }
      expect(OH.new(&block).default_proc).to eq(block)
      expect(hash.default_proc).to be_nil
    end

    it "is preserved across derived copies" do
      with_default = OH.new("A" => 1) { |key| key.size }
      expect(with_default.put("B", 2).get("missing")).to eq(7)
      expect(with_default.delete("A").get("missing")).to eq(7)
      expect(with_default.clear.get("missing")).to eq(7)
    end
  end
end
