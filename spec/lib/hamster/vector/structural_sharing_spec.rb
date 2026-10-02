require "spec_helper"
require "hamster/vector"

describe Hamster::Vector do
  # Collect the leaf node arrays of a vector's trie, bottom level only,
  # by walking @root directly. Used to prove structural sharing.
  def leaf_nodes_of(vector)
    root   = vector.instance_variable_get(:@root)
    levels = vector.instance_variable_get(:@levels)
    leaves = []
    walk = lambda do |node, level|
      if level == 0
        leaves << node
      else
        node.each { |child| walk.call(child, level - 1) }
      end
    end
    walk.call(root, levels)
    leaves
  end

  def shared_leaf_count(vector, other)
    mine   = leaf_nodes_of(vector).map(&:object_id)
    theirs = leaf_nodes_of(other).map(&:object_id)
    (mine & theirs).size
  end

  def count_allocations
    GC.start
    before = GC.stat[:total_allocated_objects]
    yield
    GC.stat[:total_allocated_objects] - before
  end

  describe "structural sharing concat" do
    [
      [32, 32],
      [32, 33],
      [1024, 1024],
      [1024, 31],
      [64, 5000],
      [32768, 32768],
      [1056, 40000],
      [32000, 1],
    ].each do |left_size, right_size|
      context "#{left_size} + #{right_size}" do
        let(:left)  { V.new(0...left_size) }
        let(:right) { V.new(left_size...(left_size + right_size)) }
        let(:combined) { left + right }

        it "concatenates the elements in order" do
          expect(combined.to_a).to eq((0...(left_size + right_size)).to_a)
        end

        it "is eql to a vector built from the elements" do
          expect(combined).to eql(V.new(0...(left_size + right_size)))
        end

        it "shares every leaf node of the right vector" do
          expect(shared_leaf_count(combined, right)).to eq(leaf_nodes_of(right).size)
        end

        it "shares every leaf node of the left vector" do
          expect(shared_leaf_count(combined, left)).to eq(leaf_nodes_of(left).size)
        end

        it "leaves both inputs unchanged when the result is modified" do
          combined.put(0, :a).put(combined.size - 1, :b).add(:c).pop
          expect(left.to_a).to eq((0...left_size).to_a)
          expect(right.to_a).to eq((left_size...(left_size + right_size)).to_a)
          expect(combined.to_a).to eq((0...(left_size + right_size)).to_a)
        end

        it "leaves the result unchanged when the inputs are modified" do
          left.put(0, :a)
          right.put(-1, :b)
          expect(combined.to_a).to eq((0...(left_size + right_size)).to_a)
        end

        it "supports indexing, enumeration and updates on the result" do
          expect(combined[0]).to eq(0)
          expect(combined[-1]).to eq(left_size + right_size - 1)
          expect(combined.map { |x| x }).to eq(combined.to_a)
          expect(combined.put(0, :x)[0]).to eq(:x)
          expect(combined.add(:x).size).to eq(left_size + right_size + 1)
        end
      end
    end

    it "concatenates across different tree heights without copying the right side" do
      left  = V.new(0...32)
      right = V.new(32...32800)
      combined = left + right
      expect(combined.to_a).to eq((0...32800).to_a)
      expect(shared_leaf_count(combined, right)).to eq(leaf_nodes_of(right).size)
    end

    it "handles empty vectors on either side" do
      expect((V.empty + V.empty).to_a).to eq([])
      expect((V.empty + V[1, 2, 3]).to_a).to eq([1, 2, 3])
      expect((V[1, 2, 3] + V.empty).to_a).to eq([1, 2, 3])
      big = V.new(0...5000)
      expect((V.empty + big).to_a).to eq(big.to_a)
      expect((big + V.empty).to_a).to eq(big.to_a)
    end

    it "still concatenates when the left vector is not block-aligned" do
      combined = V.new(0...33) + V.new(33...100)
      expect(combined.to_a).to eq((0...100).to_a)
      expect(combined).to eql(V.new(0...100))
    end

    it "allocates far fewer nodes than it has leaves when both vectors are large" do
      left  = V.new(0...100_000)
      right = V.new(100_000...200_000)
      allocated = count_allocations { left + right }
      # copying every element into fresh leaf nodes would allocate
      # thousands of arrays (one per 32 elements, plus a 100k element array)
      expect(allocated).to be < 1_000
    end
  end

  describe "structural sharing take/drop/slice" do
    let(:big) { V.new(0...100_000) }

    [
      [31, 32, 33],
      [1023, 1024, 1025],
      [32_767, 32_768, 32_769],
    ].each do |below, on, above|
      it "takes and drops across the #{on} block boundary" do
        vector = V.new(0...above)
        [below, on, above].each do |n|
          expect(vector.take(n).to_a).to eq((0...n).to_a)
          expect(vector.take(n)).to eql(V.new(0...n))
          expect(vector.drop(n).to_a).to eq((n...above).to_a)
          expect(vector.drop(n)).to eql(V.new(n...above))
        end
      end
    end

    it "takes and drops across tree levels" do
      expect(big.take(32_768).to_a).to eq((0...32_768).to_a)
      expect(big.take(32_768)).to eql(V.new(0...32_768))
      expect(big.drop(32_768).to_a).to eq((32_768...100_000).to_a)
      expect(big.drop(32_768)).to eql(V.new(32_768...100_000))
      expect(big.drop(1).to_a).to eq((1...100_000).to_a)
      expect(big.take(99_999).to_a).to eq((0...99_999).to_a)
    end

    it "shares leaf nodes when taking a block-aligned prefix" do
      taken = big.take(64_000)
      expect(shared_leaf_count(taken, big)).to eq(leaf_nodes_of(taken).size)
    end

    it "shares leaf nodes when dropping a block-aligned prefix" do
      dropped = big.drop(32_768)
      expect(shared_leaf_count(dropped, big)).to eq(leaf_nodes_of(dropped).size)
    end

    it "shares leaf nodes when slicing a block-aligned range" do
      sliced = big[1024, 2048]
      expect(sliced.to_a).to eq((1024...3072).to_a)
      expect(sliced).to eql(V.new(1024...3072))
      expect(shared_leaf_count(sliced, big)).to eq(leaf_nodes_of(sliced).size)
    end

    it "leaves the original unchanged when a taken/dropped/sliced vector is modified" do
      big.take(5000).put(0, :a).add(:b)
      big.drop(5000).put(0, :a).add(:b)
      big[1000, 2000].put(0, :a).add(:b)
      expect(big.to_a).to eq((0...100_000).to_a)
    end

    it "supports indexing, enumeration and updates on sliced vectors" do
      sliced = big[1000, 500]
      expect(sliced[0]).to eq(1000)
      expect(sliced[-1]).to eq(1499)
      expect(sliced.map { |x| x }).to eq((1000...1500).to_a)
      expect(sliced.put(0, :x)[0]).to eq(:x)
      expect(sliced.add(:x).size).to eq(501)
      expect(sliced.pop.size).to eq(499)
    end

    it "does not scan all elements for a small slice of a long vector" do
      vector = big
      allocated = count_allocations { vector[50_000, 10] }
      expect(vector[50_000, 10].to_a).to eq((50_000...50_010).to_a)
      # flattening the whole vector would allocate thousands of node arrays
      expect(allocated).to be < 200
    end

    it "does not scan all elements for a small misaligned slice of a long vector" do
      vector = big
      allocated = count_allocations { vector[50_001, 10] }
      expect(vector[50_001, 10].to_a).to eq((50_001...50_011).to_a)
      expect(allocated).to be < 200
    end

    it "does not scan all elements for a small take of a long vector" do
      vector = big
      allocated = count_allocations { vector.take(10) }
      expect(vector.take(10).to_a).to eq((0...10).to_a)
      expect(allocated).to be < 200
    end

    it "does not scan all elements for a small aligned drop from the end of a long vector" do
      vector = big
      allocated = count_allocations { vector.drop(99_968) }
      expect(vector.drop(99_968).to_a).to eq((99_968...100_000).to_a)
      expect(allocated).to be < 200
    end
  end
end
