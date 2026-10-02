require "spec_helper"
require "hamster/multiset"

describe Hamster::Multiset do
  let(:multiset_class) { described_class }

  describe ".new and .[]" do
    it "counts repeated items" do
      multiset = described_class[:a, :a, :b]

      expect(multiset.distinct_size).to eq(2)
      expect(multiset.size).to eq(3)
      expect(multiset.multiplicity(:a)).to eq(2)
      expect(multiset.multiplicity(:b)).to eq(1)
      expect(multiset.multiplicity(:c)).to eq(0)
    end

    it "accepts explicit item and multiplicity pairs" do
      multiset = described_class.new([[:a, 2], [:b, 1]])

      expect(multiset).to eql(described_class[:a, :a, :b])
    end

    it "accepts a hash of items and multiplicities" do
      multiset = described_class.new(a: 2, b: 1)

      expect(multiset.multiplicity(:a)).to eq(2)
      expect(multiset.multiplicity(:b)).to eq(1)
    end

    it "allows [] to contain an array item" do
      expect(described_class[[:a, 2]]).to eql(described_class.new([[[:a, 2], 1]]))
    end

    it "does not store zero multiplicities" do
      multiset = described_class.new([[:a, 0], [:b, 2]])
      trie = multiset.instance_variable_get(:@trie)

      expect(multiset.size).to eq(2)
      expect(multiset.distinct_size).to eq(1)
      expect(multiset.include?(:a)).to eq(false)
      expect(trie.size).to eq(1)
    end

    it "rejects negative multiplicities" do
      expect { described_class.new([[:a, -1]]) }.to raise_error(ArgumentError)
      expect { described_class[:a].add(:b, -1) }.to raise_error(ArgumentError)
      expect { described_class[:a].put(:b, -1) }.to raise_error(ArgumentError)
    end
  end

  describe "iteration" do
    it "yields each occurrence from #each" do
      multiset = described_class[:a, :a, :b]

      expect(multiset.to_a.sort_by(&:to_s)).to eq([:a, :a, :b])
      expect(multiset.each_with_multiplicity.to_a).to contain_exactly([:a, 2], [:b, 1])
    end

    it "preserves multiplicity in select" do
      multiset = described_class.new(a: 3, b: 1)

      expect(multiset.select { |item| item == :a }).to eql(described_class.new(a: 3))
    end
  end

  describe "multiset operations" do
    let(:left) { described_class[:a, :a, :b] }
    let(:right) { described_class[:a, :b, :b] }

    it "adds multiplicities" do
      result = left + right

      expect(result).to eql(described_class.new(a: 3, b: 3))
      expect(result.size).to eq(6)
      expect(result.distinct_size).to eq(2)
      expect(left).to eql(described_class[:a, :a, :b])
      expect(right).to eql(described_class[:a, :b, :b])
    end

    it "takes the maximum multiplicity in a union" do
      expect(left.union(right)).to eql(described_class.new(a: 2, b: 2))
    end

    it "takes the minimum multiplicity in an intersection" do
      expect(left.intersection(right)).to eql(described_class.new(a: 1, b: 1))
    end

    it "truncates subtraction to zero in a difference" do
      expect(left.difference(right)).to eql(described_class.new(a: 1))
      expect(right.difference(left)).to eql(described_class.new(b: 1))
    end

    it "accepts an enumerable on the right" do
      expect(left + [:a, :b, :b]).to eql(described_class.new(a: 3, b: 3))
      expect(left | [:a, :b, :b]).to eql(described_class.new(a: 2, b: 2))
      expect(left & [:a, :b, :b]).to eql(described_class.new(a: 1, b: 1))
      expect(left - [:a, :b, :b]).to eql(described_class.new(a: 1))
    end

    it "returns self when an operation cannot change the multiset" do
      expect(left.union(described_class.new(a: 1))).to be(left)
      expect(left.intersection(described_class.new(a: 2, b: 1))).to be(left)
      expect(left.difference(described_class.new(c: 4))).to be(left)
      expect(left + described_class.empty).to be(left)
    end

    it "handles large multiplicities as integers" do
      large = 2 ** 128
      result = described_class.new(a: large) + described_class.new(a: large)

      expect(result.multiplicity(:a)).to eq(2 * large)
      expect((result - described_class.new(a: large)).multiplicity(:a)).to eq(large)
    end

    it "handles hash-colliding keys separately" do
      left_key = DeterministicHash.new("left", 1)
      right_key = DeterministicHash.new("right", 33)
      left = described_class.new(left_key => 2, right_key => 1)
      right = described_class.new(left_key => 3, right_key => 5)

      expect((left + right).multiplicity(left_key)).to eq(5)
      expect((left + right).multiplicity(right_key)).to eq(6)
      expect(left.union(right).multiplicity(left_key)).to eq(3)
      expect(left.union(right).multiplicity(right_key)).to eq(5)
      expect(left.intersection(right).multiplicity(left_key)).to eq(2)
      expect(left.intersection(right).multiplicity(right_key)).to eq(1)
      expect(right.difference(left).multiplicity(left_key)).to eq(1)
      expect(right.difference(left).multiplicity(right_key)).to eq(4)
    end

    it "reuses unchanged branches through hash collisions" do
      left_key = DeterministicHash.new("left", 1)
      right_key = DeterministicHash.new("right", 33)
      left = described_class[left_key]
      right = described_class[left_key, right_key]

      result = left + right
      right_trie = right.instance_variable_get(:@trie)
      result_trie = result.instance_variable_get(:@trie)
      shared_branch = right_trie.instance_variable_get(:@children)[1]
      combined_branch = result_trie.instance_variable_get(:@children)[1]

      expect(shared_branch).not_to be_nil
      expect(combined_branch.instance_variable_get(:@entries)[1]).to equal(
        shared_branch.instance_variable_get(:@entries)[1]
      )
    end
  end

  describe "single-item updates" do
    it "adds, removes, replaces, and deletes multiplicities immutably" do
      multiset = described_class.new(a: 2)

      expect(multiset.add(:a, 2).multiplicity(:a)).to eq(4)
      expect(multiset.remove(:a, 5).multiplicity(:a)).to eq(0)
      expect(multiset.remove(:a, 5).include?(:a)).to eq(false)
      expect(multiset.put(:a, 1).multiplicity(:a)).to eq(1)
      expect(multiset.put(:a, 0).include?(:a)).to eq(false)
      expect(multiset.delete(:a)).to eql(described_class.empty)
      expect(multiset).to eql(described_class.new(a: 2))
    end
  end

  describe "equality and hashing" do
    it "is equal regardless of unordered construction" do
      expect(described_class[:a, :a, :b]).to eql(described_class[:b, :a, :a])
      expect(described_class[:a, :a, :b].hash).to eq(described_class[:b, :a, :a].hash)
    end

    it "is not equal when multiplicities differ" do
      expect(described_class[:a, :a]).not_to eql(described_class[:a])
    end
  end

  describe "aliases" do
    it "provides alternative class and method names" do
      expect(Hamster::MultiSet).to be(described_class)
      expect(Hamster::Bag).to be(described_class)
      expect(described_class[:a].element_count).to eq(1)
      expect(described_class[:a].unique_size).to eq(1)
    end
  end
end
