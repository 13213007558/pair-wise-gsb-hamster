require "spec_helper"
require "hamster/prefix_map"

describe Hamster::PrefixMap do
  describe "#put" do
    let(:map) { Hamster::PrefixMap["abc" => 1, "abd" => 2] }

    it "returns a new map with the association added" do
      result = map.put("x", 3)
      expect(result.get("x")).to eq(3)
      expect(result.size).to eq(3)
    end

    it "leaves the original map unchanged" do
      map.put("x", 3)
      expect(map.key?("x")).to be(false)
      expect(map.size).to eq(2)
    end

    it "replaces the value of an existing key without growing" do
      result = map.put("abc", 99)
      expect(result.get("abc")).to eq(99)
      expect(result.size).to eq(2)
    end

    it "returns self when the same value is stored again" do
      expect(map.put("abc", 1)).to equal(map)
    end

    it "computes the value from the old value when a block is given" do
      result = map.put("abc") { |old| old + 100 }
      expect(result.get("abc")).to eq(101)
    end

    it "passes nil to the block for a missing key" do
      result = map.put("zzz") { |old| old.nil? ? 7 : 8 }
      expect(result.get("zzz")).to eq(7)
    end

    it "stores nil as a real value" do
      result = map.put("nil-key", nil)
      expect(result.key?("nil-key")).to be(true)
      expect(result.get("nil-key")).to be_nil
      expect(result.fetch("nil-key", :default)).to be_nil
    end

    it "accepts the empty string as a key" do
      result = map.put("", 0)
      expect(result.get("")).to eq(0)
      expect(result.size).to eq(3)
    end

    it "splits a compressed edge when a key diverges midway" do
      result = Hamster::PrefixMap["abcdef" => 1].put("abcxyz", 2)
      expect(result.get("abcdef")).to eq(1)
      expect(result.get("abcxyz")).to eq(2)
      expect(result.get("abc")).to be_nil
    end

    it "splits a compressed edge when a new key is a strict prefix of an old one" do
      result = Hamster::PrefixMap["abcdef" => 1].put("abc", 2)
      expect(result.get("abc")).to eq(2)
      expect(result.get("abcdef")).to eq(1)
    end

    it "handles keys sharing only a partial edge character run" do
      result = Hamster::PrefixMap["aaaa" => 1].put("aabb", 2)
      expect(result.get("aaaa")).to eq(1)
      expect(result.get("aabb")).to eq(2)
    end

    it "stores multi-byte unicode keys by codepoints" do
      result = map.put("日本語", 3).put("🎉🎊", 4)
      expect(result.get("日本語")).to eq(3)
      expect(result.get("🎉🎊")).to eq(4)
    end

    it "does not fold case" do
      result = Hamster::PrefixMap["ABC" => 1].put("abc", 2)
      expect(result.size).to eq(2)
      expect(result.get("ABC")).to eq(1)
      expect(result.get("abc")).to eq(2)
    end

    it "does not normalize unicode" do
      composed = "é"
      decomposed = "é"
      expect(composed).not_to eq(decomposed)
      result = Hamster::PrefixMap[composed => 1].put(decomposed, 2)
      expect(result.size).to eq(2)
      expect(result.get(composed)).to eq(1)
      expect(result.get(decomposed)).to eq(2)
    end

    it "treats strings with equal codepoints but different encodings as the same key" do
      ascii = "abc".encode("US-ASCII")
      result = Hamster::PrefixMap[ascii => 1]
      expect(result.get("abc".dup.force_encoding("UTF-8"))).to eq(1)
      expect(result.size).to eq(1)
    end

    it "raises TypeError for non-string keys" do
      expect { map.put(:symbol, 1) }.to raise_error(TypeError)
      expect { map.put(42, 1) }.to raise_error(TypeError)
      expect { map.put(nil, 1) }.to raise_error(TypeError)
    end

    it "raises ArgumentError for keys with invalid encoding" do
      key = "\xFF\xFE".dup.force_encoding("UTF-8")
      expect(key.valid_encoding?).to be(false)
      expect { map.put(key, 1) }.to raise_error(ArgumentError)
    end

    it "freezes stored keys" do
      key = "mutable".dup
      result = Hamster::PrefixMap.empty.put(key, 1)
      stored = result.each_prefix("").first[0]
      expect(stored).to be_frozen
    end
  end
end
