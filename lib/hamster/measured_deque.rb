require "hamster/immutable"
require "hamster/undefined"

module Hamster

  # A {MeasuredDeque} is an immutable ordered collection whose elements each
  # contribute to a user-defined monoidal measurement. It supports insertion and
  # removal at both ends, concatenation, and logarithmic splitting at the first
  # prefix whose accumulated measurement satisfies a monotonic predicate.
  #
  # The measurement is described by:
  # - an identity value (for example `0` or `""`)
  # - an optional function which maps an element to its measurement
  # - an associative function which combines two measurements
  #
  # The combining function must not be assumed to be commutative. String
  # concatenation is therefore a valid way to verify that balancing preserves
  # left-to-right order.
  #
  # @example Locate a byte block containing an offset
  #   blocks = Hamster::MeasuredDeque.new(
  #     ["ab", "cdef", "g"],
  #     identity: 0,
  #     measure: :bytesize,
  #     combine: ->(left, right) { left + right }
  #   )
  #   prefix, remainder = blocks.span_measure { |size| size > 4 }
  #   remainder.first # => "cdef"
  class MeasuredDeque
    include Immutable
    DEFAULT_MEASURE = ->(item) { item }.freeze

    class << self
      def new(items = [], options = nil, identity: Undefined, measure: nil, combine: nil, &block)
        if options
          identity = options.fetch(:identity, Undefined)
          measure = options.key?(:measure) ? options[:measure] : measure
          combine = options[:combine] || combine
        end

        result = allocate
        if identity.equal?(Undefined)
          result.send(:initialize, items)
        else
          result.send(:initialize, items,
                      identity: identity,
                      measure: measure,
                      combine: combine,
                      &block)
        end
        result.immutable!
      end

      # Create a measured deque. The final hash configures the monoid:
      # `:identity` is required, `:measure` defaults to the element itself, and
      # `:combine` may be given as a proc or as the block.
      def [](*items, **options, &block)
        if options.empty?
          new(items, &block)
        else
          new(items, **options, &block)
        end
      end

      # Return an empty measured deque with the supplied monoid configuration.
      def empty(options = Undefined, &block)
        return new([], &block) if options.equal?(Undefined)
        new([], **options, &block)
      end

      # @private
      def alloc(root, identity, measure, combine)
        result = allocate
        result.instance_variable_set(:@root, root)
        result.instance_variable_set(:@identity, identity)
        result.instance_variable_set(:@measure, measure)
        result.instance_variable_set(:@combine, combine)
        result.freeze
      end
    end

    def initialize(items = [], identity: Undefined, measure: nil, combine: nil, &block)
      if identity.equal?(Undefined)
        raise ArgumentError, "MeasuredDeque requires an identity"
      end
      @identity = identity
      @combine = combine || block
      unless @combine.respond_to?(:call)
        raise ArgumentError, "MeasuredDeque requires a callable combine operation"
      end

      @measure = measure || DEFAULT_MEASURE
      unless @measure.respond_to?(:call) || @measure.is_a?(Symbol)
        raise TypeError, "measure must respond to #call or be a Symbol"
      end

      @root = build_tree(items.to_a)
    end

    # Return `true` if this deque contains no items.
    def empty?
      @root.nil?
    end

    # Return the number of items in this deque.
    def size
      @root ? @root.size : 0
    end
    alias :length :size

    # Return the combined measurement of every item, or the identity if empty.
    def measurement
      @root ? @root.measurement : @identity
    end
    alias :measure :measurement
    alias :total_measure :measurement

    # Return the first item, or `nil` when the deque is empty.
    def first
      Node.first_item(@root)
    end

    # Return the last item, or `nil` when the deque is empty.
    def last
      Node.last_item(@root)
    end

    # Return a new deque with `item` added at the end.
    def push(item)
      wrap(Node.join(@root, leaf(item), @combine))
    end
    alias :enqueue :push
    alias :<< :push

    # Return a new deque with the last item removed.
    def pop
      return wrap(nil) if empty?
      wrap(Node.remove_last(@root, @combine))
    end

    # Return a new deque with `item` added at the front.
    def unshift(item)
      wrap(Node.join(leaf(item), @root, @combine))
    end

    # Return a new deque with the first item removed.
    def shift
      return wrap(nil) if empty?
      wrap(Node.remove_first(@root, @combine))
    end
    alias :dequeue :shift

    # Return a new deque containing all items from this deque followed by all
    # items from `other`. Another measured deque must use the same measurement
    # configuration; a plain enumerable is measured with this deque's rules.
    def concat(other)
      if other.is_a?(MeasuredDeque)
        unless compatible?(other)
          raise ArgumentError, "cannot concatenate measured deques with different measurements"
        end
        return wrap(Node.join(@root, other.instance_variable_get(:@root), @combine))
      end

      wrap(Node.join(@root, build_tree(other.to_a), @combine))
    end
    alias :append :concat
    alias :+ :concat

    # Return an empty deque with the same measurement configuration.
    def clear
      wrap(nil)
    end

    # Split immediately before the first item whose inclusive prefix makes the
    # monotonic predicate return truthy.
    #
    # The predicate receives accumulated measurements in left-to-right order.
    # If it is true for the identity, the split is before every item. If it is
    # never true, the remainder is empty. An empty deque returns two empty
    # deques.
    def span_measure(predicate = nil, &block)
      predicate ||= block
      return [clear, clear] if empty?
      raise ArgumentError, "span_measure requires a predicate" unless predicate

      if predicate.call(@identity)
        return [clear, self]
      end

      left, right = split_node(@root, @identity, &predicate)
      [wrap(left), wrap(right)]
    end
    alias :split_measure :span_measure
    alias :span :span_measure
    alias :partition_measure :span_measure

    # Return the prefix from {#span_measure}.
    def take_while_measure(&block)
      span_measure(&block).first
    end

    # Return the remainder from {#span_measure}.
    def drop_while_measure(&block)
      span_measure(&block).last
    end

    # Split before the first item whose inclusive cumulative measurement is
    # greater than `measurement`. This is the common strict boundary used for
    # byte offsets: an exact boundary starts in the next item.
    def split_at_measure(measurement)
      span_measure(->(total) { total > measurement })
    end

    # Return the first item whose inclusive prefix makes the monotonic
    # predicate truthy. Return `nil` when the deque is empty or the predicate
    # is never satisfied.
    def find_measure(predicate = nil, &block)
      predicate ||= block
      return nil if empty? || !predicate
      return first if predicate.call(@identity)
      remainder = split_node(@root, @identity, &predicate).last
      Node.first_item(remainder)
    end

    # Yield every item in left-to-right order.
    def each
      return enum_for(:each) unless block_given?

      stack = [@root]
      until stack.empty?
        node = stack.pop
        next unless node
        if node.leaf?
          yield(node.item)
        else
          stack << node.right
          stack << node.left
        end
      end
    end
    include Enumerable

    # Return whether `other` contains the same item type and items in order.
    def eql?(other)
      return true if other.equal?(self)
      instance_of?(other.class) && to_a.eql?(other.to_a)
    end
    alias :== :eql?

    # Return an `Array` containing all items in order.
    def to_a
      result = []
      stack = [@root]
      until stack.empty?
        node = stack.pop
        next unless node
        if node.leaf?
          result << node.item
        else
          stack << node.right
          stack << node.left
        end
      end
      result
    end
    alias :entries :to_a
    alias :to_ary :to_a

    # Return a programmer-readable representation of the items.
    def inspect
      "#{self.class}[#{to_a.map(&:inspect).join(", ")}]"
    end

    # @private
    def pretty_print(pp)
      pp.group(1, "#{self.class}[", "]") do
        pp.breakable("")
        pp.seplist(to_a) { |item| item.pretty_print(pp) }
      end
    end

    private

    def compatible?(other)
      @identity.eql?(other.instance_variable_get(:@identity)) &&
        @measure.equal?(other.instance_variable_get(:@measure)) &&
        @combine.equal?(other.instance_variable_get(:@combine))
    end

    def leaf(item)
      Node.leaf(item, measure_item(item))
    end

    def measure_item(item)
      if @measure.is_a?(Symbol)
        item.public_send(@measure)
      else
        @measure.call(item)
      end
    end

    def combine(left, right)
      @combine.call(left, right)
    end

    def wrap(root)
      self.class.alloc(root, @identity, @measure, @combine)
    end

    def build_tree(items)
      leaves = items.map { |item| leaf(item) }
      build_balanced(leaves, 0, leaves.size)
    end

    def build_balanced(nodes, start_index, count)
      return nil if count.zero?
      return nodes[start_index] if count == 1

      left_count = count / 2
      left = build_balanced(nodes, start_index, left_count)
      right = build_balanced(nodes, start_index + left_count, count - left_count)
      Node.branch(left, right, @combine)
    end

    def split_node(node, accumulated, &predicate)
      left_result = nil
      right_result = nil

      until node.leaf?
        left_measurement = combine(accumulated, node.left.measurement)
        if predicate.call(left_measurement)
          right_result = Node.join(node.right, right_result, @combine)
          node = node.left
        else
          left_result = Node.join(left_result, node.left, @combine)
          accumulated = left_measurement
          node = node.right
        end
      end

      total = combine(accumulated, node.measurement)
      if predicate.call(total)
        right_result = Node.join(node, right_result, @combine)
      else
        left_result = Node.join(left_result, node, @combine)
      end

      [left_result, right_result]
    end

    # @private
    class Node
      attr_reader :left, :right, :item, :measurement, :size, :height

      def self.leaf(item, measurement)
        new(nil, nil, item, measurement, 1, 0)
      end

      def self.first_item(node)
        node = node.left while node && !node.leaf?
        node && node.item
      end

      def self.last_item(node)
        node = node.right while node && !node.leaf?
        node && node.item
      end

      def self.branch(left, right, combine)
        measurement = combine.call(left.measurement, right.measurement)
        new(left, right, nil, measurement,
            left.size + right.size,
            [left.height, right.height].max + 1)
      end

      def self.join(left, right, combine = nil)
        return right if left.nil?
        return left if right.nil?

        if left.height > right.height + 1
          rebalance(left.left, join(left.right, right, combine), combine)
        elsif right.height > left.height + 1
          rebalance(join(left, right.left, combine), right.right, combine)
        else
          branch(left, right, combine)
        end
      end

      def self.remove_first(node, combine)
        return nil if node.leaf?
        if node.left.leaf?
          node.right
        else
          rebalance(remove_first(node.left, combine), node.right, combine)
        end
      end

      def self.remove_last(node, combine)
        return nil if node.leaf?
        if node.right.leaf?
          node.left
        else
          rebalance(node.left, remove_last(node.right, combine), combine)
        end
      end

      def self.rebalance(left, right, combine)
        if left.height > right.height + 1
          if left.left.height >= left.right.height
            rotated_right = branch(left.right, right, combine)
            branch(left.left, rotated_right, combine)
          else
            middle = left.right
            rotated_left = branch(left.left, middle.left, combine)
            rotated_right = branch(middle.right, right, combine)
            branch(rotated_left, rotated_right, combine)
          end
        elsif right.height > left.height + 1
          if right.right.height >= right.left.height
            rotated_left = branch(left, right.left, combine)
            branch(rotated_left, right.right, combine)
          else
            middle = right.left
            rotated_left = branch(left, middle.left, combine)
            rotated_right = branch(middle.right, right.right, combine)
            branch(rotated_left, rotated_right, combine)
          end
        else
          branch(left, right, combine)
        end
      end

      def initialize(left, right, item, measurement, size, height)
        @left = left
        @right = right
        @item = item
        @measurement = measurement
        @size = size
        @height = height
        freeze
      end

      def leaf?
        @left.nil?
      end
    end
  end
end
