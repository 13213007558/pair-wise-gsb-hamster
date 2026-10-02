require "hamster/hash"
require "hamster/vector"

module Hamster
  # An immutable zipper cursor over a tree made from Hamster::Hash and
  # Hamster::Vector. Each operation returns a new cursor.
  class Zipper
    # Raised for invalid cursor navigation or deletion.
    class ZipperError < StandardError; end

    # A direct parent node and the key or index used to reach the child.
    class Frame < Struct.new(:parent, :locator)
    end
    UNDEFINED = Object.new.freeze

    # Create a zipper rooted at `root`.
    def self.[](root)
      new(root)
    end

    def initialize(node, path = [])
      @node = node
      @path = path.dup.freeze
      freeze
    end

    # The current node. A stored nil is a real node and is returned as nil.
    attr_reader :node

    # Ancestor frames from the root to the current node's parent.
    attr_reader :path

    # The key or index used to reach the current node, or nil at the root.
    def locator
      root? ? nil : @path.last.locator
    end

    # Return true when the cursor is at the root.
    def root?
      @path.empty?
    end

    # Commit the cursor's path and return the rebuilt root.
    def root
      rebuild_nodes.first
    end
    alias_method :finish, :root

    # Move to a child. Hashes use keys and vectors use indexes.
    def down(locator = UNDEFINED)
      ensure_container!
      locator = first_locator if locator.equal?(UNDEFINED)
      if @node.is_a?(Hamster::Vector) && locator.is_a?(Integer) && locator < 0
        locator += @node.size
      end
      ensure_locator!(locator)
      self.class.new(child_at(@node, locator), @path + [frame(@node, locator)])
    end

    # Move to the parent. At root, return the cursor unchanged.
    def up
      return self if root?
      nodes = rebuild_nodes
      level = @path.size - 1
      parent = nodes[level]
      frames = level.times.map { |index| frame(nodes[index], @path[index].locator) }
      self.class.new(parent, frames)
    end

    # Move to the immediately preceding sibling.
    def left
      move_horizontal(-1)
    end
    alias_method :previous, :left
    alias_method :backward, :left

    # Move to the immediately following sibling.
    def right
      move_horizontal(1)
    end
    alias_method :next, :right
    alias_method :forward, :right

    # Replace the current node without moving the cursor.
    def replace(new_node)
      return self if new_node.equal?(@node)
      return self.class.new(new_node) if root?
      current_frame = @path.last
      parent = replace_child(current_frame.parent, current_frame.locator, new_node)
      self.class.new(new_node, @path[0...-1] + [frame(parent, current_frame.locator)])
    end
    alias_method :set, :replace

    # Remove the current node from its parent.
    def delete
      raise ZipperError, "cannot delete the root node" if root?

      nodes = rebuild_nodes
      level = @path.size - 1
      current_locator = @path[level].locator
      parent = nodes[level]
      old_position = locator_position(parent, current_locator)
      parent_without_node = remove_child(parent, current_locator)
      ancestors = level.times.map { |index| frame(nodes[index], @path[index].locator) }

      if parent_without_node.empty?
        return self.class.new(parent_without_node, ancestors)
      end

      new_position = old_position >= parent_without_node.size ? old_position - 1 : old_position
      new_locator = locator_at(parent_without_node, new_position)
      self.class.new(child_at(parent_without_node, new_locator), ancestors + [frame(parent_without_node, new_locator)])
    end

    private

    def frame(parent, locator)
      Frame.new(parent, locator).freeze
    end

    def container?(node)
      node.is_a?(Hamster::Hash) || node.is_a?(Hamster::Vector)
    end

    def ensure_container!
      unless container?(@node)
        raise ZipperError, "current node is not a Hamster::Hash or Hamster::Vector"
      end
    end

    def ensure_locator!(locator)
      case @node
      when Hamster::Hash
        raise ZipperError, "missing key" unless @node.key?(locator)
      when Hamster::Vector
        unless locator.is_a?(Integer) && locator >= 0 && locator < @node.size
          raise ZipperError, "index outside of vector bounds"
        end
      end
    end

    def first_locator
      raise ZipperError, "cannot descend into an empty node" if @node.empty?
      case @node
      when Hamster::Hash
        @node.each.first.first
      when Hamster::Vector
        0
      end
    end

    def locator_position(parent, locator)
      return locator if parent.is_a?(Hamster::Vector)

      parent.each_with_index do |(entry_locator, _), index|
        return index if entry_locator.eql?(locator)
      end
      raise ZipperError, "missing locator"
    end

    def locator_at(parent, position)
      case parent
      when Hamster::Hash
        parent.each_with_index do |(entry_locator, _), index|
          return entry_locator if index == position
        end
      when Hamster::Vector
        return position if position >= 0 && position < parent.size
      end
      raise ZipperError, "no sibling at that position"
    end

    def child_at(parent, locator)
      parent.get(locator)
    end

    def replace_child(parent, locator, child)
      parent.put(locator, child)
    end

    def remove_child(parent, locator)
      case parent
      when Hamster::Hash
        parent.delete(locator)
      when Hamster::Vector
        parent.delete_at(locator)
      end
    end

    def move_horizontal(distance)
      raise ZipperError, "root has no siblings" if root?

      nodes = rebuild_nodes
      level = @path.size - 1
      current_locator = @path[level].locator
      parent = nodes[level]
      position = locator_position(parent, current_locator) + distance
      raise ZipperError, "no sibling at that position" if position < 0 || position >= parent.size

      ancestors = level.times.map { |index| frame(nodes[index], @path[index].locator) }
      new_locator = locator_at(parent, position)
      self.class.new(child_at(parent, new_locator), ancestors + [frame(parent, new_locator)])
    end

    def rebuild_nodes
      nodes = [@node]
      @path.reverse_each do |current_frame|
        nodes << replace_child(current_frame.parent, current_frame.locator, nodes.last)
      end
      nodes.reverse
    end
  end

  def self.zipper(root)
    Zipper.new(root)
  end
end
