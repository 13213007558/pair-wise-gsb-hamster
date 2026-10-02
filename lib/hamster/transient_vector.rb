require "hamster/transient"

module Hamster
  # A `TransientVector` is a short-lived, mutable editing session over a
  # {Hamster::Vector}. It exists to make bulk updates efficient: instead of
  # building a new immutable vector for every single change, a batch of
  # changes is applied in place, and a single immutable `Hamster::Vector` is
  # produced at the end with {#persistent!}.
  #
  #     editor = vector.transient
  #     10_000.times { |i| editor.push(i) }
  #     new_vector = editor.persistent!
  #
  # Or, using the block form, which persists automatically:
  #
  #     new_vector = vector.transient do |editor|
  #       editor.put(0, :changed)
  #       editor.pop
  #     end
  #
  # Safety rules:
  #
  # * A transient may only be used by the thread which created it.
  # * Once {#persistent!} has been called, the session is over: any further
  #   use raises {Transient::InactiveError}.
  # * The immutable vector the transient was created from (and any vector
  #   previously derived from it) is never modified, even if the editing
  #   session is abandoned midway, e.g. because of an exception.
  #
  class TransientVector
    include Transient

    # @private
    BLOCK_SIZE = 32
    # @private
    INDEX_MASK = BLOCK_SIZE - 1
    # @private
    BITS_PER_LEVEL = 5

    # @private
    def initialize(klass, root, size, levels)
      @klass = klass
      @root = root
      @size = size
      @levels = levels
      initialize_transient!
    end

    # Return the number of items currently in the transient.
    #
    # @return [Integer]
    def size
      ensure_transient_usable!
      @size
    end
    alias :length :size

    # Return `true` if the transient contains no items.
    #
    # @return [Boolean]
    def empty?
      size == 0
    end

    # Retrieve the item at the given index. Negative indexes count back from
    # the end. Returns `nil` if out of range.
    #
    # @param index [Integer] The index to look up
    # @return [Object]
    def get(index)
      ensure_transient_usable!
      return nil if @size == 0
      index += @size if index < 0
      return nil if index >= @size || index < 0
      node = @root
      bitshift = @levels * BITS_PER_LEVEL
      while bitshift > 0
        node = node[(index >> bitshift) & INDEX_MASK]
        bitshift -= BITS_PER_LEVEL
      end
      node[index & INDEX_MASK]
    end
    alias :[] :get

    # Replace the item at the given index. If `index` is greater than the
    # length of the vector, it is padded with `nil`s to the correct size.
    # Returns `self` so calls can be chained.
    #
    # @param index [Integer] The index to update. May be negative.
    # @param item [Object] The object to store at that position
    # @yield [item] The previously stored item
    # @yieldreturn [Object] The new item to store
    # @return [self]
    def put(index, item = yield(get(index)))
      ensure_transient_usable!
      raise IndexError, "index #{index} outside of vector bounds" if index < -@size
      index += @size if index < 0
      push(nil) while index > @size
      ensure_capacity_for(index)
      ensure_editable_root!
      set_transient(@root, @levels * BITS_PER_LEVEL, index, item)
      @size = index + 1 if index >= @size
      self
    end
    alias :set :put

    # Replace the item at the given index.
    #
    # @param index [Integer] The index to update. May be negative.
    # @param item [Object] The object to store at that position
    # @return [Object] the stored item
    def store(index, item)
      put(index, item)
      item
    end
    alias :[]= :store

    # Add an item after the last occupied position.
    #
    # @param item [Object] The object to append
    # @return [self]
    def push(item)
      ensure_transient_usable!
      ensure_capacity_for(@size)
      ensure_editable_root!
      set_transient(@root, @levels * BITS_PER_LEVEL, @size, item)
      @size += 1
      self
    end
    alias :add :push
    alias :<< :push

    # Remove the last item and return it. Returns `nil` if empty.
    #
    # @return [Object]
    def pop
      ensure_transient_usable!
      return nil if @size == 0
      index = @size - 1
      if index == 0
        item = get(0)
        @size = 0
        @root = []
        @levels = 0
        return item
      end
      @size -= 1
      ensure_editable_root!
      item = pop_transient(@root, @levels * BITS_PER_LEVEL, index)
      shrink_root!
      item
    end

    # Call the block once for each item in the transient.
    #
    # @yield [item]
    # @return [self]
    def each(&block)
      ensure_transient_usable!
      return to_enum unless block_given?
      traverse(@root, @levels, &block)
      self
    end

    # End this editing session and return an immutable `Hamster::Vector`
    # with the accumulated changes. The transient must not be used
    # afterwards: any further method call will raise
    # {Transient::InactiveError}.
    #
    # @return [Hamster::Vector]
    def persistent!
      ensure_transient_usable!
      invalidate_transient!
      freeze_node(@root, @levels)
      @klass.alloc(@root, @size, @levels)
    end

    private

    def ensure_capacity_for(index)
      while index >= (1 << (BITS_PER_LEVEL * (@levels + 1)))
        @root = tag_node([@root])
        @levels += 1
      end
    end

    # Make sure the root node is owned by this session, copying it first if
    # it is still shared with an immutable vector.
    def ensure_editable_root!
      @root = editable_node(@root)
    end

    def node_owned?(node)
      node.instance_variable_get(:@transient_token).equal?(@transient_token)
    end

    def tag_node(node)
      node.instance_variable_set(:@transient_token, @transient_token)
      node
    end

    # Return +node+ if this session owns it, else a mutable, owned copy of
    # it. Shared nodes are never mutated in place.
    def editable_node(node)
      node_owned?(node) ? node : tag_node(node.dup)
    end

    def set_transient(node, bitshift, index, item)
      slot_index = (index >> bitshift) & INDEX_MASK
      if bitshift > 0
        child = node[slot_index]
        child = child ? editable_node(child) : tag_node([])
        node[slot_index] = child
        set_transient(child, bitshift - BITS_PER_LEVEL, index, item)
      else
        node[slot_index] = item
      end
    end

    def pop_transient(node, bitshift, index)
      slot_index = (index >> bitshift) & INDEX_MASK
      if bitshift == 0
        node.pop
      else
        child = editable_node(node[slot_index])
        node[slot_index] = child
        item = pop_transient(child, bitshift - BITS_PER_LEVEL, index)
        node.pop if child.empty?
        item
      end
    end

    def shrink_root!
      while @levels > 0 && @root.size == 1
        @root = @root[0]
        @levels -= 1
      end
    end

    def traverse(node, level, &block)
      if level == 0
        node.each(&block)
      else
        node.each { |child| traverse(child, level - 1, &block) if child }
      end
    end

    # Freeze every node owned by this session, restoring the immutability
    # invariant of the returned vector. Nodes shared with other vectors are
    # already frozen.
    def freeze_node(node, level)
      return if node.frozen?
      if level > 0
        node.each { |child| freeze_node(child, level - 1) if child.is_a?(Array) }
      end
      node.freeze
    end
  end
end
