require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  context "with keys which have the same #hash but are not #eql?" do
    let(:key_a) { DeterministicHash.new(:a, 0) }
    let(:key_b) { DeterministicHash.new(:b, 0) }
    let(:key_c) { DeterministicHash.new(:c, 0) }

    it "treats them as distinct members, each with its own position" do
      hash = OH.new.put(key_a, 1).put(key_b, 2).put(key_c, 3)
      expect(hash.size).to eq(3)
      expect(hash.keys.to_a).to eq([key_a, key_b, key_c])
      expect(hash.get(key_a)).to eq(1)
      expect(hash.get(key_b)).to eq(2)
      expect(hash.get(key_c)).to eq(3)
      expect(hash.key_at(0)).to equal(key_a)
      expect(hash.key_at(1)).to equal(key_b)
      expect(hash.key_at(2)).to equal(key_c)
    end

    it "moves a deleted and re-inserted colliding key to the end" do
      hash = OH.new.put(key_a, 1).put(key_b, 2).put(key_c, 3)
      result = hash.delete(key_a).put(key_a, 10)
      expect(result.keys.to_a).to eq([key_b, key_c, key_a])
      expect(result.get(key_a)).to eq(10)
      expect(result.key_at(2)).to equal(key_a)
    end

    it "keeps the originally stored key object when an eql? key is re-put" do
      duplicate = DeterministicHash.new(:a, 0)
      hash = OH.new.put(key_a, 1).put(duplicate, 2)
      expect(hash.size).to eq(1)
      expect(hash.key_at(0)).to equal(key_a)
      expect(hash.get(duplicate)).to eq(2)
    end

    it "deletes only the eql? key among colliding keys" do
      hash = OH.new.put(key_a, 1).put(key_b, 2).put(key_c, 3)
      result = hash.delete(key_b)
      expect(result.size).to eq(2)
      expect(result.keys.to_a).to eq([key_a, key_c])
      expect(result.key?(key_b)).to be(false)
    end
  end
end
