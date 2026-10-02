require "spec_helper"
require "hamster/vector"

describe Hamster::Vector do
  describe "structural concatenation and slicing" do
    it "keeps empty vectors, block boundaries and mixed heights correct" do
      empty = V.empty
      sizes = [0, 1, 31, 32, 33, 1023, 1024, 1025, 4096, 5000]

      sizes.product(sizes).each do |left_size, right_size|
        left = left_size == 0 ? empty : V.new(1..left_size)
        right = right_size == 0 ? empty : V.new((left_size + 1)..(left_size + right_size))
        result = left + right
        expected = (1..(left_size + right_size)).to_a

        expect(result.size).to eq(expected.size)
        expect(result.to_a).to eq(expected)
        expect(result.map(&:itself)).to eq(expected)
        expect(result.each.each_with_index.all? { |value, index| value == expected[index] }).to be(true)

        if expected.any?
          expect(result.get(0)).to eq(expected.first)
          expect(result.get(-1)).to eq(expected.last)
          middle = expected.size / 2
          expect(result.slice(middle, 1)).to eql(V[expected[middle]])
        end
      end

      expect(empty + V[1]).to eql(V[1])
      one = V[1]
      expect(one + empty).to be(one)
    end

    it "shares complete trie nodes when concatenating vectors" do
      left = V.new(1..32768)
      right = V.new(32769..65536)
      result = left + right
      root = result.instance_variable_get(:@root)
      left_leaf = left.instance_variable_get(:@root).first.first
      right_leaf = right.instance_variable_get(:@root).first.first
      result_leaves = []
      collect_leaves = lambda do |node|
        case node
        when Hamster::Vector::InternalNode then node.children.each { |child| collect_leaves.call(child) }
        when Hamster::Vector::CanonicalNode then collect_leaves.call(node.root)
        when Hamster::Vector::LeafNode then result_leaves << node.array
        when Array
          if node.first.is_a?(Array)
            node.each { |child| collect_leaves.call(child) }
          else
            result_leaves << node
          end
        end
      end
      collect_leaves.call(root)
      expect(root).to be_a(described_class::InternalNode)
      expect(root.height).to eq(3)
      expect(result_leaves).to include(left_leaf)
      expect(result_leaves).to include(right_leaf)
      expect(result.size).to eq(65536)
      expect(result.get(0)).to eq(1)
      expect(result.get(32767)).to eq(32768)
      expect(result.get(32768)).to eq(32769)
      expect(result.get(65535)).to eq(65536)
    end

    it "shares the complete canonical subtree for a block-aligned slice" do
      vector = V.new(1..10000)
      canonical_root = vector.instance_variable_get(:@root)
      result = vector.slice(1024, 1024)
      result_root = result.instance_variable_get(:@root)

      expect(result_root).to be_a(described_class::CanonicalNode)
      expect(result_root.root).to equal(canonical_root[1])
      expect(result.to_a).to eq((1025..2048).to_a)
    end

    it "does not visit unrelated leaves while slicing a small range from a long vector" do
      visited = []
      tracking_leaf = Class.new(Array) do
        define_method(:[]) do |index, *rest|
          visited << __id__ unless rest.any?
          super(index, *rest)
        end

        define_method(:each) do |&block|
          visited << __id__
          super(&block)
        end
      end

      leaves = Array.new(4096) do |index|
        tracking_leaf.new((index * 32 + 1...(index + 1) * 32 + 1).to_a).freeze
      end
      internals = leaves.each_slice(32).map { |children| Hamster::Vector::CanonicalNode.new(1, children, 1024) }
      h2_nodes = internals.each_slice(32).map { |children| children.map(&:root) }
      canonical = Hamster::Vector::CanonicalNode.new(3, h2_nodes, 131072)
      vector = described_class.alloc(canonical, 131072, 3)

      result = vector.slice(131070, 2)

      expect(visited).to be_empty
      expect(result.to_a).to eq([131071, 131072])
      expect(visited.uniq).to contain_exactly(leaves.last.__id__)
      expect(visited.size).to be <= 2
    end

    it "preserves both inputs after updating a concatenated vector" do
      left = V.new(1..100)
      right = V.new(101..200)
      combined = left + right
      updated = combined.put(50, :changed)
      appended = updated.add(201)

      expect(left.to_a).to eq((1..100).to_a)
      expect(right.to_a).to eq((101..200).to_a)
      expect(combined.to_a).to eq((1..200).to_a)
      expect(updated.get(50)).to eq(:changed)
      expect(updated.get(51)).to eq(52)
      expect(appended.get(200)).to eq(201)
      expect(left.get(50)).to eq(51)
    end

    it "preserves the source after updating a sliced vector" do
      vector = V.new(1..10000)
      fragment = vector.slice(1000, 10)
      updated = fragment.put(3, :changed)
      extended = updated + V[:tail]

      expect(fragment.to_a).to eq((1001..1010).to_a)
      expect(updated.to_a).to eq([1001, 1002, 1003, :changed, 1005, 1006, 1007, 1008, 1009, 1010])
      expect(extended.last).to eq(:tail)
      expect(vector.get(1003)).to eq(1004)
    end

    it "supports enumeration and updates through every slice boundary and range shape" do
      vector = V.new(1..5000)
      starts = [0, 1, 31, 32, 33, 1023, 1024, 1025, 4095, 4096, 4097]
      lengths = [0, 1, 2, 31, 32, 33, 63, 64, 65, 1023, 1024, 1025]

      starts.each do |start|
        lengths.each do |length|
          next if start + length > vector.size
          result = vector.slice(start, length)
          expected = (start + 1..start + length).to_a

          expect(result.size).to eq(length)
          expect(result.to_a).to eq(expected)
          expect(result.reverse_each.to_a).to eq(expected.reverse)
          expect(result.each.each_with_index.all? { |value, index| value == expected[index] }).to be(true)

          if length > 1
            updated = result.put(length / 2, :x)
            expect(updated.get(length / 2)).to eq(:x)
            expect(result.get(length / 2)).to eq(expected[length / 2])
            expect(vector.get(start + length / 2)).to eq(expected[length / 2])
          end
        end
      end
    end
  end
end
