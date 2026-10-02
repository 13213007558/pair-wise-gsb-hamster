require "spec_helper"
require "hamster/zipper"
require "hamster/nested"

describe Hamster::Zipper do
  let(:tree) do
    H[
      "a" => V[1, 2, 3],
      "b" => H["x" => 10, "y" => 20],
      "c" => nil,
    ]
  end

  describe ".new and #node" do
    it "positions the cursor on the root" do
      zipper = Hamster::Zipper.new(tree)
      expect(zipper.node).to equal(tree)
      expect(zipper.root?).to be(true)
      expect(zipper.root).to equal(tree)
    end

    it "accepts a leaf as root" do
      expect(Hamster::Zipper.new(42).replace(43).root).to eq(43)
    end
  end

  describe "#down" do
    it "descends into a hash by key" do
      zipper = Hamster::Zipper.new(tree).down("a")
      expect(zipper.node).to eql(V[1, 2, 3])
      expect(zipper.root?).to be(false)
    end

    it "descends into a vector by index" do
      expect(Hamster::Zipper.new(tree).down("a").down(2).node).to eq(3)
    end

    it "supports negative vector indices" do
      expect(Hamster::Zipper.new(tree).down("a").down(-1).node).to eq(3)
    end

    it "descends to a nil node like any other node" do
      zipper = Hamster::Zipper.new(tree).down("c")
      expect(zipper.node).to be_nil
      expect(zipper.replace(:found).root).to eql(tree.put("c", :found))
    end

    it "raises KeyError for a missing hash key" do
      expect { Hamster::Zipper.new(tree).down("nope") }.to raise_error(KeyError)
    end

    it "raises IndexError for an out-of-range vector index" do
      expect { Hamster::Zipper.new(tree).down("a").down(3) }.to raise_error(IndexError)
      expect { Hamster::Zipper.new(tree).down("a").down(-4) }.to raise_error(IndexError)
    end

    it "raises TypeError when descending into a leaf" do
      expect { Hamster::Zipper.new(tree).down("a").down(0).down(0) }.to raise_error(TypeError)
      expect { Hamster::Zipper.new(tree).down("c").down("x") }.to raise_error(TypeError)
    end
  end

  describe "#up" do
    it "returns nil at the root" do
      expect(Hamster::Zipper.new(tree).up).to be_nil
    end

    it "moves back to the parent" do
      zipper = Hamster::Zipper.new(tree).down("a").down(0).up
      expect(zipper.node).to eql(V[1, 2, 3])
      expect(zipper.up.node).to equal(tree)
    end

    it "reflects edits made below" do
      zipper = Hamster::Zipper.new(tree).down("a").down(0).replace(99).up
      expect(zipper.node).to eql(V[99, 2, 3])
      expect(zipper.up.node).to eql(tree.put("a", V[99, 2, 3]))
    end
  end

  describe "#left and #right" do
    it "move between vector siblings" do
      zipper = Hamster::Zipper.new(tree).down("a").down(0)
      expect(zipper.right.node).to eq(2)
      expect(zipper.right.right.node).to eq(3)
      expect(zipper.right.right.right).to be_nil
      expect(zipper.left).to be_nil
      expect(zipper.right.left.node).to eq(1)
    end

    it "move between hash siblings in enumeration order" do
      keys = tree.each_key.to_a
      zipper = Hamster::Zipper.new(tree).down(keys[0])
      expect(zipper.node).to eq(tree.get(keys[0]))
      expect(zipper.right.node).to eq(tree.get(keys[1]))
      expect(zipper.right.right.node).to eq(tree.get(keys[2]))
      expect(zipper.right.right.right).to be_nil
      expect(zipper.left).to be_nil
    end

    it "return nil at the root" do
      zipper = Hamster::Zipper.new(tree)
      expect(zipper.left).to be_nil
      expect(zipper.right).to be_nil
    end

    it "keep edits to the current node when moving sideways" do
      zipper = Hamster::Zipper.new(tree).down("a").down(0).replace(99).right
      expect(zipper.node).to eq(2)
      expect(zipper.root).to eql(H["a" => V[99, 2, 3], "b" => H["x" => 10, "y" => 20], "c" => nil])
    end

    it "keep edits when moving sideways in a hash" do
      keys = tree.each_key.to_a
      zipper = Hamster::Zipper.new(tree).down(keys[0]).replace(:edited).right
      expect(zipper.node).to eq(tree.get(keys[1]))
      expect(zipper.root.get(keys[0])).to eq(:edited)
      expect(zipper.root.get(keys[1])).to eql(tree.get(keys[1]))
    end

    it "move sideways from a nil node" do
      keys = tree.each_key.to_a
      index = keys.index("c")
      zipper = Hamster::Zipper.new(tree).down("c")
      expect(zipper.node).to be_nil
      if index.zero?
        expect(zipper.left).to be_nil
      else
        expect(zipper.left.node).to eql(tree.get(keys[index - 1]))
      end
      if index == keys.size - 1
        expect(zipper.right).to be_nil
      else
        expect(zipper.right.node).to eql(tree.get(keys[index + 1]))
      end
    end
  end

  describe "#replace and #update" do
    it "replace the root" do
      expect(Hamster::Zipper.new(tree).replace(:new).root).to eq(:new)
    end

    it "replace a deep node without changing the old root" do
      zipper = Hamster::Zipper.new(tree).down("b").down("x").replace(99)
      expect(zipper.root).to eql(H["a" => V[1, 2, 3], "b" => H["x" => 99, "y" => 20], "c" => nil])
      expect(tree).to eql(H["a" => V[1, 2, 3], "b" => H["x" => 10, "y" => 20], "c" => nil])
    end

    it "update applies a function to the current node" do
      zipper = Hamster::Zipper.new(tree).down("b").down("y").update { |n| n * 2 }
      expect(zipper.node).to eq(40)
      expect(zipper.root.get("b")).to eql(H["x" => 10, "y" => 40])
    end

    it "shares unmodified subtrees with the old tree" do
      new_root = Hamster::Zipper.new(tree).down("a").down(0).replace(99).root
      expect(new_root.get("b")).to equal(tree.get("b"))
      expect(new_root.get("c")).to be_nil
      expect(new_root.get("a").get(1)).to eq(2)
    end
  end

  describe "#remove" do
    it "lands on the parent with the node removed" do
      zipper = Hamster::Zipper.new(tree).down("b").down("x").remove
      expect(zipper.node).to eql(H["y" => 20])
      expect(zipper.root).to eql(H["a" => V[1, 2, 3], "b" => H["y" => 20], "c" => nil])
    end

    it "removes a vector element, shifting later elements" do
      zipper = Hamster::Zipper.new(tree).down("a").down(0).remove
      expect(zipper.node).to eql(V[2, 3])
      expect(zipper.root.get("a")).to eql(V[2, 3])
    end

    it "removes a nil node like any other node" do
      zipper = Hamster::Zipper.new(tree).down("c").remove
      expect(zipper.node).to eql(tree.delete("c"))
      expect(zipper.root.key?("c")).to be(false)
    end

    it "raises at the root" do
      expect { Hamster::Zipper.new(tree).remove }.to raise_error(RuntimeError)
    end
  end

  describe "with a subtree shared between two positions" do
    it "editing one position does not affect the other" do
      shared = V[1, 2, 3]
      root = H["a" => shared, "b" => shared]
      new_root = Hamster::Zipper.new(root).down("a").down(0).replace(99).root
      expect(new_root.get("a")).to eql(V[99, 2, 3])
      expect(new_root.get("b")).to equal(shared)
      expect(root.get("a")).to equal(shared)
      expect(root.get("b")).to equal(shared)
    end

    it "removing one position does not affect the other" do
      shared = H["k" => "v"]
      root = V[shared, shared]
      new_root = Hamster::Zipper.new(root).down(0).remove.root
      expect(new_root).to eql(V[shared])
      expect(new_root.get(0)).to equal(shared)
    end
  end

  describe "with forked zippers" do
    it "edits through one zipper do not affect another" do
      zipper = Hamster::Zipper.new(tree).down("b")
      forked = zipper.down("x")
      edited = forked.replace(99)
      expect(forked.node).to eq(10)
      expect(forked.root).to equal(tree)
      expect(zipper.root).to equal(tree)
      expect(edited.root.get("b")).to eql(H["x" => 99, "y" => 20])
    end
  end

  # A naive reference cursor: it keeps the whole tree plus the full path
  # from the root, and re-walks the path from the root for every operation.
  class NaiveCursor
    attr_reader :tree, :path

    def initialize(tree)
      @tree = tree
      @path = []
    end

    def node
      @path.reduce(@tree) { |node, key| node.get(key) }
    end

    def parent
      @path[0...-1].reduce(@tree) { |node, key| node.get(key) }
    end

    def down(key)
      @path << key
    end

    def up
      @path.pop
    end

    def left?
      sibling?(-1)
    end

    def right?
      sibling?(1)
    end

    def left
      move(-1)
    end

    def right
      move(1)
    end

    def replace(value)
      @tree = assoc_in(@tree, @path, value)
    end

    def remove
      @tree = dissoc_in(@tree, @path)
      @path.pop
    end

    private

    def sibling?(direction)
      return false if @path.empty?
      case parent_node = parent
      when Hamster::Vector
        index = @path[-1] + direction
        index >= 0 && index < parent_node.size
      when Hamster::Hash
        keys = parent_node.each_key.to_a
        position = keys.index(@path[-1]) + direction
        position >= 0 && position < keys.size
      end
    end

    def move(direction)
      case parent_node = parent
      when Hamster::Vector
        @path[-1] += direction
      when Hamster::Hash
        keys = parent_node.each_key.to_a
        @path[-1] = keys[keys.index(@path[-1]) + direction]
      end
    end

    def assoc_in(node, path, value)
      return value if path.empty?
      key = path[0]
      child = assoc_in(node.get(key), path[1..-1], value)
      node.is_a?(Hamster::Hash) ? node.put(key, child) : node.set(key, child)
    end

    def dissoc_in(node, path)
      key = path[0]
      if path.size == 1
        node.is_a?(Hamster::Hash) ? node.delete(key) : node.delete_at(key)
      else
        child = dissoc_in(node.get(key), path[1..-1])
        node.is_a?(Hamster::Hash) ? node.put(key, child) : node.set(key, child)
      end
    end
  end

  describe "random navigation and editing sequences" do
    def random_leaf(random)
      [nil, 0, 1, -7, "s", :sym, 3.5].sample(random: random)
    end

    def random_tree(random, depth)
      if depth <= 0 || random.rand(3) == 0
        random_leaf(random)
      elsif random.rand(8) == 0
        shared = random_tree(random, depth - 1)
        H["shared_a" => shared, "shared_b" => shared]
      elsif random.rand(2) == 0
        pairs = (0...random.rand(0..4)).map { |i| ["k#{i}", random_tree(random, depth - 1)] }
        Hamster::Hash[pairs]
      else
        Hamster::Vector.new((0...random.rand(0..4)).map { random_tree(random, depth - 1) })
      end
    end

    def random_value(random)
      random.rand(4) == 0 ? random_tree(random, 1) : random_leaf(random)
    end

    it "agrees with a naive path-based cursor, and never disturbs other versions" do
      100.times do |trial|
        random = Random.new(trial)
        tree = random_tree(random, 3)
        tree_snapshot = Hamster.to_ruby(tree)

        zipper = Hamster::Zipper.new(tree)
        model = NaiveCursor.new(tree)
        forked = nil
        forked_root_snapshot = nil
        forked_node_snapshot = nil

        40.times do |step|
          ops = []
          node = model.node
          if node.is_a?(Hamster::Hash) && !node.empty?
            3.times { ops << :down }
          elsif node.is_a?(Hamster::Vector) && !node.empty?
            3.times { ops << :down }
          end
          unless model.path.empty?
            ops += [:up, :up, :remove, :replace]
            ops << :left if model.left?
            ops << :right if model.right?
          end
          ops << :replace if model.path.empty?

          case ops.sample(random: random)
          when :down
            key = node.is_a?(Hamster::Hash) ? node.each_key.to_a.sample(random: random)
                                            : random.rand(node.size)
            zipper = zipper.down(key)
            model.down(key)
          when :up
            zipper = zipper.up
            model.up
          when :left
            zipper = zipper.left
            model.left
          when :right
            zipper = zipper.right
            model.right
          when :replace
            value = random_value(random)
            zipper = zipper.replace(value)
            model.replace(value)
          when :remove
            zipper = zipper.remove
            model.remove
          end

          expect(zipper.node).to eql(model.node),
            "node mismatch in trial #{trial}, step #{step}"
          expect(zipper.root).to eql(model.tree),
            "root mismatch in trial #{trial}, step #{step}"

          if forked.nil? && random.rand(10) == 0
            forked = zipper
            forked_root_snapshot = Hamster.to_ruby(zipper.root)
            forked_node_snapshot = Hamster.to_ruby(zipper.node)
          end
        end

        # The original root is untouched.
        expect(Hamster.to_ruby(tree)).to eq(tree_snapshot)

        # A zipper forked midway is untouched by later edits.
        if forked
          expect(Hamster.to_ruby(forked.root)).to eq(forked_root_snapshot)
          expect(Hamster.to_ruby(forked.node)).to eq(forked_node_snapshot)
        end
      end
    end
  end
end
