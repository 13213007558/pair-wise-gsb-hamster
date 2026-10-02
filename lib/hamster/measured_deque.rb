require "hamster/immutable"
require "hamster/enumerable"
require "hamster/hash"

module Hamster
  # A `MeasuredDeque` is an immutable, ordered, double-ended queue in which
  # every element carries a *measure*. You supply an identity element and an
  # associative combining operation (together describing a monoid); the deque
  # caches the aggregate measure of every internal subtree. This makes the
  # total measure, logarithmic concatenation, and measure-directed splitting
  # available without scanning every element.
  #
  # Internally it is a 2-3
  # {http://staff.city.ac.uk/~ross/papers/FingerTree.html finger tree}. End
  # insertion and removal are amortized constant time; {#concat concatenation}
  # and {#split splitting by accumulated measure} are logarithmic. Rebalancing
  # only moves whole subtrees and never reverses them, so a non-commutative
  # combining operation, such as string concatenation, keeps the correct
  # left-to-right order.
  #
  # By default an element is its own measure. To derive a measure from each
  # element, pass a callable as `measure`:
  #
  #     chunks = Hamster::MeasuredDeque.empty(0, measure: :bytesize.to_proc) { |a, b| a + b }
  #
  # End operations work like a regular {Deque}:
  #
  #     d = chunks.push("ab").push("cde")
  #     d.measure   # => 5
  #
  # To locate the chunk containing a cumulative byte offset, use {#split}:
  #
  #     d = Hamster::MeasuredDeque.new("", %w[ab cd ef]) { |a, b| a + b }
  #     before, chunk, after = d.split { |total| total.bytesize >= 3 }
  #     chunk          # => "cd"
  #     before.measure # => "ab"
  #     after.measure  # => "ef"
  #
  # Every "modifying" method returns a new `MeasuredDeque`; the receiver is
  # never changed.
  #
  # @see Deque the unmeasured double-ended queue
  class MeasuredDeque
    include Immutable
    include Hamster::Enumerable

    # @private A fixed measuring rule shared by all nodes of one deque.
    Metric = Struct.new(:identity, :measurer, :op) do
      def measure_of(item)
        measurer.call(item)
      end

      def combine(a, b)
        op.call(a, b)
      end
    end

    # @private Default measurer: an element is its own measure.
    SELF_MEASURER = lambda { |item| item }

    class << self
      # Create an empty deque with the given monoid.
      #
      # @param identity [Object] identity element of the measure monoid, e.g.
      #   `0` for addition or `""` for concatenation.
      # @param measure [#call] optional callable returning the measure of an
      #   element. Defaults to the element itself.
      # @param combine [#call] optional associative combine operation. If not
      #   given, a block must be supplied.
      # @yield [accumulated, measure] associative combine operation.
      # @return [MeasuredDeque]
      def empty(identity, measure: SELF_MEASURER, combine: nil, &block)
        combine ||= block
        raise ArgumentError, "an associative combine block is required" unless combine
        metric = Metric.new(identity, measure, combine).freeze
        alloc(FingerTree::Empty.new(metric), metric)
      end

      # Create a deque containing the given items under the given monoid.
      #
      # @param identity [Object] identity element of the measure monoid.
      # @param items [::Enumerable] elements in left-to-right order.
      # @param measure [#call] optional callable returning an element's measure.
      # @param combine [#call] optional associative combine operation.
      # @yield [accumulated, measure] associative combine operation.
      # @return [MeasuredDeque]
      def new(identity, items = [], measure: SELF_MEASURER, combine: nil, &block)
        deque = empty(identity, measure: measure, combine: combine || block)
        metric = deque.instance_variable_get(:@metric)
        root = items.inject(deque.instance_variable_get(:@root)) do |tree, item|
          tree.snoc(Leaf.new(metric, item))
        end
        alloc(root, metric)
      end

      # @private Wrap an existing finger tree in a new deque.
      def alloc(root, metric)
        instance = allocate
        instance.instance_variable_set(:@root, root)
        instance.instance_variable_set(:@metric, metric)
        instance.freeze
        instance
      end
    end

    # Return `true` if this deque contains no elements.
    # @return [Boolean]
    def empty?
      @root.is_a?(FingerTree::Empty)
    end

    # Return the number of elements in this deque.
    # @return [Integer]
    def size
      @root.size
    end
    alias :length :size

    # Return the total measure of all elements: the fold of the combining
    # operation over their measures, starting from the identity. For an empty
    # deque this is the identity element.
    # @return [Object]
    def measure
      @root.measure
    end
    alias :total_measure :measure

    # Return the first element, or `nil` if the deque is empty.
    # @return [Object]
    def first
      return nil if empty?
      pair = @root.uncons
      pair[0].item
    end

    # Return the last element, or `nil` if the deque is empty.
    # @return [Object]
    def last
      return nil if empty?
      pair = @root.unsnoc
      pair[0].item
    end

    # Return a new deque with `item` added at the end. Amortized O(1).
    # @param item [Object]
    # @return [MeasuredDeque]
    def push(item)
      self.class.alloc(@root.snoc(Leaf.new(@metric, item)), @metric)
    end
    alias :enqueue :push

    # Return a new deque with `item` added at the front. Amortized O(1).
    # @param item [Object]
    # @return [MeasuredDeque]
    def unshift(item)
      self.class.alloc(@root.cons(Leaf.new(@metric, item)), @metric)
    end

    # Return a new deque with the last element removed.
    # @return [MeasuredDeque]
    def pop
      return self if empty?
      _entry, rest = @root.unsnoc
      self.class.alloc(rest, @metric)
    end

    # Return a new deque with the first element removed.
    # @return [MeasuredDeque]
    def shift
      return self if empty?
      _entry, rest = @root.uncons
      self.class.alloc(rest, @metric)
    end
    alias :dequeue :shift

    # Return an empty deque with the same measure as this one.
    # @return [MeasuredDeque]
    def clear
      self.class.alloc(FingerTree::Empty.new(@metric), @metric)
    end

    # Return a new deque containing all elements of `self` followed by all
    # elements of `other`. Both deques must use the same measure identity.
    # Logarithmic time. Elements are never reordered, so non-commutative
    # measures are combined in the correct order.
    #
    # @param other [MeasuredDeque]
    # @return [MeasuredDeque]
    def concat(other)
      unless other.is_a?(self.class) && other.same_monoid?(@metric.identity)
        raise ArgumentError, "can only concatenate a MeasuredDeque with the same measure identity"
      end
      self.class.alloc(@root.concat_tree(other.instance_variable_get(:@root)), @metric)
    end
    alias :+ :concat
    alias :append :concat

    # Yield each element once, from front to back.
    # @return [Enumerator, self]
    def each
      return enum_for(:each) unless block_given?
      @root.each_leaf { |item| yield(item) }
      self
    end

    # Yield each element once, from back to front.
    # @return [Enumerator, self]
    def reverse_each
      return enum_for(:reverse_each) unless block_given?
      @root.reverse_each_leaf { |item| yield(item) }
      self
    end

    # Return an `Array` with the same elements, front to back.
    # @return [Array]
    def to_a
      result = []
      @root.each_leaf { |item| result << item }
      result
    end
    alias :entries :to_a
    alias :to_ary  :to_a

    # Return a new deque keeping the elements for which the block is true.
    # @return [MeasuredDeque]
    def select
      return enum_for(:select) unless block_given?
      kept = []
      @root.each_leaf { |item| kept << item if yield(item) }
      rebuild(kept)
    end
    alias :filter :select

    # Return a new deque with each element transformed by the block. The result
    # keeps the same monoid; the measure of each transformed element is derived
    # with the original measurer.
    # @return [MeasuredDeque]
    def map
      return enum_for(:map) unless block_given?
      mapped = []
      @root.each_leaf { |item| mapped << yield(item) }
      rebuild(mapped)
    end

    # Return `[accepted, rejected]`, both deques with the same measure.
    # @return [Array(MeasuredDeque, MeasuredDeque)]
    def partition
      return enum_for(:partition) unless block_given?
      accepted, rejected = [], []
      @root.each_leaf do |item|
        (yield(item) ? accepted : rejected) << item
      end
      [rebuild(accepted), rebuild(rejected)].freeze
    end

    # Group elements into a {Hamster::Hash} keyed by the block result.
    # @return [Hamster::Hash]
    def group_by
      return enum_for(:group_by) unless block_given?
      groups = ::Hash.new { |hash, key| hash[key] = [] }
      @root.each_leaf { |item| groups[yield(item)] << item }
      pairs = groups.map { |key, items| [key, rebuild(items)] }
      Hamster::Hash[pairs]
    end

    # Return true if `other` is a deque with the same elements, in order.
    # @return [Boolean]
    def eql?(other)
      return true if other.equal?(self)
      other.is_a?(self.class) && to_a.eql?(other.to_a)
    end
    alias :== :eql?

    # Locate the first element at which the accumulated measure satisfies the
    # (monotone) predicate.
    #
    # The block is called with the measure accumulated from the identity
    # through successive elements, and must be monotone: once it returns
    # `true` for an accumulated measure it must keep returning `true` for every
    # larger accumulated measure. Returns a three-element array
    # `[before, element, after]`:
    #
    # - `before` is the deque of elements strictly before the located element.
    # - `element` is the first element whose accumulated measure satisfies the
    #   predicate.
    # - `after` is the deque from just after that element to the end.
    #
    # Boundary conventions:
    #
    # - On an empty deque, returns `[self, nil, self]`.
    # - If the predicate is already true at the identity (before any element),
    #   the first element is located and `before` is empty.
    # - If the predicate never becomes true, returns
    #   `[self, nil, self.class empty deque]`: the whole deque is `before` and
    #   there is no located element.
    #
    # Runs in O(log n) combining/predicate steps; it never scans every element.
    #
    # @example find the chunk containing a byte offset
    #   deque.split { |total| total.bytesize > offset }
    #
    # @return [Array(MeasuredDeque, Object, MeasuredDeque)]
    def split
      return enum_for(:split) unless block_given?
      return [self, nil, self] if empty?
      root_result = @root.split_tree(@metric.identity, lambda { |total| yield(total) })
      unless root_result
        empty_deque = self.class.alloc(FingerTree::Empty.new(@metric), @metric)
        return [self, nil, empty_deque]
      end
      left_tree, pivot_entry, right_tree = root_result
      left  = self.class.alloc(left_tree, @metric)
      right = self.class.alloc(right_tree, @metric)
      [left, pivot_entry.item, right]
    end

    # Return the longest prefix for which the predicate is still false, the
    # first element for which it becomes true, and the remainder. This is the
    # same boundary convention as {#split}.
    # @return [Array(MeasuredDeque, Object, MeasuredDeque)]
    def split_measure(&predicate)
      split(&predicate)
    end

    # Return the elements strictly before the first one that satisfies the
    # monotone predicate.
    # @return [MeasuredDeque]
    def take_measure(&predicate)
      return enum_for(:take_measure) unless predicate
      before, _element, _after = split(&predicate)
      before
    end

    # Return the elements from the first one that satisfies the monotone
    # predicate onward. If none satisfies it, returns an empty deque.
    # @return [MeasuredDeque]
    def drop_measure(&predicate)
      return enum_for(:drop_measure) unless predicate
      _before, element, after = split(&predicate)
      element.nil? ? after : after.unshift(element)
    end

    # @return [String]
    def inspect
      result = "#{self.class}["
      each_with_index { |obj, index| result << ", " if index > 0; result << obj.inspect }
      result << "]"
    end

    # @return [Boolean] whether `identity` is this deque's measure identity.
    # @private
    def same_monoid?(identity)
      @metric.identity.eql?(identity) || @metric.identity == identity
    end

    protected

    # Build a new deque with the same monoid from an array of elements.
    def rebuild(items)
      root = items.inject(FingerTree::Empty.new(@metric)) do |tree, item|
        tree.snoc(Leaf.new(@metric, item))
      end
      self.class.alloc(root, @metric)
    end

    # @private A single user element. Leaves are the bottom-level entries.
    class Leaf
      attr_reader :item, :measure, :size

      def initialize(metric, item)
        @metric  = metric
        @item    = item
        @measure = metric.measure_of(item)
        @size    = 1
        freeze
      end

      def each_leaf
        yield(@item)
      end

      def reverse_each_leaf
        yield(@item)
      end
    end

    # @private Shared behavior of internal nodes grouping child nodes.
    module InternalNode
      attr_reader :measure, :size

      # Yield the grouped child nodes as an array.
      def children
        @children
      end

      def each_leaf
        @children.each { |child| child.each_leaf { |item| yield(item) } }
      end

      def reverse_each_leaf
        @children.reverse_each { |child| child.reverse_each_leaf { |item| yield(item) } }
      end

      # Split one level through this node. `accumulated` is the measure to the
      # node's left. The matched child is returned as the pivot at the level
      # below; it is not descended into. Returns
      # `[left_children, pivot_child, right_children]`.
      def split_node(accumulated, predicate)
        scan = accumulated
        @children.each_with_index do |child, index|
          with_child = @metric.combine(scan, child.measure)
          if predicate.call(with_child)
            return [@children[0...index], child, @children[(index + 1)..-1]]
          end
          scan = with_child
        end
        nil
      end
    end

    # @private An internal node grouping two child nodes.
    class Node2
      include InternalNode

      def initialize(metric, left, right)
        @metric   = metric
        @children = [left, right].freeze
        @measure  = metric.combine(left.measure, right.measure)
        @size     = left.size + right.size
        freeze
      end
    end

    # @private An internal node grouping three child nodes.
    class Node3
      include InternalNode

      def initialize(metric, first, second, third)
        @metric   = metric
        @children = [first, second, third].freeze
        @measure  = metric.combine(metric.combine(first.measure, second.measure), third.measure)
        @size     = first.size + second.size + third.size
        freeze
      end
    end

    # @private Nodes of the finger tree itself: empty, one entry, or deep.
    module FingerTree
      # Group `n >= 2` entries (preserving order) into balanced internal nodes,
      # each holding two or three children.
      def self.group(metric, entries)
        n = entries.length
        raise ArgumentError, "cannot group #{n} entries" if n < 2
        groups = n / 3
        remainder = n % 3
        if remainder == 1
          # Use one extra pair so the rest divides evenly into triples.
          groups -= 1
          remainder = 4
        end
        nodes = []
        index = 0
        groups.times do
          nodes << Node3.new(metric, entries[index], entries[index + 1], entries[index + 2])
          index += 3
        end
        if remainder == 2
          nodes << Node2.new(metric, entries[index], entries[index + 1])
        elsif remainder == 4
          nodes << Node2.new(metric, entries[index], entries[index + 1])
          nodes << Node2.new(metric, entries[index + 2], entries[index + 3])
        end
        nodes
      end

      # Concatenate any two finger trees sharing one metric.
      def self.concat(left, right)
        app3(left, [], right)
      end

      # Prepend entries to a tree, preserving their order.
      def self.prepend_entries(entries, tree)
        entries.reverse_each.reduce(tree) { |result, entry| result.cons(entry) }
      end

      # Append entries to a tree, preserving their order.
      def self.append_entries(tree, entries)
        entries.reduce(tree) { |result, entry| result.snoc(entry) }
      end

      # Concatenate two trees with a list of entries between them.
      def self.app3(left, entries, right)
        if left.is_a?(Empty)
          prepend_entries(entries, right)
        elsif right.is_a?(Empty)
          append_entries(left, entries)
        elsif left.is_a?(Single)
          prepend_entries([left.entry] + entries, right)
        elsif right.is_a?(Single)
          append_entries(left, entries + [right.entry])
        else
          nodes = group(left.metric, left.suffix + entries + right.prefix)
          Deep.new(left.metric, left.prefix, app3(left.middle, nodes, right.middle), right.suffix)
        end
      end

      # Shared metadata and digit helpers for all tree shapes.
      module Structure
        attr_reader :measure, :size

        def empty?
          false
        end

        private

        def node2(left, right)
          Node2.new(@metric, left, right)
        end

        def node3(first, second, third)
          Node3.new(@metric, first, second, third)
        end

        # Build a tree holding 1..4 entries by repeated rear insertion.
        def tree_from_digits(entries)
          entries.inject(Empty.new(@metric)) { |tree, entry| tree.snoc(entry) }
        end
      end

      # @private The empty finger tree.
      class Empty
        include Structure

        attr_reader :metric

        def initialize(metric)
          @metric  = metric
          @measure = metric.identity
          @size    = 0
          freeze
        end

        def empty?
          true
        end

        def each_leaf
        end

        def reverse_each_leaf
        end

        def cons(entry)
          Single.new(@metric, entry)
        end

        def snoc(entry)
          Single.new(@metric, entry)
        end

        def uncons
          nil
        end

        def unsnoc
          nil
        end

        def concat_tree(other)
          FingerTree.concat(self, other)
        end

        # The predicate can never become true inside an empty tree.
        def split_tree(_accumulated, _predicate)
          nil
        end
      end

      # @private A finger tree holding exactly one entry.
      class Single
        include Structure

        attr_reader :metric, :entry

        def initialize(metric, entry)
          @metric  = metric
          @entry   = entry
          @measure = entry.measure
          @size    = entry.size
          freeze
        end

        def each_leaf
          @entry.each_leaf { |item| yield(item) }
        end

        def reverse_each_leaf
          @entry.reverse_each_leaf { |item| yield(item) }
        end

        def cons(entry)
          Deep.new(@metric, [entry].freeze, Empty.new(@metric), [@entry].freeze)
        end

        def snoc(entry)
          Deep.new(@metric, [@entry].freeze, Empty.new(@metric), [entry].freeze)
        end

        def uncons
          [@entry, Empty.new(@metric)]
        end

        def unsnoc
          [@entry, Empty.new(@metric)]
        end

        def concat_tree(other)
          FingerTree.concat(self, other)
        end

        # Split the single entry. Called only when the predicate becomes true
        # at this entry.
        def split_tree(accumulated, predicate)
          with_entry = @metric.combine(accumulated, @entry.measure)
          if predicate.call(with_entry)
            [Empty.new(@metric), @entry, Empty.new(@metric)]
          end
        end
      end

      # @private A finger tree with front and rear digits and a middle tree.
      class Deep
        include Structure

        attr_reader :metric, :prefix, :middle, :suffix

        def initialize(metric, prefix, middle, suffix)
          @metric = metric
          @prefix = prefix
          @middle = middle
          @suffix = suffix
          @measure = metric.combine(digits_measure(prefix),
                       metric.combine(middle.measure, digits_measure(suffix)))
          @size = digits_size(prefix) + middle.size + digits_size(suffix)
          freeze
        end

        def each_leaf
          @prefix.each { |entry| entry.each_leaf { |item| yield(item) } }
          @middle.each_leaf { |item| yield(item) }
          @suffix.each { |entry| entry.each_leaf { |item| yield(item) } }
        end

        def reverse_each_leaf
          @suffix.reverse_each { |entry| entry.reverse_each_leaf { |item| yield(item) } }
          @middle.reverse_each_leaf { |item| yield(item) }
          @prefix.reverse_each { |entry| entry.reverse_each_leaf { |item| yield(item) } }
        end

        # Prepend an entry (a leaf, or an internal node in the middle tree).
        def cons(entry)
          if @prefix.length < 4
            Deep.new(@metric, ([entry] + @prefix).freeze, @middle, @suffix)
          else
            Deep.new(@metric,
              [entry, @prefix[0]].freeze,
              @middle.cons(node3(@prefix[1], @prefix[2], @prefix[3])),
              @suffix)
          end
        end

        # Append an entry.
        def snoc(entry)
          if @suffix.length < 4
            Deep.new(@metric, @prefix, @middle, (@suffix + [entry]).freeze)
          else
            Deep.new(@metric,
              @prefix,
              @middle.snoc(node3(@suffix[0], @suffix[1], @suffix[2])),
              [@suffix[3], entry].freeze)
          end
        end

        # Remove and return the first entry as `[entry, remaining_tree]`.
        def uncons
          entry = @prefix.first
          if @prefix.length > 1
            [entry, Deep.new(@metric, @prefix[1..-1].freeze, @middle, @suffix)]
          elsif !@middle.empty?
            pivot, remaining = @middle.uncons
            [entry, Deep.new(@metric, pivot.children.freeze, remaining, @suffix)]
          else
            [entry, tree_from_digits(@suffix)]
          end
        end

        # Remove and return the last entry as `[entry, remaining_tree]`.
        def unsnoc
          entry = @suffix.last
          if @suffix.length > 1
            [entry, Deep.new(@metric, @prefix, @middle, @suffix[0..-2].freeze)]
          elsif !@middle.empty?
            pivot, remaining = @middle.unsnoc
            [entry, Deep.new(@metric, @prefix, remaining, pivot.children.freeze)]
          else
            [entry, tree_from_digits(@prefix)]
          end
        end

        def concat_tree(other)
          FingerTree.concat(self, other)
        end

        # Measure-directed split. `accumulated` is the measure already counted
        # to the left of this tree; `predicate` is monotone on accumulated
        # measures. Returns `[left_tree, pivot, right_tree]` with the first
        # entry for which the predicate becomes true, or `nil` if it stays
        # false over the whole tree.
        def split_tree(accumulated, predicate)
          scan = accumulated
          @prefix.each_with_index do |entry, index|
            with_entry = @metric.combine(scan, entry.measure)
            if predicate.call(with_entry)
              left  = build_left(@prefix[0...index])
              right = FingerTree.prepend_entries(@prefix[(index + 1)..-1],
                        Deep.new(@metric, [].freeze, @middle, @suffix))
              return [left, entry, right]
            end
            scan = with_entry
          end

          if (middle_split = @middle.split_tree(scan, predicate))
            middle_left, pivot, middle_right = middle_split
            if pivot.is_a?(Leaf)
              return [deepL(@prefix, middle_left, []),
                      pivot,
                      deepR([], middle_right, @suffix)]
            else
              before_pivot = @metric.combine(scan, middle_left.measure)
              left_children, leaf_pivot, right_children =
                pivot.split_node(before_pivot, predicate)
              return [deepL(@prefix, middle_left, left_children),
                      leaf_pivot,
                      deepR(right_children, middle_right, @suffix)]
            end
          end

          scan = @metric.combine(scan, @middle.measure)
          @suffix.each_with_index do |entry, index|
            with_entry = @metric.combine(scan, entry.measure)
            if predicate.call(with_entry)
              left  = FingerTree.append_entries(
                        Deep.new(@metric, @prefix, @middle, [].freeze),
                        @suffix[0...index])
              right = build_right(@suffix[(index + 1)..-1])
              return [left, entry, right]
            end
            scan = with_entry
          end
          nil
        end

        private

        # Assemble a left result from prefix entries alone, with no middle.
        def build_left(prefix_entries)
          FingerTree.append_entries(FingerTree::Empty.new(@metric), prefix_entries)
        end

        # Assemble a right result from suffix entries alone, with no middle.
        def build_right(suffix_entries)
          FingerTree.prepend_entries(suffix_entries, FingerTree::Empty.new(@metric))
        end

        # Build the left result of a split. `suffix` is always non-empty here.
        def deepL(prefix, middle, suffix)
          if !prefix.empty?
            Deep.new(@metric, prefix.freeze, middle, suffix)
          elsif !middle.empty?
            pivot, remaining = middle.uncons
            Deep.new(@metric, pivot.children.freeze, remaining, suffix)
          else
            tree_from_digits(suffix)
          end
        end

        # Build the right result of a split. `prefix` is always non-empty here.
        def deepR(prefix, middle, suffix)
          if !suffix.empty?
            Deep.new(@metric, prefix, middle, suffix.freeze)
          elsif !middle.empty?
            pivot, remaining = middle.unsnoc
            Deep.new(@metric, prefix, remaining, pivot.children.freeze)
          else
            tree_from_digits(prefix)
          end
        end

        def digits_measure(entries)
          entries.inject(@metric.identity) do |acc, entry|
            @metric.combine(acc, entry.measure)
          end
        end

        def digits_size(entries)
          entries.inject(0) { |total, entry| total + entry.size }
        end
      end
    end
  end
end
