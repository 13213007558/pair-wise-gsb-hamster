require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  describe "#merge" do
    let(:ordered) { OH["A" => "aye", "B" => "bee", "C" => "see"] }

    it "lets the other collection's value win on conflicting keys, without moving them" do
      result = ordered.merge("B" => "BEE")
      expect(result.to_a).to eq([["A", "aye"], ["B", "BEE"], ["C", "see"]])
    end

    it "appends new keys at the end, in the order the other collection yields them" do
      result = ordered.merge("E" => "ee", "D" => "dee")
      expect(result.keys).to eq(["A", "B", "C", "E", "D"])
    end

    it "handles conflicts and new keys in a single pass" do
      result = ordered.merge("C" => "SEE", "D" => "dee", "A" => "AYE")
      expect(result.to_a).to eq([["A", "AYE"], ["B", "bee"], ["C", "SEE"], ["D", "dee"]])
    end

    it "uses the iteration order of another OrderedHash for new keys" do
      other = OH["D" => "dee", "B" => "BEE", "E" => "ee"]
      result = ordered.merge(other)
      expect(result.to_a).to eq([["A", "aye"], ["B", "BEE"], ["C", "see"], ["D", "dee"], ["E", "ee"]])
    end

    it "accepts an array of pairs" do
      result = ordered.merge([["D", "dee"], ["A", "AYE"]])
      expect(result.to_a).to eq([["A", "AYE"], ["B", "bee"], ["C", "see"], ["D", "dee"]])
    end

    it "returns self when the other collection is empty" do
      expect(ordered.merge({})).to be(ordered)
    end

    it "does not modify the receiver" do
      ordered.merge("B" => "BEE", "D" => "dee")
      expect(ordered.to_a).to eq([["A", "aye"], ["B", "bee"], ["C", "see"]])
    end
  end
end
