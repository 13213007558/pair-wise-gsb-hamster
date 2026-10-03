require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  describe "#key_at" do
    let(:hash) { OH["A" => 1, "B" => 2, "C" => 3] }

    it "returns the key at the given position in insertion order" do
      expect(hash.key_at(0)).to eq("A")
      expect(hash.key_at(1)).to eq("B")
      expect(hash.key_at(2)).to eq("C")
    end

    it "supports negative indices counting from the end" do
      expect(hash.key_at(-1)).to eq("C")
      expect(hash.key_at(-2)).to eq("B")
      expect(hash.key_at(-3)).to eq("A")
    end

    it "returns nil for out-of-range indices" do
      expect(hash.key_at(3)).to be_nil
      expect(hash.key_at(100)).to be_nil
      expect(hash.key_at(-4)).to be_nil
    end

    it "returns nil for any index on an empty hash" do
      expect(OH.empty.key_at(0)).to be_nil
      expect(OH.empty.key_at(-1)).to be_nil
    end

    it "skips the slots of deleted keys" do
      result = hash.delete("B")
      expect(result.key_at(0)).to eq("A")
      expect(result.key_at(1)).to eq("C")
      expect(result.key_at(2)).to be_nil
    end

    it "stays consistent with #keys after many deletions and re-insertions" do
      result = OH.new
      50.times { |i| result = result.put("key-#{i}", i) }
      40.times { |i| result = result.delete("key-#{i}") }
      20.times { |i| result = result.put("new-#{i}", i) }
      keys = result.keys.to_a
      keys.each_with_index do |key, i|
        expect(result.key_at(i)).to eq(key)
      end
      expect(result.key_at(keys.size)).to be_nil
      expect(result.key_at(-keys.size - 1)).to be_nil
    end
  end
end
