require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  describe ".[]" do
    it "returns an empty OrderedHash when given no pairs" do
      expect(OH[]).to be_empty
      expect(OH[].size).to eq(0)
    end

    it "preserves the insertion order of a RubyHash" do
      ordered = OH["C" => 3, "A" => 1, "B" => 2]
      expect(ordered.keys).to eq(["C", "A", "B"])
      expect(ordered.to_a).to eq([["C", 3], ["A", 1], ["B", 2]])
    end

    it "preserves the order of an array of pairs" do
      ordered = OH[[["B", 2], ["A", 1], ["C", 3]]]
      expect(ordered.keys).to eq(["B", "A", "C"])
    end

    it "keeps the first position and the last value for duplicate keys" do
      ordered = OH[[["A", 1], ["B", 2], ["A", 3]]]
      expect(ordered.size).to eq(2)
      expect(ordered.to_a).to eq([["A", 3], ["B", 2]])
    end
  end

  describe ".new" do
    it "creates an empty OrderedHash with no arguments" do
      expect(OH.new).to be_empty
    end

    it "accepts any enumerable of pairs" do
      ordered = OH.new([["A", 1], ["B", 2]].each)
      expect(ordered.to_a).to eq([["A", 1], ["B", 2]])
    end
  end

  describe ".empty" do
    it "returns a memoized, frozen, empty instance" do
      expect(OH.empty).to be(OH.empty)
      expect(OH.empty).to be_frozen
      expect(OH.empty).to be_empty
    end
  end

  describe "string keys" do
    it "duplicates and freezes unfrozen string keys" do
      key = "mutable".dup
      ordered = OH[key => 1]
      stored = ordered.keys.first
      expect(stored).to be_frozen
      expect(stored).to_not be(key)
    end
  end
end
