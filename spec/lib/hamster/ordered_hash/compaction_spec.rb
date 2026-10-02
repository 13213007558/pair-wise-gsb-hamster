require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  def slots_of(ordered)
    ordered.instance_variable_get(:@slots)
  end

  def holes_of(ordered)
    ordered.instance_variable_get(:@holes)
  end

  describe "slot vector bookkeeping" do
    it "appends exactly one slot per new key, without rebuilding existing slots" do
      ordered = OH.empty
      10.times { |i| ordered = ordered.put("key#{i}", i) }
      expect(slots_of(ordered).size).to eq(10)

      grown = ordered.put("key10", 10)
      expect(slots_of(grown).size).to eq(11)
    end

    it "updates an existing key in place, reusing the key-to-slot index" do
      ordered = OH["A" => 1, "B" => 2, "C" => 3]
      updated = ordered.put("B", 22)
      expect(slots_of(updated).size).to eq(3)
      expect(updated.instance_variable_get(:@hash))
        .to be(ordered.instance_variable_get(:@hash))
    end

    it "leaves a tombstone instead of rebuilding the slot vector on delete" do
      ordered = OH["A" => 1, "B" => 2, "C" => 3, "D" => 4, "E" => 5]
      deleted = ordered.delete("C")
      expect(slots_of(deleted).size).to eq(5)
      expect(holes_of(deleted)).to eq(1)
      expect(deleted.keys).to eq(["A", "B", "D", "E"])
    end

    it "compacts once tombstones outnumber live entries" do
      ordered = OH["A" => 1, "B" => 2, "C" => 3, "D" => 4]
      compacted = ordered.delete("A").delete("B").delete("C")
      expect(compacted.keys).to eq(["D"])
      expect(slots_of(compacted).size).to eq(1)
      expect(holes_of(compacted)).to eq(0)
    end

    it "compacts away all slots when the last key is removed" do
      ordered = OH["A" => 1, "B" => 2]
      emptied = ordered.delete("A").delete("B")
      expect(emptied).to be_empty
      expect(slots_of(emptied).size).to eq(0)
    end

    it "keeps the slot vector bounded by twice the live size" do
      ordered = OH.empty
      50.times { |i| ordered = ordered.put("key#{i}", i) }
      49.times do |i|
        ordered = ordered.delete("key#{i}")
        expect(slots_of(ordered).size).to be <= 2 * [ordered.size, 1].max
        expect(holes_of(ordered)).to be <= ordered.size
      end
    end
  end

  describe "with many retained versions across interleaved updates and compaction" do
    it "enumerates every historical version correctly" do
      versions = []
      current = OH.empty
      expected_keys = []
      expected_values = {}
      rng = Random.new(1234)
      keys = (1..30).map { |i| "key#{i}" }

      300.times do
        if expected_keys.empty? || rng.rand < 0.55
          key = keys[rng.rand(keys.size)]
          value = rng.rand(1000)
          current = current.put(key, value)
          expected_values[key] = value
          expected_keys << key unless expected_keys.include?(key)
        else
          key = expected_keys[rng.rand(expected_keys.size)]
          current = current.delete(key)
          expected_keys.delete(key)
          expected_values.delete(key)
        end
        versions << [current, expected_keys.dup, expected_values.dup]
      end

      # Compaction really did happen: far more pairs were put than the
      # final slot vector holds, and deletes alone never shrink it.
      expect(slots_of(current).size).to be < 100

      versions.each do |version, keys, values|
        expect(version.keys).to eq(keys)
        expect(version.to_a).to eq(keys.map { |key| [key, values[key]] })
        expect(version.size).to eq(keys.size)
        expect(holes_of(version)).to be <= version.size
        expect(slots_of(version).size).to eq(version.size + holes_of(version))
      end
    end

    it "keeps pre-compaction versions intact after later versions compact" do
      v1 = OH["A" => 1, "B" => 2, "C" => 3, "D" => 4]
      v2 = v1.delete("A")
      v3 = v2.delete("B")
      v4 = v3.delete("C") # triggers compaction in v4
      v5 = v4.put("E", 5).put("F", 6)

      expect(holes_of(v4)).to eq(0)
      expect(v1.to_a).to eq([["A", 1], ["B", 2], ["C", 3], ["D", 4]])
      expect(v2.to_a).to eq([["B", 2], ["C", 3], ["D", 4]])
      expect(v3.to_a).to eq([["C", 3], ["D", 4]])
      expect(v4.to_a).to eq([["D", 4]])
      expect(v5.to_a).to eq([["D", 4], ["E", 5], ["F", 6]])
    end
  end
end
