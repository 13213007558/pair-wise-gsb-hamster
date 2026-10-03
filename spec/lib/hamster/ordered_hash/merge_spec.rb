require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  describe "#merge" do
    let(:hash) { OH["A" => 1, "B" => 2, "C" => 3] }

    it "keeps the receiver's position for keys present in both hashes" do
      result = hash.merge("B" => 20, "A" => 10)
      expect(result.keys.to_a).to eq(%w[A B C])
      expect(result.values.to_a).to eq([10, 20, 3])
    end

    it "appends new keys in the order they occur in the other collection" do
      result = hash.merge("E" => 5, "D" => 4)
      expect(result.keys.to_a).to eq(%w[A B C E D])
    end

    it "matches RubyHash's merge order exactly" do
      left = { "A" => 1, "B" => 2, "C" => 3 }
      right = { "C" => 30, "D" => 4, "A" => 10, "E" => 5 }
      result = OH.new(left).merge(right)
      expect(result.to_a).to eq(left.merge(right).to_a)
    end

    it "uses the block to resolve values for duplicate keys" do
      result = hash.merge("B" => 20, "D" => 4) { |key, old, new| old + new }
      expect(result.keys.to_a).to eq(%w[A B C D])
      expect(result.get("B")).to eq(22)
      expect(result.get("D")).to eq(4)
    end

    it "does not call the block for keys which are not duplicated" do
      yielded = []
      hash.merge("D" => 4) { |*args| yielded << args }
      expect(yielded).to be_empty
    end

    it "accepts another OrderedHash" do
      result = hash.merge(OH["C" => 30, "D" => 4])
      expect(result.keys.to_a).to eq(%w[A B C D])
      expect(result.get("C")).to eq(30)
    end

    it "accepts a Hamster::Hash" do
      result = hash.merge(H["C" => 30, "D" => 4])
      expect(result.keys.to_a).to eq(%w[A B C D])
      expect(result.get("C")).to eq(30)
    end

    it "accepts an enumerable of pairs" do
      result = hash.merge([["C", 30], ["D", 4]])
      expect(result.keys.to_a).to eq(%w[A B C D])
      expect(result.get("C")).to eq(30)
    end

    it "returns self when nothing changes" do
      expect(hash.merge("B" => 2)).to be(hash)
      expect(hash.merge({})).to be(hash)
    end

    it "does not modify the receiver" do
      hash.merge("B" => 20, "D" => 4)
      expect(hash.keys.to_a).to eq(%w[A B C])
      expect(hash.get("B")).to eq(2)
    end

    it "keeps the first position when the other collection repeats a new key" do
      result = hash.merge([["D", 4], ["E", 5], ["D", 40]])
      expect(result.keys.to_a).to eq(%w[A B C D E])
      expect(result.get("D")).to eq(40)
    end
  end
end
