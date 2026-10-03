require "spec_helper"
require "hamster/prefix_map"

describe Hamster::PrefixMap do
  describe "node compression" do
    def node_and_label_counts(map)
      root = map.instance_variable_get(:@root)
      nodes = 0
      labels = 0
      stack = [root]
      until stack.empty?
        node = stack.pop
        nodes += 1
        node.children.each_value do |edge|
          labels += edge.label.length
          stack.push(edge.node)
        end
      end
      [nodes, labels]
    end

    it "stores a single long key in one compressed edge" do
      map = Hamster::PrefixMap["a" * 1000 => 1]
      nodes, labels = node_and_label_counts(map)
      expect(nodes).to eq(2)
      expect(labels).to eq(1000)
    end

    it "shares long common prefixes instead of repeating them per key" do
      common = "a" * 400
      map = Hamster::PrefixMap.empty
      200.times { |i| map = map.put(common + i.to_s, i) }
      nodes, labels = node_and_label_counts(map)
      total_codepoints = (0...200).sum { |i| (common + i.to_s).length }
      # 202 nodes: root, the shared-prefix node, and one node per key.
      # An uncompressed trie would need roughly one node per codepoint.
      expect(nodes).to eq(202)
      expect(labels).to eq(600)
      expect(labels).to be < total_codepoints / 50
      expect(map.size).to eq(200)
    end

    it "splits an edge only as far as the keys diverge" do
      map = Hamster::PrefixMap[("x" * 500) + "a" => 1].put(("x" * 500) + "b", 2)
      nodes, labels = node_and_label_counts(map)
      expect(nodes).to eq(4)
      expect(labels).to eq(502)
    end

    it "merges edges back together when deletes make a branch redundant" do
      map = Hamster::PrefixMap["abcdef" => 1, "abcxyz" => 2]
      expect(node_and_label_counts(map)[0]).to eq(4)
      result = map.delete("abcxyz")
      nodes, labels = node_and_label_counts(result)
      expect(nodes).to eq(2)
      expect(labels).to eq(6)
    end
  end
end
