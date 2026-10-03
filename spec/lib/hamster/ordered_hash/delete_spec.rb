require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  describe "#delete" do
    let(:hash) { OH["A" => "aye", "B" => "bee", "C" => "see"] }

    it "removes the key and closes the gap in the iteration order" do
      expect(hash.delete("B").keys.to_a).to eq(%w[A C])
    end

    it "returns self when the key is not present" do
      expect(hash.delete("Z")).to be(hash)
    end

    it "does not modify the receiver" do
      hash.delete("A")
      expect(hash.keys.to_a).to eq(%w[A B C])
    end

    it "moves a re-inserted key to the end" do
      result = hash.delete("A").put("A", "aye-again")
      expect(result.keys.to_a).to eq(%w[B C A])
      expect(result.get("A")).to eq("aye-again")
    end

    it "returns the canonical empty hash when the last key is removed" do
      expect(hash.delete("A").delete("B").delete("C")).to be(OH.empty)
    end

    it "keeps the default block when emptied" do
      hash = OH.new("A" => 1) { |key| key.size }
      result = hash.delete("A")
      expect(result).to be_empty
      expect(result.get("missing")).to eq(7)
    end

    it "keeps key_at correct through many deletions" do
      result = OH.new
      100.times { |i| result = result.put("key-#{i}", i) }
      75.times { |i| result = result.delete("key-#{i}") }
      expected = (75..99).map { |i| "key-#{i}" }
      expect(result.keys.to_a).to eq(expected)
      expected.each_with_index do |key, i|
        expect(result.key_at(i)).to eq(key)
      end
    end
  end
end
