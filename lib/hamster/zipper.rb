require "hamster/hash"
require "hamster/vector"
require "hamster/list"

module Hamster
  # A `Zipper` is a cursor into a tree made of {Hamster::Hash} and
  # {Hamster::Vector} nodes. It allows navigating the tree (down, up, and
  # sideways to adjacent elements) and editing the node at the cursor
  # (replace or remove), without re-walking a path from the root for every
  # operation. At any point, {#root} returns the root of the edited tree.
  #
  # A zipper is an immutable value: every navigation or editing operation
  # returns a new `Zipper`, and previously obtained zippers (and the
  # original root) are never affected. Each zipper only carries the context
  # of its own ancestors, so unmodified subtrees keep being shared between
  # the old and the new tree. If the same (sub)object appears at several
  # positions in the tree, editing it through one position never affects
  # the other positions.
  #
  # In a {Hamster::Hash}, children are located by key; in a
  # {Hamster::Vector}, by (zero-based) index. A `nil` stored in a `Hash` or
  # `Vector` is a regular node: it can be navigated to, replaced, and
  # removed like any other node.
  #
  # Removing a node moves the cursor to its parent (with the node removed
  # from it). The root cannot be removed.
  #
  # @example
  #   zipper = Hamster::Zipper.new(Hamster::Hash["a" => Hamster::Vector[1, 2, 3]])
  #   zipper.down("a").down(0).replace(99).root
  #   # => Hamster::Hash["a" => Hamster::Vector[99, 2, 3]]
  #
  class Zipper
    # Context of a node located by key in a {Hamster::Hash}.
    #
    # @api private
    class HashContext
      attr_reader :parent, :key

      def initialize(parent, key)
        @parent = parent
        @key = key
        freeze
      end

      def assoc(child)
        @parent.put(@key, child)
      end

      def dissoc
        @parent.delete(@key)
      end
    end

    # Context of a node located by index in a {Hamster::Vector}.
    #
    # @api private
    class VectorContext
      attr_reader :parent, :index

      def initialize(parent, index)
        @parent = parent
        @index = index
        freeze
      end

      def assoc(child)
        @parent.set(@index, child)
      end

      def dissoc
        @parent.delete_at(@index)
      end
    end

    # The node the cursor is currently on.
    attr_reader :node

    # Return a new `Zipper` positioned on the root of `tree`.
    #
    # @param tree [Hash, Vector, Object] the root of the tree
    def initialize(tree)
      @node = tree
      @path = EmptyList
    end

    # True if the cursor is on the root of the tree.
    def root?
      @path.empty?
    end

    # Move the cursor down to a child of the current node. If the current
    # node is a {Hamster::Hash}, `key` is the key of the child; if it is a
    # {Hamster::Vector}, `key` is the (zero-based) index of the child. A
    # negative index counts from the end of the vector.
    #
    # @param key [Object] key or index of the child to descend to
    # @return [Zipper]
    # @raise [KeyError] if the current node is a `Hash` without `key`
    # @raise [IndexError] if the current node is a `Vector` and the index
    #   is out of range
    # @raise [TypeError] if the current node is not a `Hash` or `Vector`
    def down(key)
      case node = @node
      when Hamster::Hash
        raise KeyError, "key not found: #{key.inspect}" unless node.key?(key)
        self.class.send(:new_at, node.get(key), @path.cons(HashContext.new(node, key)))
      when Hamster::Vector
        unless Integer === key
          raise TypeError, "vector index must be an Integer, got #{key.inspect}"
        end
        index = key < 0 ? key + node.size : key
        raise IndexError, "index #{key} out of range" if index < 0 || index >= node.size
        self.class.send(:new_at, node.get(index), @path.cons(VectorContext.new(node, index)))
      else
        raise TypeError, "cannot descend into #{node.inspect}"
      end
    end

    # Move the cursor up to the parent of the current node, reflecting any
    # edit made to the current node. Return `nil` if the cursor is already
    # on the root.
    #
    # @return [Zipper, nil]
    def up
      return nil if @path.empty?
      self.class.send(:new_at, @path.head.assoc(@node), @path.tail)
    end

    # Move the cursor to the previous sibling of the current node: the
    # previous index in a {Hamster::Vector}, or the previous key (in
    # enumeration order) in a {Hamster::Hash}. Any edit made to the current
    # node is kept. Return `nil` if there is no previous sibling or if the
    # cursor is on the root.
    #
    # @return [Zipper, nil]
    def left
      move_sideways(-1)
    end

    # Move the cursor to the next sibling of the current node: the next
    # index in a {Hamster::Vector}, or the next key (in enumeration order)
    # in a {Hamster::Hash}. Any edit made to the current node is kept.
    # Return `nil` if there is no next sibling or if the cursor is on the
    # root.
    #
    # @return [Zipper, nil]
    def right
      move_sideways(1)
    end

    # Replace the current node with `new_node`, keeping the cursor at the
    # same position.
    #
    # @param new_node [Object]
    # @return [Zipper]
    def replace(new_node)
      self.class.send(:new_at, new_node, @path)
    end

    # Replace the current node with the result of yielding it to the
    # block, keeping the cursor at the same position.
    #
    # @yieldparam node [Object] the current node
    # @yieldreturn [Object] the new node
    # @return [Zipper]
    def update
      replace(yield(@node))
    end

    # Remove the current node from its parent. The cursor lands on the
    # parent, with the node removed from it.
    #
    # @return [Zipper]
    # @raise [RuntimeError] if the cursor is on the root
    def remove
      raise "cannot remove the root of a tree" if @path.empty?
      self.class.send(:new_at, @path.head.dissoc, @path.tail)
    end

    # The root of the (possibly edited) tree.
    #
    # @return [Hash, Vector, Object]
    def root
      node = @node
      @path.each { |context| node = context.assoc(node) }
      node
    end

    private

    def move_sideways(direction)
      return nil if @path.empty?
      context = @path.head
      case context
      when VectorContext
        index = context.index + direction
        return nil if index < 0 || index >= context.parent.size
        parent = context.parent.set(context.index, @node)
        self.class.send(:new_at, parent.get(index),
                        @path.tail.cons(VectorContext.new(parent, index)))
      when HashContext
        keys = context.parent.each_key.to_a
        position = keys.index(context.key) + direction
        return nil if position < 0 || position >= keys.size
        parent = context.parent.put(context.key, @node)
        key = keys[position]
        self.class.send(:new_at, parent.get(key),
                        @path.tail.cons(HashContext.new(parent, key)))
      end
    end

    # @api private
    def self.new_at(node, path)
      zipper = allocate
      zipper.send(:initialize_at, node, path)
      zipper
    end

    # @api private
    def initialize_at(node, path)
      @node = node
      @path = path
    end
  end
end
