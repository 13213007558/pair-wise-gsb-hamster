require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  let(:described_class) { Hamster::OrderedHash }

  it "is an immutable Hamster Hash" do
    expect(described_class.new).to be_a(Hamster::Hash)
    expect(described_class.new).to be_frozen
  end

  it "retains insertion order after clearing and repopulating a hash with a default proc" do
    ordered_hash = described_class.new([["a", 1]]) { |key| key }

    repopulated = ordered_hash.clear.put("b", 2).put("a", 1)

    expect(repopulated.to_a).to eq([["b", 2], ["a", 1]])
    expect(repopulated.default_proc).to be_a(Proc)
    expect(repopulated["missing"]).to eq("missing")
  end

  describe "insertion order" do
    it "follows Ruby Hash construction order" do
      pairs = [["a", 1], [:b, 2], [3, "three"], ["a", 4]]
      ruby_hash = {}
      pairs.each { |key, value| ruby_hash[key] = value }

      ordered_hash = described_class.new(pairs)

      expect(ordered_hash.to_a).to eq(ruby_hash.to_a)
      expect(ordered_hash.keys).to be_a(Hamster::Vector)
      expect(ordered_hash.keys.to_a).to eq(ruby_hash.keys)
      expect(ordered_hash.keys[1]).to eq(:b)
      expect(ordered_hash.values.to_a).to eq(ruby_hash.values)
      expect(ordered_hash.reverse_each.to_a).to eq(ruby_hash.to_a.reverse)
    end

    it "keeps an existing key in place when its value changes" do
      ordered_hash = described_class["a" => 1, "b" => 2, "c" => 3]

      changed = ordered_hash.put("b", 20)

      expect(changed.to_a).to eq([["a", 1], ["b", 20], ["c", 3]])
      expect(changed.key_at(1)).to eq("b")
      expect(changed.pair_at(1)).to eq(["b", 20])
      expect(changed.at(1)).to eq(["b", 20])
      expect(changed.reverse_each.to_a).to eq([["c", 3], ["b", 20], ["a", 1]])
    end

    it "moves a deleted key to the end when it is reinserted" do
      ordered_hash = described_class["a" => 1, "b" => 2, "c" => 3]

      result = ordered_hash.delete("b").put("b", 20)

      expect(result.to_a).to eq([["a", 1], ["c", 3], ["b", 20]])
      expect(result.key_at(-1)).to eq("b")
      expect(result.pair_at(-1)).to eq(["b", 20])
      expect(result.key_at(3)).to be_nil
      expect(result.pair_at(-4)).to be_nil
    end

    it "keeps merge duplicate keys at their receiver position" do
      receiver = described_class["a" => 1, "b" => 2, "c" => 3]
      other = described_class["b" => 20, "d" => 4, "a" => 10]

      replaced = receiver.merge(other)
      combined = receiver.merge(other) { |_key, old_value, new_value| old_value + new_value }

      expect(replaced.to_a).to eq([["a", 10], ["b", 20], ["c", 3], ["d", 4]])
      expect(combined.to_a).to eq([["a", 11], ["b", 22], ["c", 3], ["d", 4]])
    end

    it "preserves order through selection and slicing" do
      ordered_hash = described_class["a" => 1, "b" => 2, "c" => 3, "d" => 4]

      expect(ordered_hash.select { |_key, value| value.even? }.to_a).to eq([["b", 2], ["d", 4]])
      expect(ordered_hash.slice("d", "a", "z").to_a).to eq([["d", 4], ["a", 1]])
    end

    it "preserves independent forks with different changes" do
      base_pairs = (0...10).map { |number| ["k#{number}", number] }
      base = described_class.new(base_pairs)
      reference = {}
      base_pairs.each { |key, value| reference[key] = value }

      left = base.delete("k1").put("k1", 100).put("k10", 10)
      right = base.delete("k7").put("k2", 200).put("k11", 11)

      left_reference = reference.dup
      left_reference.delete("k1")
      left_reference["k1"] = 100
      left_reference["k10"] = 10

      right_reference = reference.dup
      right_reference.delete("k7")
      right_reference["k2"] = 200
      right_reference["k11"] = 11

      expect(left.to_a).to eq(left_reference.to_a)
      expect(right.to_a).to eq(right_reference.to_a)
      expect(left.to_a).not_to eq(right.to_a)
      expect((0...left.size).map { |index| left.key_at(index) }).to eq(left_reference.keys)
      expect((0...right.size).map { |index| right.pair_at(index) }).to eq(right_reference.to_a)
      expect(base.to_a).to eq(reference.to_a)
    end

    it "keeps positional access fast after many deletions and reinsertions" do
      ordered_hash = (0...200).reduce(described_class.empty) do |hash, number|
        hash.put(number, number)
      end

      changed = (0...200).reduce(ordered_hash) do |hash, number|
        hash = hash.delete(number) if number.even?
        hash.put(number, number * 10)
      end

      expected = {}
      (0...200).each { |number| expected[number] = number }
      (0...200).each do |number|
        expected.delete(number) if number.even?
        expected[number] = number * 10
      end

      expect(changed.to_a).to eq(expected.to_a)
      expect((0...changed.size).map { |index| changed.key_at(index) }).to eq(expected.keys)
    end

    it "supports keys with identical hash values that are not eql?" do
      first_key = CollisionKey.new(1)
      second_key = CollisionKey.new(2)
      ordered_hash = described_class[first_key => "one", second_key => "two"]

      expect(ordered_hash.to_a).to eq([[first_key, "one"], [second_key, "two"]])
      expect(ordered_hash[first_key]).to eq("one")
      expect(ordered_hash[second_key]).to eq("two")
      expect(ordered_hash.delete(first_key).to_a).to eq([[second_key, "two"]])
    end

    it "does not expose internal sequence numbers" do
      ordered_hash = described_class["a" => 1, "b" => 2]
      public_views = [
        ordered_hash.to_a,
        ordered_hash.to_hash.to_a,
        (0...ordered_hash.size).map { |index| ordered_hash.pair_at(index) }
      ]

      public_views.each do |view|
        expect(view).to eq([["a", 1], ["b", 2]])
      end
      expect(ordered_hash.reverse_each.to_a).to eq([["b", 2], ["a", 1]])
      expect(ordered_hash.inspect).to eq('Hamster::OrderedHash["a" => 1, "b" => 2]')
    end
  end

  class CollisionKey
    attr_reader :value

    def initialize(value)
      @value = value
    end

    def hash
      1
    end

    def eql?(other)
      other.is_a?(CollisionKey) && value == other.value
    end

    def inspect
      "CollisionKey(#{value})"
    end
  end
end
