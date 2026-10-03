require "spec_helper"
require "hamster/prefix_map"

describe Hamster::PrefixMap do
  describe "#each_prefix" do
    let(:map) do
      Hamster::PrefixMap[
        "app" => 1,
        "apple" => 2,
        "application" => 3,
        "banana" => 4,
        "" => 0,
      ]
    end

    it "yields every entry whose key starts with the prefix" do
      result = map.each_prefix("app").to_a.sort
      expect(result).to eq([["app", 1], ["apple", 2], ["application", 3]])
    end

    it "yields entries when the prefix ends in the middle of a compressed edge" do
      expect(map.each_prefix("appl").to_a.sort).to eq([["apple", 2], ["application", 3]])
      expect(map.each_prefix("ap").to_a.size).to eq(3)
    end

    it "matches the exact key itself" do
      expect(map.each_prefix("apple").to_a).to eq([["apple", 2]])
    end

    it "yields nothing when no key starts with the prefix" do
      expect(map.each_prefix("apq").to_a).to eq([])
      expect(map.each_prefix("bananas").to_a).to eq([])
    end

    it "enumerates the whole map for the empty prefix" do
      expect(map.each_prefix("").to_a.size).to eq(5)
    end

    it "yields key and value as two block arguments" do
      pairs = {}
      map.each_prefix("banana") { |key, value| pairs[key] = value }
      expect(pairs).to eq("banana" => 4)
    end

    it "returns self when given a block" do
      expect(map.each_prefix("app") { |*| }).to equal(map)
    end

    it "returns an Enumerator without a block" do
      expect(map.each_prefix("app")).to be_a(Enumerator)
    end

    it "raises ArgumentError for invalidly encoded prefixes" do
      prefix = "\xFF".dup.force_encoding("UTF-8")
      expect { map.each_prefix(prefix).to_a }.to raise_error(ArgumentError)
    end

    it "raises TypeError for non-string prefixes" do
      expect { map.each_prefix(nil).to_a }.to raise_error(TypeError)
    end

    context "laziness" do
      let(:big_map) do
        map = Hamster::PrefixMap.empty
        1000.times { |i| map = map.put(format("key-%04d", i), i) }
        map
      end

      it "does not precompute the result set" do
        enum = big_map.each_prefix("key-")
        expect(enum.size).to be_nil
      end

      it "can take the first few entries without enumerating the rest" do
        pulled = []
        enum = big_map.each_prefix("key-")
        enum.lazy.map { |pair| pulled << pair }.first(3)
        expect(pulled.size).to eq(3)
        pulled.each { |key, _| expect(key).to start_with("key-") }
      end

      it "produces correct entries when taken lazily" do
        taken = big_map.each_prefix("key-00").take(5)
        expect(taken.size).to eq(5)
        taken.each { |key, value| expect(key).to eq(format("key-%04d", value)) }
      end
    end
  end

  describe "#each" do
    it "enumerates every entry" do
      map = Hamster::PrefixMap["a" => 1, "b" => 2, "c" => nil]
      expect(map.each.to_a.sort_by(&:first)).to eq([["a", 1], ["b", 2], ["c", nil]])
    end

    it "returns an Enumerator without a block" do
      expect(Hamster::PrefixMap["a" => 1].each).to be_a(Enumerator)
    end

    it "supports Enumerable methods" do
      map = Hamster::PrefixMap["a" => 1, "b" => 2]
      expect(map.map { |key, _| key }.sort).to eq(["a", "b"])
      expect(map.count).to eq(2)
    end
  end

  describe "#select" do
    it "returns a PrefixMap with matching entries" do
      map = Hamster::PrefixMap["a" => 1, "b" => 2, "c" => 3]
      result = map.select { |_, value| value.odd? }
      expect(result).to be_a(Hamster::PrefixMap)
      expect(result.each.to_a.sort).to eq([["a", 1], ["c", 3]])
    end
  end
end
