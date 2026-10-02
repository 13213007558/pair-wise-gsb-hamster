require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  let(:ordered) { OH["C" => 3, "A" => 1, "B" => 2] }

  describe "#each" do
    it "yields key/value pairs in insertion order and returns self" do
      yielded = []
      result = ordered.each { |key, value| yielded << [key, value] }
      expect(yielded).to eq([["C", 3], ["A", 1], ["B", 2]])
      expect(result).to be(ordered)
    end

    it "returns an Enumerator when no block is given" do
      expect(ordered.each.to_a).to eq([["C", 3], ["A", 1], ["B", 2]])
    end
  end

  describe "#reverse_each" do
    it "yields key/value pairs in reverse insertion order" do
      yielded = []
      ordered.reverse_each { |key, value| yielded << [key, value] }
      expect(yielded).to eq([["B", 2], ["A", 1], ["C", 3]])
    end
  end

  describe "#each_key and #each_value" do
    it "iterate in insertion order" do
      expect(ordered.each_key.to_a).to eq(["C", "A", "B"])
      expect(ordered.each_value.to_a).to eq([3, 1, 2])
    end
  end

  describe "#keys and #values" do
    it "return frozen arrays in insertion order" do
      expect(ordered.keys).to eq(["C", "A", "B"])
      expect(ordered.keys).to be_frozen
      expect(ordered.values).to eq([3, 1, 2])
      expect(ordered.values).to be_frozen
    end
  end

  describe "#to_a" do
    it "returns a frozen array of pairs in insertion order" do
      expect(ordered.to_a).to eq([["C", 3], ["A", 1], ["B", 2]])
      expect(ordered.to_a).to be_frozen
    end
  end

  describe "#to_hash" do
    it "returns a RubyHash which enumerates in the same order" do
      ruby_hash = ordered.to_hash
      expect(ruby_hash).to eq({"C" => 3, "A" => 1, "B" => 2})
      expect(ruby_hash.keys).to eq(["C", "A", "B"])
    end
  end

  describe "#select" do
    it "keeps the relative order of the remaining pairs" do
      result = ordered.select { |key, value| value > 1 }
      expect(result).to be_a(Hamster::OrderedHash)
      expect(result.to_a).to eq([["C", 3], ["B", 2]])
    end
  end

  describe "#first" do
    it "returns the first pair in insertion order" do
      expect(ordered.first).to eq(["C", 3])
    end
  end

  describe "#inspect" do
    it "renders pairs in insertion order" do
      expect(ordered.inspect).to eq('Hamster::OrderedHash["C" => 3, "A" => 1, "B" => 2]')
    end
  end
end
