require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  describe "#eql?" do
    it "is true for the same pairs in the same order" do
      expect(OH["A" => 1, "B" => 2].eql?(OH["A" => 1, "B" => 2])).to be(true)
    end

    it "is false when the key order differs" do
      expect(OH["A" => 1, "B" => 2].eql?(OH["B" => 2, "A" => 1])).to be(false)
    end

    it "is false when a value differs" do
      expect(OH["A" => 1].eql?(OH["A" => 2])).to be(false)
    end

    it "is false when a key differs" do
      expect(OH["A" => 1].eql?(OH["B" => 1])).to be(false)
    end

    it "is false for another class" do
      expect(OH["A" => 1].eql?(H["A" => 1])).to be(false)
    end
  end

  describe "#==" do
    it "is true for the same pairs in the same order" do
      expect(OH["A" => 1, "B" => 2]).to eq(OH["A" => 1, "B" => 2])
    end

    it "is false when the key order differs" do
      expect(OH["A" => 1, "B" => 2]).to_not eq(OH["B" => 2, "A" => 1])
    end

    it "is false for objects which are not OrderedHashes" do
      expect(OH["A" => 1]).to_not eq({"A" => 1})
    end
  end
end
