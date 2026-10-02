require "spec_helper"
require "hamster/vector"

describe Hamster::Vector do
  def node_ids(vector)
    ids = []
    walk = lambda do |node, level|
      ids << node.object_id
      if level > 0
        children = node.is_a?(Hamster::Vector::RelaxedNode) ? node.children : node
        children.each { |child| walk.call(child, level - 1) }
      end
    end
    walk.call(vector.instance_variable_get(:@root), vector.instance_variable_get(:@levels))
    ids
  end

  describe ".concat_many" do
    it "returns an empty vector when given no vectors" do
      expect(V.concat_many).to eql(V.empty)
      expect(V.concat_many([])).to eql(V.empty)
    end

    it "accepts either splatted arguments or a single enumerable of vectors" do
      a, b = V.new(1..10), V.new(11..20)
      expect(V.concat_many(a, b)).to eql(V.new(1..20))
      expect(V.concat_many([a, b])).to eql(V.new(1..20))
    end

    it "converts array-like batches to vectors" do
      expect(V.concat_many(V[1, 2], [3, 4], V[5])).to eql(V[1, 2, 3, 4, 5])
    end

    it "handles empty vectors anywhere in the batch" do
      expect(V.concat_many(V.empty, V.empty)).to eql(V.empty)
      expect(V.concat_many(V.empty, V[1], V.empty, V[2], V.empty)).to eql(V[1, 2])
    end

    [0, 1, 31, 32, 33, 100, 1023, 1024, 1025].each do |size_a|
      [0, 1, 31, 32, 33, 100, 500].each do |size_b|
        it "concatenates #{size_a} items with #{size_b} items like Array#+" do
          array_a = (0...size_a).to_a
          array_b = (size_a...(size_a + size_b)).to_a
          result = V.concat_many([V.new(array_a), V.new(array_b)])
          expect(result.size).to eq(size_a + size_b)
          expect(result).to eql(V.new(array_a + array_b))
          expect(result.to_a).to eq(array_a + array_b)
        end
      end
    end

    it "concatenates vectors of very different heights" do
      big = V.new((0...5000).to_a)
      small = V[1, 2, 3]
      expect(V.concat_many([big, small]).to_a).to eq((0...5000).to_a + [1, 2, 3])
      expect(V.concat_many([small, big]).to_a).to eq([1, 2, 3] + (0...5000).to_a)
    end

    it "matches Array for a long chain of batches" do
      batches = 20.times.map { |i| (i * 10...i * 10 + (i % 7)).to_a }
      result = V.concat_many(batches.map { |b| V.new(b) })
      expect(result.to_a).to eq(batches.inject([], :+))
    end

    it "supports element access throughout the result" do
      result = V.concat_many([V.new(0...100), V.new(100...250), V.new(250...300)])
      300.times { |i| expect(result[i]).to eq(i) }
      expect(result[-1]).to eq(299)
      expect(result[100, 50]).to eql(V.new(100...150))
    end

    it "reuses complete internal blocks of the inputs" do
      a = V.new((0...1024).to_a)
      b = V.new((1024...2048).to_a)
      result = V.concat_many([a, b])
      expect(node_ids(a) - node_ids(result)).to eq([a.instance_variable_get(:@root).object_id])
      expect(node_ids(b) - node_ids(result)).to eq([b.instance_variable_get(:@root).object_id])
    end

    it "reuses complete blocks even when batch sizes are not block-aligned" do
      a = V.new((0...1000).to_a)
      b = V.new((1000...2500).to_a)
      result = V.concat_many([a, b])
      expect((node_ids(a) & node_ids(result)).size).to be >= 30
      expect((node_ids(b) & node_ids(result)).size).to be >= 45
    end

    it "does not modify the input vectors when the result is updated" do
      a = V.new((0...500).to_a)
      b = V.new((500...1000).to_a)
      result = V.concat_many([a, b])
      updated = result.put(700, :x).add(1000).put(0, :y)
      expect(a.to_a).to eq((0...500).to_a)
      expect(b.to_a).to eq((500...1000).to_a)
      expect(result.to_a).to eq((0...1000).to_a)
      expect(updated[700]).to eq(:x)
      expect(updated[0]).to eq(:y)
      expect(updated.size).to eq(1001)
    end

    it "keeps trie depth logarithmic when concatenating many small batches" do
      vector = V.empty
      500.times { |i| vector = V.concat_many([vector, V.new((i * 7...(i + 1) * 7).to_a)]) }
      expect(vector.to_a).to eq((0...3500).to_a)
      expect(vector.instance_variable_get(:@levels)).to be <= 4
    end

    it "keeps trie depth logarithmic when concatenating single items" do
      vector = V.empty
      300.times { |i| vector = V.concat_many([vector, V[i]]) }
      expect(vector.to_a).to eq((0...300).to_a)
      expect(vector.instance_variable_get(:@levels)).to be <= 3
    end

    it "returns a vector of the same class when called on a subclass" do
      subclass = Class.new(Hamster::Vector)
      expect(subclass.concat_many([V[1], V[2]])).to be_a(subclass)
    end
  end

  describe "#concat_many" do
    it "concatenates the arguments onto this vector" do
      expect(V[1, 2].concat_many([3, 4], V[5])).to eql(V[1, 2, 3, 4, 5])
    end

    it "returns a vector equal to self when there is nothing to concatenate" do
      vector = V.new(1..100)
      expect(vector.concat_many).to eql(vector)
      expect(vector.concat_many(V.empty)).to eql(vector)
    end
  end
end
