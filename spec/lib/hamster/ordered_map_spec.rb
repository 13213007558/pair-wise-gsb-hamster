require "spec_helper"
require "hamster/ordered_map"

describe Hamster::OrderedMap do
  let(:map) { described_class[[[:a, 1], [:b, 2], [:c, 3]]] }

  it "is available as OrderedHash" do
    expect(Hamster::OrderedHash).to be(described_class)
  end

  describe "insertion order" do
    it "keeps the order used during construction" do
      expect(map.to_a).to eq([[:a, 1], [:b, 2], [:c, 3]])
      expect(map.keys.to_a).to eq([:a, :b, :c])
      expect(map.values.to_a).to eq([1, 2, 3])
    end

    it "does not move a key when overwritten" do
      result = map.put(:b, 20)

      expect(result.to_a).to eq([[:a, 1], [:b, 20], [:c, 3]])
      expect(result.instance_variable_get(:@order)).to equal(map.instance_variable_get(:@order))
    end

    it "appends a deleted key when it is inserted again" do
      result = map.delete(:b).put(:b, 20)

      expect(result.to_a).to eq([[:a, 1], [:c, 3], [:b, 20]])
    end

    it "can delete the final key and append it again" do
      result = map.delete(:c).put(:c, 30)

      expect(result.to_a).to eq([[:a, 1], [:b, 2], [:c, 30]])
    end

    it "enumerates backwards in insertion order" do
      pairs = []
      map.reverse_each { |key, value| pairs << [key, value] }

      expect(pairs).to eq([[:c, 3], [:b, 2], [:a, 1]])
    end

    it "preserves a stored nil value" do
      result = map.put(:b, nil)

      expect(result.fetch(:b, :default)).to be_nil
      expect(result.to_a).to eq([[:a, 1], [:b, nil], [:c, 3]])
    end

    it "freezes copied string keys" do
      key = "b"
      result = map.put(key, 20)
      key.upcase!

      expect(result.get("b")).to eq(20)
      expect(result.key?("B")).to be(false)
    end
  end

  describe "hash collisions" do
    it "allows keys with the same hash when they are not eql?" do
      first = DeterministicHash.new("a", 1)
      second = DeterministicHash.new("b", 1)
      result = described_class.empty.put(first, 1).put(second, 2)

      expect(result.get(DeterministicHash.new("a", 1))).to eq(1)
      expect(result.get(DeterministicHash.new("b", 1))).to eq(2)
      expect(result.to_a.map(&:first).map(&:value)).to eq(["a", "b"])
    end

    it "overwrites only the eql? key in a collision bucket" do
      first = DeterministicHash.new("a", 1)
      second = DeterministicHash.new("b", 1)
      result = described_class.empty.put(first, 1).put(second, 2)
      updated = result.put(DeterministicHash.new("a", 1), 10)

      expect(updated.to_a).to eq([[DeterministicHash.new("a", 1), 10], [DeterministicHash.new("b", 1), 2]])
    end
  end

  describe "persistence" do
    it "leaves the original map unchanged" do
      map.put(:b, 20)
      map.delete(:b)
      map.put(:d, 4)

      expect(map.to_a).to eq([[:a, 1], [:b, 2], [:c, 3]])
    end

    it "returns self when deleting a missing key" do
      expect(map.delete(:missing)).to be(map)
    end

    it "is immutable" do
      expect(map.immutable?).to be(true)
      expect(map.put(:d, 4).immutable?).to be(true)
      expect(map.delete(:a).immutable?).to be(true)
    end

    it "keeps old versions enumerable across interleaved branches and compaction" do
      left = described_class.empty
      right = described_class.empty

      1.upto(40) { |number| left = left.put(number, number) }
      before_compaction = left

      1.upto(15) { |number| left = left.delete(number) }
      before_threshold = left

      1.upto(40) { |number| right = right.put("r#{number}", number) }
      16.upto(31) { |number| left = left.delete(number) }
      right = 1.upto(31).reduce(right) { |branch, number| branch.delete("r#{number}") }

      compacted = left.delete(32)
      after_add = compacted.put(41, 41)
      right = right.put("r41", 41)

      expect(before_compaction.to_a).to eq((1..40).map { |number| [number, number] })
      expect(before_threshold.to_a).to eq((16..40).map { |number| [number, number] })
      expect(compacted.to_a).to eq((33..40).map { |number| [number, number] })
      expect(compacted.instance_variable_get(:@deleted)).to eq(0)
      expect(compacted.instance_variable_get(:@order).to_a).to eq((33..40).to_a)
      expect(after_add.to_a).to eq(((33..41).map { |number| [number, number] }))
      expect(right.to_a).to eq((32..41).map { |number| ["r#{number}", number] })
    end

    it "can delete live keys after compaction" do
      compacted = (1..40).reduce(described_class.empty) { |m, n| m.put(n, n) }
      compacted = 1.upto(32).reduce(compacted) { |m, n| m.delete(n) }

      expect(compacted.delete(33).put(41, 41).to_a).to eq((34..41).map { |number| [number, number] })
    end

    it "does not grow the order index on overwrite or delete" do
      result = map.put(:b, 20).delete(:a)

      expect(result.size).to eq(2)
      expect(result.instance_variable_get(:@order).size).to eq(3)
    end
  end

  describe "#merge" do
    it "keeps conflicting receiver keys in place and appends new keys in argument order" do
      other = described_class[[[:d, 4], [:b, 20], [:e, 5]]]

      expect(map.merge(other).to_a).to eq([[:a, 1], [:b, 20], [:c, 3], [:d, 4], [:e, 5]])
    end

    it "uses the block to resolve conflicts while retaining receiver position" do
      other = described_class[[[:b, 20], [:d, 4]]]
      result = map.merge(other) { |_key, old_value, new_value| old_value + new_value }

      expect(result.to_a).to eq([[:a, 1], [:b, 22], [:c, 3], [:d, 4]])
    end

    it "uses the first occurrence position for a repeated new key" do
      other = [[:d, 4], [:b, 20], [:d, 40]]

      expect(map.merge(other).to_a).to eq([[:a, 1], [:b, 20], [:c, 3], [:d, 40]])
    end

    it "accepts a Ruby Hash" do
      expect(map.merge(b: 20, d: 4).to_a).to eq([[:a, 1], [:b, 20], [:c, 3], [:d, 4]])
    end
  end

  describe "filtering" do
    it "passes key and value separately to select and reject blocks" do
      expect(map.select { |_key, value| value > 1 }.to_a).to eq([[:b, 2], [:c, 3]])
      expect(map.reject { |_key, value| value > 1 }.to_a).to eq([[:a, 1]])
    end

    it "removes nil values while preserving order" do
      expect(map.put(:b, nil).compact.to_a).to eq([[:a, 1], [:c, 3]])
    end
  end

  describe "comparison and conversion" do
    it "is eql? only when pair order matches" do
      reordered = described_class[[[:a, 1], [:c, 3], [:b, 2]]]

      expect(map.eql?(described_class[[[:a, 1], [:b, 2], [:c, 3]]])).to be(true)
      expect(map.eql?(reordered)).to be(false)
      expect(map == reordered).to be(true)
    end

    it "converts to an ordered Ruby Hash" do
      expect(map.to_hash).to eq(a: 1, b: 2, c: 3)
      expect(map.to_hash.to_a).to eq([[:a, 1], [:b, 2], [:c, 3]])
    end

    it "supports marshalling" do
      restored = Marshal.load(Marshal.dump(map))

      expect(restored).to eql(map)
      expect(restored.immutable?).to be(true)
    end
  end

  describe "default block" do
    it "calls the default block for a missing key" do
      map = described_class.new { |key| key.to_s.size }

      expect(map.get(:abc)).to eq(3)
      expect(map.put(:abc, 10).get(:abc)).to eq(10)
    end
  end
end
