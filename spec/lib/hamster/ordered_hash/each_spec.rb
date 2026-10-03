require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  let(:hash) { OH["A" => "aye", "B" => "bee", "C" => "see"] }

  [:each, :each_pair].each do |method|
    describe "##{method}" do
      it "yields key/value pairs in insertion order" do
        pairs = []
        hash.send(method) { |key, value| pairs << [key, value] }
        expect(pairs).to eq([["A", "aye"], ["B", "bee"], ["C", "see"]])
      end

      it "returns self" do
        expect(hash.send(method) { |*args| }).to be(hash)
      end

      it "returns an enumerator when no block is given" do
        expect(hash.send(method).to_a).to eq([["A", "aye"], ["B", "bee"], ["C", "see"]])
      end
    end
  end

  describe "#reverse_each" do
    it "yields key/value pairs in reverse insertion order" do
      pairs = []
      hash.reverse_each { |key, value| pairs << [key, value] }
      expect(pairs).to eq([["C", "see"], ["B", "bee"], ["A", "aye"]])
    end

    it "returns self" do
      expect(hash.reverse_each { |*args| }).to be(hash)
    end

    it "returns an enumerator when no block is given" do
      expect(hash.reverse_each.to_a).to eq([["C", "see"], ["B", "bee"], ["A", "aye"]])
    end
  end

  describe "#each_key" do
    it "yields keys in insertion order" do
      keys = []
      hash.each_key { |key| keys << key }
      expect(keys).to eq(%w[A B C])
    end

    it "returns an enumerator when no block is given" do
      expect(hash.each_key.to_a).to eq(%w[A B C])
    end
  end

  describe "#each_value" do
    it "yields values in insertion order" do
      values = []
      hash.each_value { |value| values << value }
      expect(values).to eq(%w[aye bee see])
    end

    it "returns an enumerator when no block is given" do
      expect(hash.each_value.to_a).to eq(%w[aye bee see])
    end
  end

  describe "iteration order after structural edits" do
    it "reflects deletes, re-insertions and value replacements" do
      result = hash.delete("B").put("D", "dee").put("A", "AYE").put("B", "BEE")
      expect(result.to_a).to eq([["A", "AYE"], ["C", "see"], ["D", "dee"], ["B", "BEE"]])
      expect(result.reverse_each.to_a).to eq([["B", "BEE"], ["D", "dee"], ["C", "see"], ["A", "AYE"]])
    end
  end
end
