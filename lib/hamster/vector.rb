require "hamster/immutable"
require "hamster/enumerable"
require "hamster/hash"
require "hamster/associable"

module Hamster
  # A `Vector` is an ordered, integer-indexed collection of objects. Like
  # Ruby's `Array`, `Vector` indexing starts at zero and negative indexes count
  # back from the end.
  #
  # `Vector` has a similar interface to `Array`. The main difference is methods
  # that would destructively update an `Array` (such as {#insert} or
  # {#delete_at}) instead return new `Vectors` and leave the existing one
  # unchanged.
  #
  # ### Creating New Vectors
  #
  #     Hamster::Vector.new([:first, :second, :third])
  #     Hamster::Vector[1, 2, 3, 4, 5]
  #
  # ### Retrieving Items from Vectors
  #
  #     vector = Hamster::Vector[1, 2, 3, 4, 5]
  #
  #     vector[0]      # => 1
  #     vector[-1]     # => 5
  #     vector[0,3]    # => Hamster::Vector[1, 2, 3]
  #     vector[1..-1]  # => Hamster::Vector[2, 3, 4, 5]
  #     vector.first   # => 1
  #     vector.last    # => 5
  #
  # ### Creating Modified Vectors
  #
  #     vector.add(6)            # => Hamster::Vector[1, 2, 3, 4, 5, 6]
  #     vector.insert(1, :a, :b) # => Hamster::Vector[1, :a, :b, 2, 3, 4, 5]
  #     vector.delete_at(2)      # => Hamster::Vector[1, 2, 4, 5]
  #     vector + [6, 7]          # => Hamster::Vector[1, 2, 3, 4, 5, 6, 7]
  #
  class Vector
    include Immutable
    include Enumerable
    include Associable

    # @private
    BLOCK_SIZE = 32
    # @private
    INDEX_MASK = BLOCK_SIZE - 1
    # @private
    BITS_PER_LEVEL = 5

    class StructuralNode
      def self.raise_to(node, height)
        while node.height < height
          node = InternalNode.new(node.height + 1, [node])
        end
        node
      end

      def self.minimize(node)
        while node.is_a?(InternalNode) && node.children.size == 1
          node = node.children.first
        end
        node
      end
    end

    class LeafNode < StructuralNode
      attr_reader :array, :offset, :size

      def initialize(array, offset = 0, size = array.size - offset)
        @array = array
        @offset = offset
        @size = size
        freeze
      end

      def height
        0
      end

      def get(index)
        @array[@offset + index]
      end

      def each(&block)
        return enum_for(__method__) unless block_given?
        @size.times { |index| yield @array[@offset + index] }
        self
      end

      def reverse_each(&block)
        return enum_for(__method__) unless block_given?
        @size.times { |index| yield @array[@offset + @size - index - 1] }
        self
      end

      def put(index, item)
        existing = @array[@offset + index]
        return self if existing.equal?(item)
        values = Array.new(@size) { |i| @array[@offset + i] }
        values[index] = item
        LeafNode.new(values.freeze)
      end

      def slice_range(from, to)
        return self if from == 0 && to == @size
        LeafNode.new(@array, @offset + from, to - from)
      end

      def to_a
        Array.new(@size) { |index| @array[@offset + index] }
      end
    end

    class InternalNode < StructuralNode
      attr_reader :height, :children, :sizes

      def initialize(height, children)
        @height = height
        @children = children.freeze
        total = 0
        @sizes = children.map { |child| total += child.size }.freeze
        freeze
      end

      def size
        @sizes.last
      end

      def child_and_offset(index)
        child_index = @sizes.bsearch_index { |size| size > index }
        start = child_index == 0 ? 0 : @sizes[child_index - 1]
        [@children[child_index], index - start, child_index]
      end

      def get(index)
        child, offset = child_and_offset(index)
        child.get(offset)
      end

      def each(&block)
        return enum_for(__method__) unless block_given?
        @children.each { |child| child.each(&block) }
        self
      end

      def reverse_each(&block)
        return enum_for(__method__) unless block_given?
        @children.reverse_each { |child| child.reverse_each(&block) }
        self
      end

      def put(index, item)
        child, offset, child_index = child_and_offset(index)
        updated = child.put(offset, item)
        return self if updated.equal?(child)
        children = @children.dup
        children[child_index] = updated
        InternalNode.new(@height, children)
      end

      def slice_range(from, to)
        first = @sizes.bsearch_index { |size| size > from }
        last = @sizes.bsearch_index { |size| size >= to }
        pieces = []

        first.upto(last) do |child_index|
          child = @children[child_index]
          start = child_index == 0 ? 0 : @sizes[child_index - 1]
          local_from = [from - start, 0].max
          local_to = [to - start, child.size].min
          piece = child.slice_range(local_from, local_to)
          pieces << StructuralNode.raise_to(piece, @height - 1)
        end

        if pieces.size == 1
          StructuralNode.minimize(pieces.first)
        else
          InternalNode.new(@height, pieces)
        end
      end

      def to_a
        @children.flat_map(&:to_a)
      end
    end

    class CanonicalNode < StructuralNode
      attr_reader :height, :root, :size

      def initialize(height, root, size)
        @height = height
        @root = root
        @size = size
        freeze
      end

      def get(index)
        node = @root
        bitshift = @height * BITS_PER_LEVEL
        while bitshift > 0
          node = node[(index >> bitshift) & INDEX_MASK]
          bitshift -= BITS_PER_LEVEL
        end
        node[index & INDEX_MASK]
      end

      def each(&block)
        return enum_for(__method__) unless block_given?
        self.class.traverse(@root, @height, &block)
        self
      end

      def reverse_each(&block)
        return enum_for(__method__) unless block_given?
        self.class.reverse_traverse(@root, @height, &block)
        self
      end

      def put(index, item)
        updated = self.class.update_node(@root, @height * BITS_PER_LEVEL, index, item)
        return self if updated.equal?(@root)
        CanonicalNode.new(@height, updated, @size)
      end

      def children
        capacity = 1 << (@height * BITS_PER_LEVEL)
        @root.each_with_index.map do |child, index|
          start = index * capacity
          child_size = index == @root.size - 1 ? @size - start : capacity
          self.class.wrap(child, @height - 1, child_size)
        end
      end

      def slice_range(from, to)
        return self if from == 0 && to == @size

        if @height == 0
          piece = LeafNode.new(@root, 0, @size).slice_range(from, to)
          return StructuralNode.minimize(StructuralNode.raise_to(piece, 0))
        end

        capacity = 1 << (@height * BITS_PER_LEVEL)
        first = from / capacity
        last = (to - 1) / capacity
        pieces = []

        first.upto(last) do |index|
          start = index * capacity
          child_size = index == @root.size - 1 ? @size - start : capacity
          local_from = [from - start, 0].max
          local_to = [to - start, child_size].min
          child = self.class.wrap(@root[index], @height - 1, child_size)
          piece = child.slice_range(local_from, local_to)
          pieces << StructuralNode.raise_to(piece, @height - 1)
        end

        if pieces.size == 1
          StructuralNode.minimize(pieces.first)
        else
          InternalNode.new(@height, pieces)
        end
      end

      def to_a
        self.class.flatten(@root, @height, [])
      end

      def self.traverse(node, height, &block)
        if height == 0
          node.each(&block)
        else
          node.each { |child| traverse(child, height - 1, &block) }
        end
      end

      def self.reverse_traverse(node, height, &block)
        if height == 0
          node.reverse_each(&block)
        else
          node.reverse_each { |child| reverse_traverse(child, height - 1, &block) }
        end
      end

      def self.update_node(node, bitshift, index, item)
        slot = (index >> bitshift) & INDEX_MASK
        if bitshift > 0
          child = update_node(node[slot], bitshift - BITS_PER_LEVEL, index, item)
          item = child
        end
        return node if node[slot].equal?(item)
        updated = node.dup
        updated[slot] = item
        updated.freeze
      end

      def self.wrap(node, height, size)
        if height == 0
          LeafNode.new(node, 0, size)
        else
          CanonicalNode.new(height, node, size)
        end
      end

      def self.flatten(node, height, result)
        if height == 0
          result.concat(node)
        else
          node.each { |child| flatten(child, height - 1, result) }
        end
        result
      end
    end

    # Return the number of items in this `Vector`
    # @return [Integer]
    attr_reader :size
    alias :length :size

    class << self
      # Create a new `Vector` populated with the given items.
      # @return [Vector]
      def [](*items)
        new(items.freeze)
      end

      # Return an empty `Vector`. If used on a subclass, returns an empty instance
      # of that class.
      #
      # @return [Vector]
      def empty
        @empty ||= self.new
      end

      # "Raw" allocation of a new `Vector`. Used internally to create a new
      # instance quickly after building a modified trie.
      #
      # @return [Vector]
      # @private
      def alloc(root, size, levels)
        obj = allocate
        obj.instance_variable_set(:@root, root)
        obj.instance_variable_set(:@size, size)
        obj.instance_variable_set(:@levels, levels)
        obj
      end
    end

    def initialize(items=[].freeze)
      items = items.to_a
      if items.size <= 32
        items = items.dup.freeze if !items.frozen?
        @root, @size, @levels = items, items.size, 0
      else
        root, size, levels = items, items.size, 0
        while root.size > 32
          root = root.each_slice(32).to_a
          levels += 1
        end
        @root, @size, @levels = root.freeze, size, levels
      end
    end

    # Return `true` if this `Vector` contains no items.
    #
    # @return [Boolean]
    def empty?
      @size == 0
    end

    # Return the first item in the `Vector`. If the vector is empty, return `nil`.
    #
    # @example
    #   Hamster::Vector["A", "B", "C"].first  # => "A"
    #
    # @return [Object]
    def first
      get(0)
    end

    # Return the last item in the `Vector`. If the vector is empty, return `nil`.
    #
    # @example
    #   Hamster::Vector["A", "B", "C"].last  # => "C"
    #
    # @return [Object]
    def last
      get(-1)
    end

    # Return a new `Vector` with `item` added after the last occupied position.
    #
    # @example
    #   Hamster::Vector[1, 2].add(99)  # => Hamster::Vector[1, 2, 99]
    #
    # @param item [Object] The object to insert at the end of the vector
    # @return [Vector]
    def add(item)
      update_root(@size, item)
    end
    alias :<< :add
    alias :push :add

    # Return a new `Vector` with a new value at the given `index`. If `index`
    # is greater than the length of the vector, the returned vector will be
    # padded with `nil`s to the correct size.
    #
    # @overload put(index, item)
    #   Return a new `Vector` with the item at `index` replaced by `item`.
    #
    #   @param item [Object] The object to insert into that position
    #   @example
    #     Hamster::Vector[1, 2, 3, 4].put(2, 99)
    #     # => Hamster::Vector[1, 2, 99, 4]
    #     Hamster::Vector[1, 2, 3, 4].put(-1, 99)
    #     # => Hamster::Vector[1, 2, 3, 99]
    #     Hamster::Vector[].put(2, 99)
    #     # => Hamster::Vector[nil, nil, 99]
    #
    # @overload put(index)
    #   Return a new `Vector` with the item at `index` replaced by the return
    #   value of the block.
    #
    #   @yield (existing) Once with the existing value at the given `index`.
    #   @example
    #     Hamster::Vector[1, 2, 3, 4].put(2) { |v| v * 10 }
    #     # => Hamster::Vector[1, 2, 30, 4]
    #
    # @param index [Integer] The index to update. May be negative.
    # @return [Vector]
    def put(index, item = yield(get(index)))
      raise IndexError, "index #{index} outside of vector bounds" if index < -@size
      index += @size if index < 0
      if index > @size
        padding = self.class.new(Array.new(index - @size, nil) << item)
        self + padding
      else
        update_root(index, item)
      end
    end
    alias :set :put

    # Return a new `Vector` with a deeply nested value modified to the result
    # of the given code block.  When traversing the nested `Vector`s and
    # `Hash`es, non-existing keys are created with empty `Hash` values.
    #
    # The code block receives the existing value of the deeply nested key (or
    # `nil` if it doesn't exist). This is useful for "transforming" the value
    # associated with a certain key.
    #
    # Note that the original `Vector` and sub-`Vector`s and sub-`Hash`es are
    # left unmodified; new data structure copies are created along the path
    # wherever needed.
    #
    # @example
    #   v = Hamster::Vector[123, 456, 789, Hamster::Hash["a" => Hamster::Vector[5, 6, 7]]]
    #   v.update_in(3, "a", 1) { |value| value + 9 }
    #   # => Hamster::Vector[123, 456, 789, Hamster::Hash["a" => Hamster::Vector[5, 15, 7]]]
    #
    # @param key_path [Object(s)] List of keys which form the path to the key to be modified
    # @yield [value] The previously stored value
    # @yieldreturn [Object] The new value to store
    # @return [Vector]

    # Retrieve the item at `index`. If there is none (either the provided index
    # is too high or too low), return `nil`.
    #
    # @example
    #   v = Hamster::Vector["A", "B", "C", "D"]
    #   v.get(2)   # => "C"
    #   v.get(-1)  # => "D"
    #   v.get(4)   # => nil
    #
    # @param index [Integer] The index to retrieve
    # @return [Object]
    def get(index)
      return nil if @size == 0
      index += @size if index < 0
      return nil if index >= @size || index < 0
      if structural?
        @root.get(index)
      else
        leaf_node_for(@root, @levels * BITS_PER_LEVEL, index)[index & INDEX_MASK]
      end
    end
    alias :at :get

    # Retrieve the value at `index` with optional default.
    #
    # @overload fetch(index)
    #   Retrieve the value at the given index, or raise an `IndexError` if not
    #   found.
    #
    #   @param index [Integer] The index to look up
    #   @raise [IndexError] if index does not exist
    #   @example
    #     v = Hamster::Vector["A", "B", "C", "D"]
    #     v.fetch(2)       # => "C"
    #     v.fetch(-1)      # => "D"
    #     v.fetch(4)       # => IndexError: index 4 outside of vector bounds
    #
    # @overload fetch(index) { |index| ... }
    #   Retrieve the value at the given index, or return the result of yielding
    #   the block if not found.
    #
    #   @yield Once if the index is not found.
    #   @yieldparam [Integer] index The index which does not exist
    #   @yieldreturn [Object] Default value to return
    #   @param index [Integer] The index to look up
    #   @example
    #     v = Hamster::Vector["A", "B", "C", "D"]
    #     v.fetch(2) { |i| i * i }   # => "C"
    #     v.fetch(4) { |i| i * i }   # => 16
    #
    # @overload fetch(index, default)
    #   Retrieve the value at the given index, or return the provided `default`
    #   value if not found.
    #
    #   @param index [Integer] The index to look up
    #   @param default [Object] Object to return if the key is not found
    #   @example
    #     v = Hamster::Vector["A", "B", "C", "D"]
    #     v.fetch(2, "Z")  # => "C"
    #     v.fetch(4, "Z")  # => "Z"
    #
    # @return [Object]
    def fetch(index, default = (missing_default = true))
      if index >= -@size && index < @size
        get(index)
      elsif block_given?
        yield(index)
      elsif !missing_default
        default
      else
        raise IndexError, "index #{index} outside of vector bounds"
      end
    end

    # Return specific objects from the `Vector`. All overloads return `nil` if
    # the starting index is out of range.
    #
    # @overload vector.slice(index)
    #   Returns a single object at the given `index`. If `index` is negative,
    #   count backwards from the end.
    #
    #   @param index [Integer] The index to retrieve. May be negative.
    #   @return [Object]
    #   @example
    #     v = Hamster::Vector["A", "B", "C", "D", "E", "F"]
    #     v[2]  # => "C"
    #     v[-1] # => "F"
    #     v[6]  # => nil
    #
    # @overload vector.slice(index, length)
    #   Return a subvector starting at `index` and continuing for `length`
    #   elements or until the end of the `Vector`, whichever occurs first.
    #
    #   @param start [Integer] The index to start retrieving items from. May be
    #                          negative.
    #   @param length [Integer] The number of items to retrieve.
    #   @return [Vector]
    #   @example
    #     v = Hamster::Vector["A", "B", "C", "D", "E", "F"]
    #     v[2, 3]  # => Hamster::Vector["C", "D", "E"]
    #     v[-2, 3] # => Hamster::Vector["E", "F"]
    #     v[20, 1] # => nil
    #
    # @overload vector.slice(index..end)
    #   Return a subvector starting at `index` and continuing to index
    #   `end` or the end of the `Vector`, whichever occurs first.
    #
    #   @param range [Range] The range of indices to retrieve.
    #   @return [Vector]
    #   @example
    #     v = Hamster::Vector["A", "B", "C", "D", "E", "F"]
    #     v[2..3]    # => Hamster::Vector["C", "D"]
    #     v[-2..100] # => Hamster::Vector["E", "F"]
    #     v[20..21]  # => nil
    def slice(arg, length = (missing_length = true))
      if missing_length
        if arg.is_a?(Range)
          from, to = arg.begin, arg.end
          from += @size if from < 0
          to   += @size if to < 0
          to   += 1     if !arg.exclude_end?
          length = to - from
          length = 0 if length < 0
          subsequence(from, length)
        else
          get(arg)
        end
      else
        arg += @size if arg < 0
        subsequence(arg, length)
      end
    end
    alias :[] :slice

    # Return a new `Vector` with the given values inserted before the element
    # at `index`. If `index` is greater than the current length, `nil` values
    # are added to pad the `Vector` to the required size.
    #
    # @example
    #   Hamster::Vector["A", "B", "C", "D"].insert(2, "X", "Y", "Z")
    #   # => Hamster::Vector["A", "B", "X", "Y", "Z", "C", "D"]
    #   Hamster::Vector[].insert(2, "X", "Y", "Z")
    #   # => Hamster::Vector[nil, nil, "X", "Y", "Z"]
    #
    # @param index [Integer] The index where the new items should go
    # @param items [Array] The items to add
    # @return [Vector]
    # @raise [IndexError] if index exceeds negative range.
    def insert(index, *items)
      raise IndexError if index < -@size
      index += @size if index < 0

      if index < @size
        prefix = subsequence(0, index)
        suffix = subsequence(index, @size - index)
        inserted = self.class.new(items)
        return prefix + inserted + suffix
      else
        padding = Array.new(index - @size, nil).concat(items)
        return self + self.class.new(padding)
      end
    end

    # Return a new `Vector` with the element at `index` removed. If the given `index`
    # does not exist, return `self`.
    #
    # @example
    #   Hamster::Vector["A", "B", "C", "D"].delete_at(2)
    #   # => Hamster::Vector["A", "B", "D"]
    #
    # @param index [Integer] The index to remove
    # @return [Vector]
    def delete_at(index)
      return self if index >= @size || index < -@size
      index += @size if index < 0
      subsequence(0, index) + subsequence(index + 1, @size - index - 1)
    end

    # Return a new `Vector` with the last element removed. Return `self` if
    # empty.
    #
    # @example
    #   Hamster::Vector["A", "B", "C"].pop  # => Hamster::Vector["A", "B"]
    #
    # @return [Vector]
    def pop
      return self if @size == 0
      subsequence(0, @size - 1)
    end

    # Return a new `Vector` with `object` inserted before the first element,
    # moving the other elements upwards.
    #
    # @example
    #   Hamster::Vector["A", "B"].unshift("Z")
    #   # => Hamster::Vector["Z", "A", "B"]
    #
    # @param object [Object] The value to prepend
    # @return [Vector]
    def unshift(object)
      insert(0, object)
    end

    # Return a new `Vector` with the first element removed. If empty, return
    # `self`.
    #
    # @example
    #   Hamster::Vector["A", "B", "C"].shift  # => Hamster::Vector["B", "C"]
    #
    # @return [Vector]
    def shift
      delete_at(0)
    end

    # Call the given block once for each item in the vector, passing each
    # item from first to last successively to the block. If no block is given,
    # an `Enumerator` is returned instead.
    #
    # @example
    #   Hamster::Vector["A", "B", "C"].each { |e| puts "Element: #{e}" }
    #
    #   Element: A
    #   Element: B
    #   Element: C
    #   # => Hamster::Vector["A", "B", "C"]
    #
    # @return [self, Enumerator]
    def each(&block)
      return to_enum unless block_given?
      if structural?
        @root.each(&block)
      else
        traverse_depth_first(@root, @levels, &block)
      end
      self
    end

    # Call the given block once for each item in the vector, from last to
    # first.
    #
    # @example
    #   Hamster::Vector["A", "B", "C"].reverse_each { |e| puts "Element: #{e}" }
    #
    #   Element: C
    #   Element: B
    #   Element: A
    #
    # @return [self]
    def reverse_each(&block)
      return enum_for(:reverse_each) unless block_given?
      if structural?
        @root.reverse_each(&block)
      else
        reverse_traverse_depth_first(@root, @levels, &block)
      end
      self
    end

    # Return a new `Vector` containing all elements for which the given block returns
    # true.
    #
    # @example
    #   Hamster::Vector["Bird", "Cow", "Elephant"].select { |e| e.size >= 4 }
    #   # => Hamster::Vector["Bird", "Elephant"]
    #
    # @return [Vector]
    # @yield [element] Once for each element.
    def select
      return enum_for(:select) unless block_given?
      reduce(self.class.empty) { |vector, item| yield(item) ? vector.add(item) : vector }
    end
    alias :find_all :select
    alias :keep_if  :select

    # Return a new `Vector` with all items which are equal to `obj` removed.
    # `#==` is used for checking equality.
    #
    # @example
    #   Hamster::Vector["C", "B", "A", "B"].delete("B")  # => Hamster::Vector["C", "A"]
    #
    # @param obj [Object] The object to remove (every occurrence)
    # @return [Vector]
    def delete(obj)
      select { |item| item != obj }
    end

    # Invoke the given block once for each item in the vector, and return a new
    # `Vector` containing the values returned by the block. If no block is
    # provided, return an enumerator.
    #
    # @example
    #   Hamster::Vector[3, 2, 1].map { |e| e * e }  # => Hamster::Vector[9, 4, 1]
    #
    # @return [Vector, Enumerator]
    def map
      return enum_for(:map) if not block_given?
      return self if empty?
      self.class.new(super)
    end
    alias :collect :map

    # Return a new `Vector` with the concatenated results of running the block once
    # for every element in this `Vector`.
    #
    # @example
    #   Hamster::Vector[1, 2, 3].flat_map { |x| [x, -x] }
    #   # => Hamster::Vector[1, -1, 2, -2, 3, -3]
    #
    # @return [Vector]
    def flat_map
      return enum_for(:flat_map) if not block_given?
      return self if empty?
      self.class.new(super)
    end

    # Return a new `Vector` with the same elements as this one, but randomly permuted.
    #
    # @example
    #   Hamster::Vector[1, 2, 3, 4].shuffle  # => Hamster::Vector[4, 1, 3, 2]
    #
    # @return [Vector]
    def shuffle
      self.class.new(((array = to_a).frozen? ? array.shuffle : array.shuffle!).freeze)
    end

    # Return a new `Vector` with no duplicate elements, as determined by `#hash` and
    # `#eql?`. For each group of equivalent elements, only the first will be retained.
    #
    # @example
    #   Hamster::Vector["A", "B", "C", "B"].uniq      # => Hamster::Vector["A", "B", "C"]
    #   Hamster::Vector["a", "A", "b"].uniq(&:upcase) # => Hamster::Vector["a", "b"]
    #
    # @return [Vector]
    def uniq(&block)
      array = self.to_a
      return self.class.new(array.uniq(&block).freeze) if array.frozen?
      return self.class.new(array.freeze) if array.uniq!(&block)
      self
    end

    # Return a new `Vector` with the same elements as this one, but in reverse order.
    #
    # @example
    #   Hamster::Vector["A", "B", "C"].reverse  # => Hamster::Vector["C", "B", "A"]
    #
    # @return [Vector]
    def reverse
      self.class.new(((array = to_a).frozen? ? array.reverse : array.reverse!).freeze)
    end

    # Return a new `Vector` with the same elements, but rotated so that the one at
    # index `count` is the first element of the new vector. If `count` is positive,
    # the elements will be shifted left, and those shifted past the lowest position
    # will be moved to the end. If `count` is negative, the elements will be shifted
    # right, and those shifted past the last position will be moved to the beginning.
    #
    # @example
    #   v = Hamster::Vector["A", "B", "C", "D", "E", "F"]
    #   v.rotate(2)   # => Hamster::Vector["C", "D", "E", "F", "A", "B"]
    #   v.rotate(-1)  # => Hamster::Vector["F", "A", "B", "C", "D", "E"]
    #
    # @param count [Integer] The number of positions to shift items by
    # @return [Vector]
    def rotate(count = 1)
      return self if (count % @size) == 0
      self.class.new(((array = to_a).frozen? ? array.rotate(count) : array.rotate!(count)).freeze)
    end

    # Return a new `Vector` with all nested vectors and arrays recursively "flattened
    # out". That is, their elements inserted into the new `Vector` in the place where
    # the nested array/vector originally was. If an optional `level` argument is
    # provided, the flattening will only be done recursively that number of times.
    # A `level` of 0 means not to flatten at all, 1 means to only flatten nested
    # arrays/vectors which are directly contained within this `Vector`.
    #
    # @example
    #   v = Hamster::Vector["A", Hamster::Vector["B", "C", Hamster::Vector["D"]]]
    #   v.flatten(1)
    #   # => Hamster::Vector["A", "B", "C", Hamster::Vector["D"]]
    #   v.flatten
    #   # => Hamster::Vector["A", "B", "C", "D"]
    #
    # @param level [Integer] The depth to which flattening should be applied
    # @return [Vector]
    def flatten(level = -1)
      return self if level == 0
      array = self.to_a
      if array.frozen?
        self.class.new(array.flatten(level).freeze)
      elsif array.flatten!(level) # returns nil if no changes were made
        self.class.new(array.freeze)
      else
        self
      end
    end

    # Return a new `Vector` built by concatenating this one with `other`. `other`
    # can be any object which is convertible to an `Array` using `#to_a`.
    #
    # @example
    #   Hamster::Vector["A", "B", "C"] + ["D", "E"]
    #   # => Hamster::Vector["A", "B", "C", "D", "E"]
    #
    # @param other [Enumerable] The collection to concatenate onto this vector
    # @return [Vector]
    def +(other)
      return concat_vector(other) if other.is_a?(Vector)
      concat_vector(self.class.new(other.to_a))
    end
    alias :concat :+

    # Combine two vectors by "zipping" them together. `others` should be arrays
    # and/or vectors. The corresponding elements from this `Vector` and each of
    # `others` (that is, the elements with the same indices) will be gathered
    # into arrays.
    #
    # If `others` contains fewer elements than this vector, `nil` will be used
    # for padding.
    #
    # @overload zip(*others)
    #   Return a new vector containing the new arrays.
    #
    #   @return [Vector]
    #
    # @overload zip(*others)
    #   @yield [pair] once for each array
    #   @return [nil]
    #
    # @example
    #   v1 = Hamster::Vector["A", "B", "C"]
    #   v2 = Hamster::Vector[1, 2]
    #   v1.zip(v2)
    #   # => Hamster::Vector[["A", 1], ["B", 2], ["C", nil]]
    #
    # @param others [Array] The arrays/vectors to zip together with this one
    # @return [Vector]
    def zip(*others)
      if block_given?
        super
      else
        self.class.new(super)
      end
    end

    # Return a new `Vector` with the same items, but sorted.
    #
    # @overload sort
    #   Compare elements with their natural sort key (`#<=>`).
    #
    #   @example
    #     Hamster::Vector["Elephant", "Dog", "Lion"].sort
    #     # => Hamster::Vector["Dog", "Elephant", "Lion"]
    #
    # @overload sort
    #   Uses the block as a comparator to determine sorted order.
    #
    #   @yield [a, b] Any number of times with different pairs of elements.
    #   @yieldreturn [Integer] Negative if the first element should be sorted
    #                          lower, positive if the latter element, or 0 if
    #                          equal.
    #   @example
    #     Hamster::Vector["Elephant", "Dog", "Lion"].sort { |a,b| a.size <=> b.size }
    #     # => Hamster::Vector["Dog", "Lion", "Elephant"]
    #
    # @return [Vector]
    def sort
      self.class.new(super)
    end

    # Return a new `Vector` with the same items, but sorted. The sort order is
    # determined by mapping the items through the given block to obtain sort
    # keys, and then sorting the keys according to their natural sort order
    # (`#<=>`).
    #
    # @yield [element] Once for each element.
    # @yieldreturn a sort key object for the yielded element.
    # @example
    #   Hamster::Vector["Elephant", "Dog", "Lion"].sort_by { |e| e.size }
    #   # => Hamster::Vector["Dog", "Lion", "Elephant"]
    #
    # @return [Vector]
    def sort_by
      self.class.new(super)
    end

    # Drop the first `n` elements and return the rest in a new `Vector`.
    #
    # @example
    #   Hamster::Vector["A", "B", "C", "D", "E", "F"].drop(2)
    #   # => Hamster::Vector["C", "D", "E", "F"]
    #
    # @param n [Integer] The number of elements to remove
    # @return [Vector]
    # @raise ArgumentError if `n` is negative.
    def drop(n)
      return self if n == 0
      return self.class.empty if n >= @size
      raise ArgumentError, "attempt to drop negative size" if n < 0
      subsequence(n, @size - n)
    end

    # Return only the first `n` elements in a new `Vector`.
    #
    # @example
    #   Hamster::Vector["A", "B", "C", "D", "E", "F"].take(4)
    #   # => Hamster::Vector["A", "B", "C", "D"]
    #
    # @param n [Integer] The number of elements to retain
    # @return [Vector]
    def take(n)
      return self if n >= @size
      raise ArgumentError, "attempt to take negative size" if n < 0
      subsequence(0, n)
    end

    # Drop elements up to, but not including, the first element for which the
    # block returns `nil` or `false`. Gather the remaining elements into a new
    # `Vector`. If no block is given, an `Enumerator` is returned instead.
    #
    # @example
    #   Hamster::Vector[1, 3, 5, 7, 6, 4, 2].drop_while { |e| e < 5 }
    #   # => Hamster::Vector[5, 7, 6, 4, 2]
    #
    # @return [Vector, Enumerator]
    def drop_while
      return enum_for(:drop_while) if not block_given?
      self.class.new(super)
    end

    # Gather elements up to, but not including, the first element for which the
    # block returns `nil` or `false`, and return them in a new `Vector`. If no block
    # is given, an `Enumerator` is returned instead.
    #
    # @example
    #   Hamster::Vector[1, 3, 5, 7, 6, 4, 2].take_while { |e| e < 5 }
    #   # => Hamster::Vector[1, 3]
    #
    # @return [Vector, Enumerator]
    def take_while
      return enum_for(:take_while) if not block_given?
      self.class.new(super)
    end

    # Repetition. Return a new `Vector` built by concatenating `times` copies
    # of this one together.
    #
    # @example
    #   Hamster::Vector["A", "B"] * 3
    #   # => Hamster::Vector["A", "B", "A", "B", "A", "B"]
    #
    # @param times [Integer] The number of times to repeat the elements in this vector
    # @return [Vector]
    def *(times)
      return self.class.empty if times == 0
      return self if times == 1
      result = (to_a * times)
      result.is_a?(Array) ? self.class.new(result) : result
    end

    # Replace a range of indexes with the given object.
    #
    # @overload fill(object)
    #   Return a new `Vector` of the same size, with every index set to
    #   `object`.
    #
    #   @param [Object] object Fill value.
    #   @example
    #     Hamster::Vector["A", "B", "C", "D", "E", "F"].fill("Z")
    #     # => Hamster::Vector["Z", "Z", "Z", "Z", "Z", "Z"]
    #
    # @overload fill(object, index)
    #   Return a new `Vector` with all indexes from `index` to the end of the
    #   vector set to `object`.
    #
    #   @param [Object] object Fill value.
    #   @param [Integer] index Starting index. May be negative.
    #   @example
    #     Hamster::Vector["A", "B", "C", "D", "E", "F"].fill("Z", 3)
    #     # => Hamster::Vector["A", "B", "C", "Z", "Z", "Z"]
    #
    # @overload fill(object, index, length)
    #   Return a new `Vector` with `length` indexes, beginning from `index`,
    #   set to `object`. Expands the `Vector` if `length` would extend beyond
    #   the current length.
    #
    #   @param [Object] object Fill value.
    #   @param [Integer] index Starting index. May be negative.
    #   @param [Integer] length
    #   @example
    #     Hamster::Vector["A", "B", "C", "D", "E", "F"].fill("Z", 3, 2)
    #     # => Hamster::Vector["A", "B", "C", "Z", "Z", "F"]
    #     Hamster::Vector["A", "B"].fill("Z", 1, 5)
    #     # => Hamster::Vector["A", "Z", "Z", "Z", "Z", "Z"]
    #
    # @return [Vector]
    # @raise [IndexError] if index is out of negative range.
    def fill(object, index = 0, length = nil)
      raise IndexError if index < -@size
      index += @size if index < 0
      length ||= @size - index # to the end of the array, if no length given

      if index < @size
        kept = [length, @size - index].min
        prefix = subsequence(0, index)
        replacement = self.class.new([object] * kept)
        extension = self.class.new([object] * (length - kept))
        suffix = subsequence(index + kept, @size - index - kept)
        prefix + replacement + extension + suffix
      else
        padding = Array.new(index - @size, nil).concat(Array.new(length, object))
        self + self.class.new(padding)
      end
    end

    # When invoked with a block, yields all combinations of length `n` of items
    # from the `Vector`, and then returns `self`. There is no guarantee about
    # which order the combinations will be yielded.
    #
    # If no block is given, an `Enumerator` is returned instead.
    #
    # @example
    #   v = Hamster::Vector[5, 6, 7, 8]
    #   v.combination(3) { |c| puts "Combination: #{c}" }
    #
    #   Combination: [5, 6, 7]
    #   Combination: [5, 6, 8]
    #   Combination: [5, 7, 8]
    #   Combination: [6, 7, 8]
    #   #=> Hamster::Vector[5, 6, 7, 8]
    #
    # @return [self, Enumerator]
    def combination(n)
      return enum_for(:combination, n) if not block_given?
      return self if n < 0 || @size < n
      if n == 0
        yield []
      elsif n == 1
        each { |item| yield [item] }
      elsif n == @size
        yield self.to_a
      else
        combos = lambda do |result,index,remaining|
          while @size - index > remaining
            if remaining == 1
              yield result.dup << get(index)
            else
              combos[result.dup << get(index), index+1, remaining-1]
            end
            index += 1
          end
          index.upto(@size-1) { |i| result << get(i) }
          yield result
        end
        combos[[], 0, n]
      end
      self
    end

    # When invoked with a block, yields all repeated combinations of length `n` of
    # items from the `Vector`, and then returns `self`. A "repeated combination" is
    # one in which any item from the `Vector` can appear consecutively any number of
    # times.
    #
    # There is no guarantee about which order the combinations will be yielded in.
    #
    # If no block is given, an `Enumerator` is returned instead.
    #
    # @example
    #   v = Hamster::Vector[5, 6, 7, 8]
    #   v.repeated_combination(2) { |c| puts "Combination: #{c}" }
    #
    #   Combination: [5, 5]
    #   Combination: [5, 6]
    #   Combination: [5, 7]
    #   Combination: [5, 8]
    #   Combination: [6, 6]
    #   Combination: [6, 7]
    #   Combination: [6, 8]
    #   Combination: [7, 7]
    #   Combination: [7, 8]
    #   Combination: [8, 8]
    #   # => Hamster::Vector[5, 6, 7, 8]
    #
    # @return [self, Enumerator]
    def repeated_combination(n)
      return enum_for(:repeated_combination, n) if not block_given?
      if n < 0
        # yield nothing
      elsif n == 0
        yield []
      elsif n == 1
        each { |item| yield [item] }
      elsif @size == 0
        # yield nothing
      else
        combos = lambda do |result,index,remaining|
          while index < @size-1
            if remaining == 1
              yield result.dup << get(index)
            else
              combos[result.dup << get(index), index, remaining-1]
            end
            index += 1
          end
          item = get(index)
          remaining.times { result << item }
          yield result
        end
        combos[[], 0, n]
      end
      self
    end

    # Yields all permutations of length `n` of items from the `Vector`, and then
    # returns `self`. If no length `n` is specified, permutations of all elements
    # will be yielded.
    #
    # There is no guarantee about which order the permutations will be yielded in.
    #
    # If no block is given, an `Enumerator` is returned instead.
    #
    # @example
    #   v = Hamster::Vector[5, 6, 7]
    #   v.permutation(2) { |p| puts "Permutation: #{p}" }
    #
    #   Permutation: [5, 6]
    #   Permutation: [5, 7]
    #   Permutation: [6, 5]
    #   Permutation: [6, 7]
    #   Permutation: [7, 5]
    #   Permutation: [7, 6]
    #   # => Hamster::Vector[5, 6, 7]
    #
    # @return [self, Enumerator]
    def permutation(n = @size)
      return enum_for(:permutation, n) if not block_given?
      if n < 0 || @size < n
        # yield nothing
      elsif n == 0
        yield []
      elsif n == 1
        each { |item| yield [item] }
      else
        used, result = [], []
        perms = lambda do |index|
          0.upto(@size-1) do |i|
            if !used[i]
              result[index] = get(i)
              if index < n-1
                used[i] = true
                perms[index+1]
                used[i] = false
              else
                yield result.dup
              end
            end
          end
        end
        perms[0]
      end
      self
    end

    # When invoked with a block, yields all repeated permutations of length `n` of
    # items from the `Vector`, and then returns `self`. A "repeated permutation" is
    # one where any item from the `Vector` can appear any number of times, and in
    # any position (not just consecutively)
    #
    # If no length `n` is specified, permutations of all elements will be yielded.
    # There is no guarantee about which order the permutations will be yielded in.
    #
    # If no block is given, an `Enumerator` is returned instead.
    #
    # @example
    #   v = Hamster::Vector[5, 6, 7]
    #   v.repeated_permutation(2) { |p| puts "Permutation: #{p}" }
    #
    #   Permutation: [5, 5]
    #   Permutation: [5, 6]
    #   Permutation: [5, 7]
    #   Permutation: [6, 5]
    #   Permutation: [6, 6]
    #   Permutation: [6, 7]
    #   Permutation: [7, 5]
    #   Permutation: [7, 6]
    #   Permutation: [7, 7]
    #   # => Hamster::Vector[5, 6, 7]
    #
    # @return [self, Enumerator]
    def repeated_permutation(n = @size)
      return enum_for(:repeated_permutation, n) if not block_given?
      if n < 0
        # yield nothing
      elsif n == 0
        yield []
      elsif n == 1
        each { |item| yield [item] }
      else
        result = []
        perms = lambda do |index|
          0.upto(@size-1) do |i|
            result[index] = get(i)
            if index < n-1
              perms[index+1]
            else
              yield result.dup
            end
          end
        end
        perms[0]
      end
      self
    end

    # Cartesian product or multiplication.
    #
    # @overload product(*vectors)
    #   Return a `Vector` of all combinations of elements from this `Vector` and each
    #   of the given vectors or arrays. The length of the returned `Vector` is the product
    #   of `self.size` and the size of each argument vector or array.
    #   @example
    #     v1 = Hamster::Vector[1, 2, 3]
    #     v2 = Hamster::Vector["A", "B"]
    #     v1.product(v2)
    #     # => [[1, "A"], [1, "B"], [2, "A"], [2, "B"], [3, "A"], [3, "B"]]
    # @overload product
    #   Return the result of multiplying all the items in this `Vector` together.
    #
    #   @example
    #     Hamster::Vector[1, 2, 3, 4, 5].product  # => 120
    #
    # @return [Vector]
    def product(*vectors)
      # if no vectors passed, return "product" as in result of multiplying all items
      return super if vectors.empty?

      vectors.unshift(self)

      if vectors.any?(&:empty?)
        return block_given? ? self : []
      end

      counters = Array.new(vectors.size, 0)

      bump_counters = lambda do
        i = vectors.size-1
        counters[i] += 1
        while counters[i] == vectors[i].size
          counters[i] = 0
          i -= 1
          return true if i == -1 # we are done
          counters[i] += 1
        end
        false # not done yet
      end
      build_array = lambda do
        array = []
        counters.each_with_index { |index,i| array << vectors[i][index] }
        array
      end

      if block_given?
        while true
          yield build_array[]
          return self if bump_counters[]
        end
      else
        result = []
        while true
          result << build_array[]
          return result if bump_counters[]
        end
      end
    end

    # Assume all elements are vectors or arrays and transpose the rows and columns.
    # In other words, take the first element of each nested vector/array and gather
    # them together into a new `Vector`. Do likewise for the second, third, and so on
    # down to the end of each nested vector/array. Gather all the resulting `Vectors`
    # into a new `Vector` and return it.
    #
    # This operation is closely related to {#zip}. The result is almost the same as
    # calling {#zip} on the first nested vector/array with the others supplied as
    # arguments.
    #
    # @example
    #   Hamster::Vector[["A", 10], ["B", 20], ["C", 30]].transpose
    #   # => Hamster::Vector[Hamster::Vector["A", "B", "C"], Hamster::Vector[10, 20, 30]]
    #
    # @return [Vector]
    # @raise [IndexError] if elements are not of the same size.
    # @raise [TypeError] if an element can not be implicitly converted to an array (using `#to_ary`)
    def transpose
      return self.class.empty if empty?
      result = Array.new(first.size) { [] }

      0.upto(@size-1) do |i|
        source = get(i)
        if source.size != result.size
          raise IndexError, "element size differs (#{source.size} should be #{result.size})"
        end

        0.upto(result.size-1) do |j|
          result[j].push(source[j])
        end
      end

      result.map! { |a| self.class.new(a) }
      self.class.new(result)
    rescue NoMethodError
      if any? { |x| !x.respond_to?(:size) || !x.respond_to?(:[]) }
        bad = find { |x| !x.respond_to?(:size) || !x.respond_to?(:[]) }
        raise TypeError, "'#{bad.inspect}' must respond to #size and #[] to be transposed"
      else
        raise
      end
    end

    # Finds a value from this `Vector` which meets the condition defined by the
    # provided block, using a binary search. The vector must already be sorted
    # with respect to the block.  See Ruby's `Array#bsearch` for details,
    # behaviour is equivalent.
    #
    # @example
    #   v = Hamster::Vector[1, 3, 5, 7, 9, 11, 13]
    #   # Block returns true/false for exact element match:
    #   v.bsearch { |e| e > 4 }      # => 5
    #   # Block returns number to match an element in 4 <= e <= 7:
    #   v.bsearch { |e| 1 - e / 4 }  # => 7
    #
    # @yield Once for at most `log n` elements, where `n` is the size of the
    #        vector. The exact elements and ordering are undefined.
    # @yieldreturn [Boolean] `true` if this element matches the criteria, `false` otherwise.
    # @yieldreturn [Integer] See `Array#bsearch` for details.
    # @yieldparam [Object] element element to be evaluated
    # @return [Object] The matched element, or `nil` if none found.
    # @raise TypeError if the block returns a non-numeric, non-boolean, non-nil
    #                  value.
    def bsearch
      return enum_for(:bsearch) if not block_given?
      low, high, result = 0, @size, nil
      while low < high
        mid = (low + ((high - low) >> 1))
        val = get(mid)
        v   = yield val
        if v.is_a? Numeric
          if v == 0
            return val
          elsif v > 0
            high = mid
          else
            low = mid + 1
          end
        elsif v == true
          result = val
          high = mid
        elsif !v
          low = mid + 1
        else
          raise TypeError, "wrong argument type #{v.class} (must be numeric, true, false, or nil)"
        end
      end
      result
    end

    # Return an empty `Vector` instance, of the same class as this one. Useful if you
    # have multiple subclasses of `Vector` and want to treat them polymorphically.
    #
    # @return [Vector]
    def clear
      self.class.empty
    end

    # Return a randomly chosen item from this `Vector`. If the vector is empty, return `nil`.
    #
    # @example
    #   Hamster::Vector[1, 2, 3, 4, 5].sample  # => 2
    #
    # @return [Object]
    def sample
      get(rand(@size))
    end

    # Return a new `Vector` with only the elements at the given `indices`, in the
    # order specified by `indices`. If any of the `indices` do not exist, `nil`s will
    # appear in their places.
    #
    # @example
    #   v = Hamster::Vector["A", "B", "C", "D", "E", "F"]
    #   v.values_at(2, 4, 5)   # => Hamster::Vector["C", "E", "F"]
    #
    # @param indices [Array] The indices to retrieve and gather into a new `Vector`
    # @return [Vector]
    def values_at(*indices)
      self.class.new(indices.map { |i| get(i) }.freeze)
    end

    # Find the index of an element, starting from the end of the vector.
    # Returns `nil` if no element is found.
    #
    # @overload rindex(obj)
    #   Return the index of the last element which is `#==` to `obj`.
    #
    #   @example
    #     v = Hamster::Vector[7, 8, 9, 7, 8, 9]
    #     v.rindex(8) # => 4
    #
    # @overload rindex
    #   Return the index of the last element for which the block returns true.
    #
    #   @yield [element] Once for each element, last to first, until the block
    #                    returns true.
    #   @example
    #     v = Hamster::Vector[7, 8, 9, 7, 8, 9]
    #     v.rindex { |e| e.even? }  # => 4
    #
    # @return [Integer]
    def rindex(obj = (missing_arg = true))
      i = @size - 1
      if missing_arg
        if block_given?
          reverse_each { |item| return i if yield item; i -= 1 }
          nil
        else
          enum_for(:rindex)
        end
      else
        reverse_each { |item| return i if item == obj; i -= 1 }
        nil
      end
    end

    # Assumes all elements are nested, indexable collections, and searches through them,
    # comparing `obj` with the first element of each nested collection. Return the
    # first nested collection which matches, or `nil` if none is found.
    # Behaviour is undefined when elements do not meet assumptions (i.e. are
    # not indexable collections).
    #
    # @example
    #   v = Hamster::Vector[["A", 10], ["B", 20], ["C", 30]]
    #   v.assoc("B")  # => ["B", 20]
    #
    # @param obj [Object] The object to search for
    # @return [Object]
    def assoc(obj)
      each do |array|
        next if !array.respond_to?(:[])
        return array if obj == array[0]
      end
      nil
    end

    # Assumes all elements are nested, indexable collections, and searches through them,
    # comparing `obj` with the second element of each nested collection. Return
    # the first nested collection which matches, or `nil` if none is found.
    # Behaviour is undefined when elements do not meet assumptions (i.e. are
    # not indexable collections).
    #
    # @example
    #   v = Hamster::Vector[["A", 10], ["B", 20], ["C", 30]]
    #   v.rassoc(20)  # => ["B", 20]
    #
    # @param obj [Object] The object to search for
    # @return [Object]
    def rassoc(obj)
      each do |array|
        next if !array.respond_to?(:[])
        return array if obj == array[1]
      end
      nil
    end

    # Return an `Array` with the same elements, in the same order. The returned
    # `Array` may or may not be frozen.
    #
    # @return [Array]
    def to_a
      if structural?
        @root.to_a
      elsif @levels == 0
        # When initializing a Vector with 32 or less items, we always make
        # sure @root is frozen, so we can return it directly here
        @root
      else
        flatten_node(@root, @levels * BITS_PER_LEVEL, [])
      end
    end
    alias :to_ary :to_a

    # Return true if `other` has the same type and contents as this `Vector`.
    #
    # @param other [Object] The collection to compare with
    # @return [Boolean]
    def eql?(other)
      return true if other.equal?(self)
      return false unless instance_of?(other.class) && @size == other.size
      return structural_eql?(other) if structural? || other.instance_variable_get(:@root).is_a?(StructuralNode)
      @root.eql?(other.instance_variable_get(:@root))
    end

    # See `Object#hash`.
    # @return [Integer]
    def hash
      reduce(0) { |hash, item| (hash << 5) - hash + item.hash }
    end

    # @return [::Array]
    # @private
    def marshal_dump
      to_a
    end

    # @private
    def marshal_load(array)
      initialize(array.freeze)
    end

    private

    def structural?
      @root.is_a?(StructuralNode)
    end

    def canonical_structural_node
      CanonicalNode.new(@levels, @root, @size)
    end

    def structural_alloc(node, size)
      vector = self.class.alloc(node, size, node.height)
      vector.freeze
    end

    def concat_vector(other)
      return other if @size == 0
      return self if other.size == 0

      left = structural? ? @root : canonical_structural_node
      right = other.instance_variable_get(:@root)
      right = CanonicalNode.new(
        other.instance_variable_get(:@levels),
        right,
        other.size
      ) unless right.is_a?(StructuralNode)

      target_height = [left.height, right.height].max
      left = StructuralNode.raise_to(left, target_height)
      right = StructuralNode.raise_to(right, target_height)
      nodes = concat_nodes(left, right)
      node = nodes.size == 1 ? nodes.first : InternalNode.new(target_height + 1, nodes)
      structural_alloc(node, @size + other.size)
    end

    def concat_nodes(left, right)
      if left.height == 0
        items = left.to_a.concat(right.to_a)
        if items.size <= BLOCK_SIZE
          [LeafNode.new(items.freeze)]
        else
          [LeafNode.new(items.take(BLOCK_SIZE).freeze),
           LeafNode.new(items[BLOCK_SIZE..-1].freeze)]
        end
      else
        boundary = concat_nodes(left.children.last, right.children.first)
        children = left.children[0...-1] + boundary + right.children[1..-1]
        if children.size <= BLOCK_SIZE
          [InternalNode.new(left.height, children)]
        else
          split_nodes(left.height, children)
        end
      end
    end

    def split_nodes(height, children)
      boundary = concat_nodes(children[BLOCK_SIZE - 1], children[BLOCK_SIZE])
      left = children.take(BLOCK_SIZE - 1) + boundary[0, 1]
      right = (boundary.size == 1 ? [] : boundary[1..-1]) + children[(BLOCK_SIZE + 1)..-1]
      result = [InternalNode.new(height, left)]
      result << InternalNode.new(height, right) unless right.empty?
      result
    end

    def structural_append(item)
      concat_vector(self.class.new([item]))
    end

    def structural_eql?(other)
      left = structural? ? @root : canonical_structural_node
      right_root = other.instance_variable_get(:@root)
      right = right_root.is_a?(StructuralNode) ? right_root : CanonicalNode.new(
        other.instance_variable_get(:@levels),
        right_root,
        other.size
      )

      left_values = left.each
      right_values = right.each
      loop do
        return false unless left_values.next == right_values.next
      end
      true
    rescue StopIteration
      true
    end

    def traverse_depth_first(node, level, &block)
      return node.each(&block) if level == 0
      node.each { |child| traverse_depth_first(child, level - 1, &block) }
    end

    def reverse_traverse_depth_first(node, level, &block)
      return node.reverse_each(&block) if level == 0
      node.reverse_each { |child| reverse_traverse_depth_first(child, level - 1, &block) }
    end

    def leaf_node_for(node, bitshift, index)
      while bitshift > 0
        node = node[(index >> bitshift) & INDEX_MASK]
        bitshift -= BITS_PER_LEVEL
      end
      node
    end

    def update_root(index, item)
      if structural?
        if index < @size
          updated = @root.put(index, item)
          return self if updated.equal?(@root)
          return structural_alloc(updated, @size)
        end
        appended = structural_append(item)
        return appended if index == @size

        padding = self.class.new(Array.new(index - @size, nil) << item)
        return self + padding
      end

      root, levels = @root, @levels
      while index >= (1 << (BITS_PER_LEVEL * (levels + 1)))
        root = [root].freeze
        levels += 1
      end
      new_root = update_leaf_node(root, levels * BITS_PER_LEVEL, index, item)
      if new_root.equal?(root)
        self
      else
        self.class.alloc(new_root, @size > index ? @size : index + 1, levels)
      end
    end

    def update_leaf_node(node, bitshift, index, item)
      slot_index = (index >> bitshift) & INDEX_MASK
      if bitshift > 0
        old_child = node[slot_index] || []
        item = update_leaf_node(old_child, bitshift - BITS_PER_LEVEL, index, item)
      end
      existing_item = node[slot_index]
      if existing_item.equal?(item)
        node
      else
        node.dup.tap { |n| n[slot_index] = item }.freeze
      end
    end

    def flatten_node(node, bitshift, result)
      if bitshift == 0
        result.concat(node)
      elsif bitshift == BITS_PER_LEVEL
        node.each { |a| result.concat(a) }
      else
        bitshift -= BITS_PER_LEVEL
        node.each { |a| flatten_node(a, bitshift, result) }
      end
      result
    end

    def subsequence(from, length)
      return nil if from > @size || from < 0 || length < 0
      length = @size - from if @size < from + length
      return self.class.empty if length == 0
      return self if from == 0 && length == @size

      if structural?
        node = @root.slice_range(from, from + length)
        structural_alloc(node, length)
      else
        node = canonical_structural_node.slice_range(from, from + length)
        structural_alloc(node, length)
      end
    end
  end

  # The canonical empty `Vector`. Returned by `Vector[]` when
  # invoked with no arguments; also returned by `Vector.empty`. Prefer using this
  # one rather than creating many empty vectors using `Vector.new`.
  #
  # @private
  EmptyVector = Hamster::Vector.empty
end
