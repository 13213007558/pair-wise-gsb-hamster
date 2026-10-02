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

  describe "#split_at" do
    it "splits an empty vector into two empty vectors" do
      left, right = V.empty.split_at(0)
      expect(left).to eql(V.empty)
      expect(right).to eql(V.empty)
    end

    it "returns [empty, self] when splitting at 0" do
      vector = V.new(1..100)
      left, right = vector.split_at(0)
      expect(left).to eql(V.empty)
      expect(right).to eql(vector)
    end

    it "returns [self, empty] when splitting at the size" do
      vector = V.new(1..100)
      left, right = vector.split_at(100)
      expect(left).to eql(vector)
      expect(right).to eql(V.empty)
    end

    it "clamps indexes beyond the size" do
      vector = V.new(1..100)
      left, right = vector.split_at(200)
      expect(left).to eql(vector)
      expect(right).to eql(V.empty)
    end

    it "counts negative indexes back from the end" do
      left, right = V.new((0...100).to_a).split_at(-10)
      expect(left).to eql(V.new((0...90).to_a))
      expect(right).to eql(V.new((90...100).to_a))
    end

    it "raises IndexError when the negative index is out of range" do
      expect { V[1, 2].split_at(-3) }.to raise_error(IndexError)
    end

    [1, 2, 31, 32, 33, 100, 1023, 1024, 1025, 2000].each do |size|
      it "splits a #{size}-item vector like an Array" do
        array = (0...size).to_a
        vector = V.new(array)
        [0, 1, size / 2, size - 1, size].uniq.each do |index|
          left, right = vector.split_at(index)
          expect(left.to_a).to eq(array[0...index])
          expect(right.to_a).to eq(array[index..-1] || [])
          expect(left.size).to eq(index)
          expect(right.size).to eq(size - index)
        end
      end
    end

    it "supports element access and slicing on both halves" do
      left, right = V.new((0...1000).to_a).split_at(333)
      333.times { |i| expect(left[i]).to eq(i) }
      667.times { |i| expect(right[i]).to eq(333 + i) }
      expect(left[-1]).to eq(332)
      expect(right[-1]).to eq(999)
      expect(left[100, 50]).to eql(V.new(100...150))
      expect(right[100, 50]).to eql(V.new(433...483))
      expect(right[0..9]).to eql(V.new(333...343))
    end

    it "only copies the nodes along the splitting boundary" do
      vector = V.new((0...2048).to_a)
      vector_ids = node_ids(vector)
      left, right = vector.split_at(1000)
      result_ids = node_ids(left) + node_ids(right)
      new_nodes = result_ids - vector_ids
      shared_nodes = result_ids & vector_ids
      expect(new_nodes.size).to be <= 3 * (vector.instance_variable_get(:@levels) + 1)
      expect(shared_nodes.size).to be >= vector_ids.size - 10
    end

    it "shares complete internal blocks with the original vector" do
      vector = V.new((0...1024).to_a)
      left, right = vector.split_at(512)
      shared = (node_ids(left) + node_ids(right)) & node_ids(vector)
      expect(shared.size).to be >= 30
    end

    it "does not modify the original vector or the other half when either half is updated" do
      vector = V.new((0...1000).to_a)
      left, right = vector.split_at(400)
      new_left = left.put(10, :x).add(:y)
      new_right = right.put(10, :z).unshift(:w)
      expect(vector.to_a).to eq((0...1000).to_a)
      expect(left.to_a).to eq((0...400).to_a)
      expect(right.to_a).to eq((400...1000).to_a)
      expect(new_left[10]).to eq(:x)
      expect(new_left.last).to eq(:y)
      expect(new_right[11]).to eq(:z)
      expect(new_right.first).to eq(:w)
    end

    it "produces halves which can be split and concatenated again" do
      vector = V.new((0...2048).to_a)
      left, right = vector.split_at(1000)
      mid_left, mid_right = right.split_at(500)
      expect(mid_left.to_a).to eq((1000...1500).to_a)
      expect(mid_right.to_a).to eq((1500...2048).to_a)
      rejoined = V.concat_many([left, mid_left, mid_right])
      expect(rejoined).to eql(vector)
      expect(rejoined.to_a).to eq((0...2048).to_a)
    end

    it "keeps working after splitting a concatenated vector" do
      vector = V.concat_many([V.new(0...333), V.new(333...1200), V.new(1200...1500)])
      left, right = vector.split_at(700)
      expect(left.to_a).to eq((0...700).to_a)
      expect(right.to_a).to eq((700...1500).to_a)
      expect(left.put(0, :x)[0]).to eq(:x)
      expect(right.drop(650).to_a).to eq((1350...1500).to_a)
      expect(left.take(5).to_a).to eq([0, 1, 2, 3, 4])
    end
  end
end
