require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  describe "#put" do
    let(:ordered) { OH["A" => "aye", "B" => "bee", "C" => "see"] }

    it "appends a new key at the end of the order" do
      expect(ordered.put("D", "dee").keys).to eq(["A", "B", "C", "D"])
    end

    it "replaces the value of an existing key without moving it" do
      result = ordered.put("B", "BEE")
      expect(result.to_a).to eq([["A", "aye"], ["B", "BEE"], ["C", "see"]])
    end

    it "returns self when the identical value is stored again" do
      expect(ordered.put("B", ordered.get("B"))).to be(ordered)
    end

    it "does not modify the receiver" do
      ordered.put("D", "dee")
      ordered.put("A", "AYE")
      expect(ordered.to_a).to eq([["A", "aye"], ["B", "bee"], ["C", "see"]])
    end

    context "with a block" do
      it "passes the existing value to the block" do
        result = ordered.put("A") { |value| value.upcase }
        expect(result.get("A")).to eq("AYE")
      end

      it "passes nil to the block when there is no existing association" do
        result = ordered.put("D") { |value| value.nil? ? "dee" : "wrong" }
        expect(result.get("D")).to eq("dee")
      end

      it "keeps the key in place when the block updates an existing key" do
        result = ordered.put("B") { |value| value * 2 }
        expect(result.keys).to eq(["A", "B", "C"])
      end
    end

    context "with keys which have the same #hash but are not #eql?" do
      let(:key_a) { DeterministicHash.new("a", 1) }
      let(:key_b) { DeterministicHash.new("b", 1) }
      let(:key_c) { DeterministicHash.new("c", 1) }

      it "stores all of them, in insertion order" do
        result = OH.empty.put(key_a, 1).put(key_b, 2).put(key_c, 3)
        expect(result.size).to eq(3)
        expect(result.keys).to eq([key_a, key_b, key_c])
        expect(result.get(key_a)).to eq(1)
        expect(result.get(key_b)).to eq(2)
        expect(result.get(key_c)).to eq(3)
      end

      it "updates a colliding key in place" do
        result = OH.empty.put(key_a, 1).put(key_b, 2).put(key_b, 22)
        expect(result.size).to eq(2)
        expect(result.keys).to eq([key_a, key_b])
        expect(result.get(key_b)).to eq(22)
      end

      it "moves a deleted colliding key to the end when re-added" do
        result = OH.empty.put(key_a, 1).put(key_b, 2).put(key_c, 3)
        result = result.delete(key_b).put(key_b, 22)
        expect(result.keys).to eq([key_a, key_c, key_b])
        expect(result.get(key_b)).to eq(22)
      end
    end
  end
end
