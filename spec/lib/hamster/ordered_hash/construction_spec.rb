require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  describe ".[]" do
    it "returns the canonical empty hash when no pairs are given" do
      expect(OH[]).to be(OH.empty)
      expect(OH[nil]).to be(OH.empty)
      expect(OH[{}]).to be(OH.empty)
    end

    it "accepts a Ruby hash and preserves its order" do
      hash = OH["B" => 2, "A" => 1, "C" => 3]
      expect(hash.keys.to_a).to eq(%w[B A C])
      expect(hash.values.to_a).to eq([2, 1, 3])
    end

    it "accepts an enumerable of pairs" do
      hash = OH[[["B", 2], ["A", 1]]]
      expect(hash.keys.to_a).to eq(%w[B A])
    end
  end

  describe ".new" do
    it "returns an empty hash by default" do
      expect(OH.new).to be_empty
      expect(OH.new.size).to eq(0)
    end

    it "keeps the first position when pairs contain duplicate keys" do
      hash = OH.new([["A", 1], ["B", 2], ["A", 3]])
      expect(hash.size).to eq(2)
      expect(hash.keys.to_a).to eq(%w[A B])
      expect(hash.get("A")).to eq(3)
    end

    it "stores a default block" do
      hash = OH.new("A" => 1) { |key| key.size }
      expect(hash.get("B")).to eq(1)
      expect(hash.get("missing")).to eq(7)
      expect(hash.default_proc).to be_a(Proc)
    end

    it "duplicates and freezes unfrozen string keys" do
      key = "mutable".dup
      hash = OH.new([[key, 1]])
      stored = hash.key_at(0)
      expect(stored).to eq("mutable")
      expect(stored).to be_frozen
      expect(stored).not_to equal(key)
    end
  end

  describe ".empty" do
    it "returns the same instance every time" do
      expect(OH.empty).to be(OH.empty)
    end

    it "returns an empty instance of a subclass" do
      subclass = Class.new(OH)
      expect(subclass.empty).to be_a(subclass)
      expect(subclass.empty).to be_empty
    end
  end
end
