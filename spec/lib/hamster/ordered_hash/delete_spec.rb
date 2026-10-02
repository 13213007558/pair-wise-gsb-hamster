require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  describe "#delete" do
    let(:ordered) { OH["A" => "aye", "B" => "bee", "C" => "see"] }

    it "removes the key and preserves the order of the rest" do
      result = ordered.delete("B")
      expect(result.to_a).to eq([["A", "aye"], ["C", "see"]])
      expect(result.size).to eq(2)
    end

    it "returns self when the key is not present" do
      expect(ordered.delete("Z")).to be(ordered)
    end

    it "does not modify the receiver" do
      ordered.delete("A")
      expect(ordered.keys).to eq(["A", "B", "C"])
    end

    it "places a re-added key at the end of the order" do
      result = ordered.delete("A").put("A", "AYE")
      expect(result.to_a).to eq([["B", "bee"], ["C", "see"], ["A", "AYE"]])
    end

    it "can remove every key" do
      result = ordered.delete("A").delete("B").delete("C")
      expect(result).to be_empty
      expect(result.keys).to eq([])
    end
  end
end
