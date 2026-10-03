require "spec_helper"
require "hamster/prefix_map"

describe Hamster::PrefixMap do
  describe ".[]" do
    it "creates an empty map with no arguments" do
      expect(Hamster::PrefixMap[]).to be_empty
    end

    it "creates a map from a hash of pairs" do
      map = Hamster::PrefixMap["a" => 1, "ab" => 2]
      expect(map.size).to eq(2)
      expect(map.get("a")).to eq(1)
      expect(map.get("ab")).to eq(2)
    end

    it "creates a map from an array of pairs" do
      map = Hamster::PrefixMap[[["a", 1], ["b", 2]]]
      expect(map.size).to eq(2)
      expect(map.get("b")).to eq(2)
    end

    it "accepts nil values" do
      map = Hamster::PrefixMap["a" => nil]
      expect(map.size).to eq(1)
      expect(map.key?("a")).to be(true)
    end

    it "rejects non-string keys" do
      expect { Hamster::PrefixMap[[:a, 1]] }.to raise_error(TypeError)
    end

    it "rejects keys with invalid encoding" do
      key = "\xFF".dup.force_encoding("UTF-8")
      expect { Hamster::PrefixMap[[key, 1]] }.to raise_error(ArgumentError)
    end
  end

  describe ".empty" do
    it "returns an empty map" do
      expect(Hamster::PrefixMap.empty.size).to eq(0)
    end

    it "returns the same object on subsequent calls" do
      expect(Hamster::PrefixMap.empty).to equal(Hamster::PrefixMap.empty)
    end
  end

  describe ".new" do
    it "is immutable" do
      expect(Hamster::PrefixMap["a" => 1]).to be_frozen
    end

    it "counts duplicate keys only once" do
      map = Hamster::PrefixMap.new([["a", 1], ["a", 2]])
      expect(map.size).to eq(1)
      expect(map.get("a")).to eq(2)
    end
  end
end
