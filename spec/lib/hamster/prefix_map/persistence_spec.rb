require "spec_helper"
require "hamster/prefix_map"

describe Hamster::PrefixMap do
  describe "persistence" do
    it "keeps the old version intact when an insert splits a compressed edge" do
      v1 = Hamster::PrefixMap["abcdef" => 1]
      v2 = v1.put("abcxyz", 2)
      expect(v1.each.to_a).to eq([["abcdef", 1]])
      expect(v1.get("abcxyz")).to be_nil
      expect(v2.get("abcdef")).to eq(1)
      expect(v2.get("abcxyz")).to eq(2)
    end

    it "keeps the old version intact when a delete merges edges" do
      v1 = Hamster::PrefixMap["abcdef" => 1, "abcxyz" => 2]
      v2 = v1.delete("abcxyz")
      expect(v1.get("abcxyz")).to eq(2)
      expect(v1.size).to eq(2)
      expect(v2.get("abcdef")).to eq(1)
      expect(v2.key?("abcxyz")).to be(false)
    end

    it "keeps every intermediate version usable" do
      versions = [Hamster::PrefixMap.empty]
      keys = %w[aaaa aaab aaba abaa baaa aaaa1 aaaa2]
      keys.each_with_index do |key, i|
        versions << versions.last.put(key, i)
      end
      versions << versions.last.delete("aaaa")
      versions << versions.last.delete("baaa")
      versions.each_with_index do |version, i|
        expected = {}
        keys.each_with_index do |key, j|
          expected[key] = j if j < i
        end
        expected.delete("aaaa") if i > keys.size
        expected.delete("baaa") if i > keys.size + 1
        expect(version.each.to_a.sort).to eq(expected.to_a.sort)
        expect(version.size).to eq(expected.size)
      end
    end

    it "shares structure without aliasing mutable state" do
      v1 = Hamster::PrefixMap["shared-prefix-a" => 1, "shared-prefix-b" => 2]
      v2 = v1.put("other", 3).delete("shared-prefix-a")
      expect(v1.longest_prefix("shared-prefix-b!")).to eq("shared-prefix-b")
      expect(v1.each_prefix("shared").to_a.size).to eq(2)
      expect(v2.each_prefix("shared").to_a).to eq([["shared-prefix-b", 2]])
    end
  end
end
