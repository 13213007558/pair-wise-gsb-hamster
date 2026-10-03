require "spec_helper"
require "hamster/prefix_map"

describe Hamster::PrefixMap do
  describe "compared against naive Hash filtering" do
    alphabet = ["a", "b", "c", "ab", "日", "é", "🎉"]
    rng = Random.new(20261001)

    random_key = lambda do
      length = rng.rand(0..8)
      (0...length).map { alphabet[rng.rand(alphabet.size)] }.join
    end

    map = Hamster::PrefixMap.empty
    reference = {}
    600.times do |i|
      key = random_key.call
      if rng.rand < 0.6
        value = rng.rand < 0.1 ? nil : rng.rand(1000)
        map = map.put(key, value)
        reference[key] = value
      else
        map = map.delete(key)
        reference.delete(key)
      end
    end

    it "agrees on size" do
      expect(map.size).to eq(reference.size)
      expect(map.empty?).to eq(reference.empty?)
    end

    it "agrees on full enumeration" do
      expect(map.each.to_a.sort_by(&:first)).to eq(reference.to_a.sort_by(&:first))
    end

    it "agrees on point lookups" do
      (reference.keys + Array.new(30) { random_key.call }).each do |key|
        expect(map.key?(key)).to eq(reference.key?(key))
        expect(map.get(key)).to eq(reference[key])
      end
    end

    it "agrees on longest-prefix matches" do
      queries = reference.keys.first(20) + Array.new(30) { random_key.call } + ["", "日"]
      queries.each do |query|
        naive = reference.keys.select { |key| query.start_with?(key) }.max_by(&:length)
        expect(map.longest_prefix(query)).to eq(naive)
      end
    end

    it "agrees on prefix enumeration" do
      prefixes = ["", "a", "ab", "日", "🎉", "nope"] + Array.new(10) { random_key.call }
      prefixes.each do |prefix|
        naive = reference.select { |key, _| key.start_with?(prefix) }.to_a.sort_by(&:first)
        expect(map.each_prefix(prefix).to_a.sort_by(&:first)).to eq(naive)
      end
    end

    it "agrees after a second round of mixed updates" do
      200.times do
        key = random_key.call
        map = map.put(key, rng.rand(100))
        reference[key] = map.get(key)
        key = random_key.call
        map = map.delete(key)
        reference.delete(key)
      end
      expect(map.each.to_a.sort_by(&:first)).to eq(reference.to_a.sort_by(&:first))
    end
  end
end
