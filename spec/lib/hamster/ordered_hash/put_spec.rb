require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  describe "#put" do
    let(:hash) { OH["A" => "aye", "B" => "bee", "C" => "see"] }

    it "appends a new key at the end of the insertion order" do
      expect(hash.put("D", "dee").keys.to_a).to eq(%w[A B C D])
    end

    it "keeps the position of an existing key when replacing its value" do
      result = hash.put("B", "BEE")
      expect(result.keys.to_a).to eq(%w[A B C])
      expect(result.get("B")).to eq("BEE")
    end

    it "returns self when an identical value is stored again" do
      numbers = OH["A" => 1, "B" => 2]
      expect(numbers.put("B", 2)).to be(numbers)
    end

    it "does not modify the receiver" do
      hash.put("D", "dee")
      expect(hash.keys.to_a).to eq(%w[A B C])
    end

    it "preserves the values of other keys" do
      result = hash.put("B", "BEE")
      expect(result.get("A")).to eq("aye")
      expect(result.get("C")).to eq("see")
    end

    it "passes the previous value to the block form" do
      result = hash.put("A") { |value| value.upcase }
      expect(result.get("A")).to eq("AYE")
      expect(result.keys.to_a).to eq(%w[A B C])
    end

    it "passes nil to the block form for a missing key" do
      result = hash.put("Z") { |value| value.inspect }
      expect(result.get("Z")).to eq("nil")
      expect(result.keys.to_a).to eq(%w[A B C Z])
    end

    it "keeps the originally stored key object when an eql? key is re-put" do
      key = DeterministicHash.new(:a, 0)
      duplicate = DeterministicHash.new(:a, 0)
      result = OH.new.put(key, 1).put(duplicate, 2)
      expect(result.size).to eq(1)
      expect(result.key_at(0)).to equal(key)
      expect(result.get(duplicate)).to eq(2)
    end

    it "supports #store as an alias" do
      expect(hash.store("D", "dee").keys.to_a).to eq(%w[A B C D])
    end

    it "raises NoMethodError for #[]=" do
      expect { hash["D"] = "dee" }.to raise_error(NoMethodError)
    end
  end
end
