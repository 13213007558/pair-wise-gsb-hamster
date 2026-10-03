require "spec_helper"
require "hamster/prefix_map"

describe Hamster::PrefixMap do
  describe "#delete" do
    let(:map) { Hamster::PrefixMap["abc" => 1, "abd" => 2, "b" => 3] }

    it "returns a new map without the key" do
      result = map.delete("abc")
      expect(result.key?("abc")).to be(false)
      expect(result.size).to eq(2)
    end

    it "leaves the original map unchanged" do
      map.delete("abc")
      expect(map.key?("abc")).to be(true)
      expect(map.size).to eq(3)
    end

    it "returns self when the key is missing" do
      expect(map.delete("nope")).to equal(map)
      expect(map.delete("ab")).to equal(map)
      expect(map.delete("abcd")).to equal(map)
      expect(map.delete("")).to equal(map)
    end

    it "removes nil-valued keys" do
      result = Hamster::PrefixMap["a" => nil].delete("a")
      expect(result).to be_empty
    end

    it "removes the empty string key" do
      result = Hamster::PrefixMap["" => 1, "a" => 2].delete("")
      expect(result.key?("")).to be(false)
      expect(result.get("a")).to eq(2)
    end

    it "merges edges after removal so lookups still work" do
      result = Hamster::PrefixMap["abcdef" => 1, "abcxyz" => 2].delete("abcxyz")
      expect(result.get("abcdef")).to eq(1)
      expect(result.key?("abcxyz")).to be(false)
      expect(result.size).to eq(1)
    end

    it "keeps sibling branches intact when merging" do
      result = Hamster::PrefixMap["abc" => 1, "abd" => 2, "b" => 3].delete("abc")
      expect(result.get("abd")).to eq(2)
      expect(result.get("b")).to eq(3)
    end

    it "collapses chains of single-child nodes" do
      map = Hamster::PrefixMap["aaaa" => 1, "aaab" => 2, "b" => 3]
      result = map.delete("aaab")
      expect(result.get("aaaa")).to eq(1)
      expect(result.get("b")).to eq(3)
      expect(result.size).to eq(2)
    end

    it "can empty the map completely" do
      result = Hamster::PrefixMap["a" => 1].delete("a")
      expect(result).to be_empty
      expect(result.each.to_a).to eq([])
    end

    it "raises ArgumentError for invalidly encoded keys" do
      key = "\xFF".dup.force_encoding("UTF-8")
      expect { map.delete(key) }.to raise_error(ArgumentError)
    end

    it "raises TypeError for non-string keys" do
      expect { map.delete(nil) }.to raise_error(TypeError)
    end
  end
end
