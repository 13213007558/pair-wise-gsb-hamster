require "spec_helper"
require "hamster/multiset"

describe Hamster::Multiset do
  let(:left) { described_class["a", "a", "b"] }
  let(:right) { described_class["a", "b", "b"] }

  CollisionKey = Struct.new(:name) do
    CODES = { x: 1010, y: 1010 + (1 << 5), z: 1010 + (1 << 10) }

    def hash
      CODES.fetch(name)
    end
  end

  it "counts occurrences separately from distinct elements" do
    expect(left.distinct_size).to eq(2)
    expect(left.size).to eq(3)
    expect(left.total_count).to eq(3)
    expect(left.to_a.sort).to eq(%w[a a b])
  end

  it "adds multiplicities" do
    result = left.sum(right)
    expect(result.to_counts).to eq("a" => 3, "b" => 3)
    expect(result.distinct_size).to eq(2)
    expect(result.size).to eq(6)
    expect(left + right).to eql(result)
    expect(left.merge(right)).to eql(result)
  end

  it "takes the larger multiplicity for union" do
    result = left.union(right)
    expect(result.to_counts).to eq("a" => 2, "b" => 2)
    expect(left | right).to eql(result)
  end

  it "takes the smaller multiplicity for intersection" do
    result = left.intersection(right)
    expect(result.to_counts).to eq("a" => 1, "b" => 1)
    expect(result.distinct_size).to eq(2)
    expect(result.size).to eq(2)
    expect(left & right).to eql(result)
  end

  it "subtracts multiplicities and truncates at zero" do
    result = left.difference(right)
    expect(result.to_counts).to eq("a" => 1)
    expect(result.size).to eq(1)
    expect(left - right).to eql(result)
    expect(result.difference(left)).to equal(described_class.empty)
  end

  it "accepts Enumerable operands as occurrence lists" do
    expect((left + ["a", "b", "b"]).to_counts).to eq("a" => 3, "b" => 3)
    expect((left & ["a", "b", "b"]).to_counts).to eq("a" => 1, "b" => 1)
    expect((left - ["a", "a", "a"]).to_counts).to eq("b" => 1)
  end

  it "accepts explicit zero and positive multiplicities and rejects negative values" do
    from_counts = described_class.new("a" => 2, "b" => 0)
    expect(from_counts.to_counts).to eq("a" => 2)
    expect(from_counts.put("b", 0)).to eql(from_counts)
    expect { from_counts.put("b", -1) }.to raise_error(ArgumentError)
    expect { from_counts.add("b", -1) }.to raise_error(ArgumentError)
    expect { from_counts.delete("b", -1) }.to raise_error(ArgumentError)
  end

  it "builds explicit multiplicities from a list of pairs" do
    multiset = described_class.new([["a", 2], ["b", 3]])
    expect(multiset.to_counts).to eq("a" => 2, "b" => 3)
    expect(multiset.size).to eq(5)
    expect(multiset.distinct_size).to eq(2)
  end

  it "supports large multiplicities without dropping quantity" do
    large = 10 ** 100
    multiset = described_class.new("a" => large)
    expect((multiset + multiset).multiplicity("a")).to eq(large * 2)
    expect(multiset.union(described_class.new("a" => large - 1)).multiplicity("a")).to eq(large)
    expect(multiset.intersection(described_class.new("a" => large - 1)).multiplicity("a")).to eq(large - 1)
    expect(multiset.difference(described_class.new("a" => large - 1)).multiplicity("a")).to eq(1)
  end

  it "handles hash-colliding but unequal keys according to multiplicity" do
    x = CollisionKey.new(:x)
    y = CollisionKey.new(:y)
    z = CollisionKey.new(:z)
    a = described_class.new(x => 2, y => 3)
    b = described_class.new(x => 4, y => 1, z => 5)

    expect((a + b).to_counts).to eq(x => 6, y => 4, z => 5)
    expect(a.union(b).to_counts).to eq(x => 4, y => 3, z => 5)
    expect(a.intersection(b).to_counts).to eq(x => 2, y => 1)
    expect(a.difference(b).to_counts).to eq(y => 2)
  end

  it "preserves existing multisets through operations" do
    left + right
    left.union(right)
    left.intersection(right)
    left.difference(right)
    left.add("c", 2)
    left.put("a", 5)
    left.delete("a", 1)

    expect(left.to_counts).to eq("a" => 2, "b" => 1)
    expect(right.to_counts).to eq("a" => 1, "b" => 2)
    expect(left).to be_frozen
  end

  it "reuses unchanged trie branches when adding into another branch" do
    left_multiset = described_class.new(0...500)
    left_trie = left_multiset.instance_variable_get(:@trie)
    changed_index = left_trie.send(:index_for, 1)
    unchanged_index = left_trie.instance_variable_get(:@children).each_index.find do |index|
      child = left_trie.instance_variable_get(:@children)[index]
      child && index != changed_index
    end

    result = left_multiset + described_class[1]
    result_trie = result.instance_variable_get(:@trie)

    expect(result_trie.instance_variable_get(:@children)[unchanged_index]).to equal(
      left_trie.instance_variable_get(:@children)[unchanged_index]
    )
  end

  it "reuses an unchanged collided branch when subtraction removes no key" do
    x = CollisionKey.new(:x)
    y = CollisionKey.new(:y)
    z = CollisionKey.new(:z)
    left = described_class.new(x => 2, y => 3)
    right = described_class.new(z => 1)

    expect(left.difference(right)).to equal(left)
  end

  it "compares by type and complete multiplicities" do
    expect(left).to eql(described_class["b", "a", "a"])
    expect(left).not_to eql(right)
    expect(left.hash).to eq(described_class["b", "a", "a"].hash)
  end
end
