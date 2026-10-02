require "hamster/undefined"

module Hamster
  # Raised when a transient editor is used after it has been sealed (by
  # sealing explicitly, or by leaving the block form of +Hash#transient+ or
  # +Vector#transient+), or from a thread other than the one which created
  # it.
  class TransientError < StandardError; end

  # A short-lived, mutable editor for a {Hamster::Hash}, obtained from
  # {Hash#transient}. Within a single editing session, updates are made in
  # place on nodes which are exclusively owned by the session; nodes still
  # shared with the source hash (or any other collection) are copied on
  # first touch, so the original and all its derivatives remain untouched.
  #
  # Unlike {Hamster::MutableHash}, which repeatedly swaps one persistent
  # hash for another, a +TransientHash+ performs no persistent updates at
  # all until it is sealed: call {#persistent!} exactly once to obtain an
  # immutable {Hamster::Hash} again.
  #
  # An editor is confined to the thread which created it, and becomes
  # unusable as soon as it is sealed. Any access after sealing, reads
  # included, raises {TransientError}. If the block form of
  # {Hash#transient} exits because of an exception, the editor is
  # invalidated, so a half-finished session cannot be kept alive (and
  # written to) through a saved reference.
  class TransientHash
    # @private
    def initialize(hash_class, trie, default)
      @hash_class = hash_class
      @trie = trie
      @default = default
      @token = Object.new
      @thread = Thread.current
      @sealed = false
    end

    # Return the number of key/value pairs in the hash under construction.
    #
    # @return [Integer]
    def size
      check_valid!
      @trie.size
    end

    # Return +true+ if the hash under construction contains no key/value pairs.
    #
    # @return [Boolean]
    def empty?
      check_valid!
      @trie.empty?
    end

    # Return +true+ if the given key is present in the hash under construction.
    #
    # @return [Boolean]
    def key?(key)
      check_valid!
      @trie.key?(key)
    end
    alias :has_key? :key?
    alias :include? :key?
    alias :member? :key?

    # Retrieve the value associated with the given key. If not found, return
    # +nil+ or, if the hash was created with a default block, the result of
    # evaluating it.
    #
    # @return [Object]
    def get(key)
      check_valid!
      entry = @trie.get(key)
      if entry
        entry[1]
      elsif @default
        @default.call(key)
      end
    end
    alias :[] :get

    # Retrieve the value associated with the given key, following the same
    # rules as {Hash#fetch}.
    #
    # @return [Object]
    def fetch(key, default = Undefined)
      check_valid!
      entry = @trie.get(key)
      if entry
        entry[1]
      elsif block_given?
        yield(key)
      elsif default != Undefined
        default
      elsif @default
        @default.call(key)
      else
        raise KeyError, "key not found: #{key.inspect}"
      end
    end

    # Associate the given key with the given value, replacing any existing
    # association. When called with a block and no value, the block receives
    # the currently associated value (or +nil+) and its result is stored.
    #
    # @return [self]
    def put(key, value = yield(get(key)))
      check_valid!
      @trie = @trie.put_transient(key, value, @token)
      self
    end

    # Associate the given key with the given value.
    #
    # @return [Object] the stored value
    def store(key, value)
      put(key, value)
      value
    end
    alias :[]= :store

    # Remove the association for the given key, if present.
    #
    # @return [Object] the previously associated value, or +nil+
    def delete(key)
      check_valid!
      old_value = get(key)
      @trie = @trie.delete_transient(key, @token) || Trie.new(0)
      old_value
    end

    # Call the block once for each key/value pair in the hash under
    # construction.
    #
    # @return [self, Enumerator]
    def each(&block)
      check_valid!
      return enum_for(:each) unless block_given?
      @trie.each(&block)
      self
    end

    # End the editing session and return an immutable {Hamster::Hash} with
    # the accumulated contents. The editor must not be used afterwards.
    #
    # @return [Hash]
    def persistent!
      check_valid!
      @sealed = true
      @hash_class.alloc(@trie, @default)
    end

    # @private
    # Permanently disable this editor, discarding any reference to the
    # mutable trie. Used to guarantee that a session which ends abnormally
    # cannot be resumed through a lingering reference.
    def invalidate!
      @sealed = true
      @trie = nil
      self
    end

    private

    def check_valid!
      if @sealed
        raise TransientError, "transient used after being sealed"
      elsif !@thread.equal?(Thread.current)
        raise TransientError, "transient used from a thread other than the one which created it"
      end
    end
  end

  # A short-lived, mutable editor for a {Hamster::Vector}, obtained from
  # {Vector#transient}. Like {TransientHash}, it mutates only nodes which
  # are exclusively owned by the editing session, copies shared nodes on
  # first touch, is confined to its creating thread, and must be sealed with
  # {#persistent!} to produce an immutable {Hamster::Vector}. Indexing and
  # bounds behaviour mirror {Vector}: out-of-range reads return +nil+,
  # {#fetch} raises +IndexError+, and writing past the end pads with +nil+s.
  class TransientVector
    # @private
    def initialize(vector_class, root, size, levels)
      @vector_class = vector_class
      @root = root
      @size = size
      @levels = levels
      @owned = {}.compare_by_identity
      @thread = Thread.current
      @sealed = false
    end

    # Return the number of items in the vector under construction.
    #
    # @return [Integer]
    def size
      check_valid!
      @size
    end
    alias :length :size

    # Return +true+ if the vector under construction contains no items.
    #
    # @return [Boolean]
    def empty?
      check_valid!
      @size == 0
    end

    # Return the first item, or +nil+ if empty.
    #
    # @return [Object]
    def first
      get(0)
    end

    # Return the last item, or +nil+ if empty.
    #
    # @return [Object]
    def last
      get(-1)
    end

    # Retrieve the item at +index+. If there is none (either the provided
    # index is too high or too low), return +nil+.
    #
    # @param index [Integer] The index to retrieve. May be negative.
    # @return [Object]
    def get(index)
      check_valid!
      return nil if @size == 0
      index += @size if index < 0
      return nil if index >= @size || index < 0
      leaf_node_for(@root, @levels * Vector::BITS_PER_LEVEL, index)[index & Vector::INDEX_MASK]
    end
    alias :at :get
    alias :[] :get

    # Retrieve the value at +index+, following the same rules as
    # {Vector#fetch}.
    #
    # @return [Object]
    def fetch(index, default = (missing_default = true))
      check_valid!
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

    # Replace the item at +index+ with +item+, or with the result of the
    # block when no item is given. Follows the same rules as {Vector#put}:
    # negative indices count from the end, an +index+ of exactly {#size}
    # appends, greater indices pad the gap with +nil+s, and an index below
    # +-size+ raises +IndexError+.
    #
    # @return [self]
    def set(index, item = yield(get(index)))
      check_valid!
      raise IndexError, "index #{index} outside of vector bounds" if index < -@size
      index += @size if index < 0
      if index > @size
        (@size...index).each { update_root!(@size, nil) }
        update_root!(@size, item)
      else
        update_root!(index, item)
      end
      self
    end
    alias :put :set

    # Replace the item at +index+ with +item+.
    #
    # @return [Object] the stored item
    def store(index, item)
      set(index, item)
      item
    end
    alias :[]= :store

    # Add +item+ after the last occupied position.
    #
    # @return [self]
    def push(item)
      check_valid!
      update_root!(@size, item)
      self
    end
    alias :<< :push
    alias :add :push

    # Remove the last item. Does nothing if the vector is empty.
    #
    # @return [self]
    def pop
      check_valid!
      return self if @size == 0
      @size -= 1
      @root = ensure_owned(@root)
      remove_at!(@root, @levels * Vector::BITS_PER_LEVEL, @size)
      while @levels > 0 && @root.size == 1
        @root = @root[0]
        @levels -= 1
      end
      self
    end

    # Call the block once for each item, from first to last.
    #
    # @return [self, Enumerator]
    def each(&block)
      check_valid!
      return enum_for(:each) unless block_given?
      traverse_depth_first(@root, @levels, &block)
      self
    end

    # End the editing session and return an immutable {Hamster::Vector}
    # with the accumulated contents. The editor must not be used afterwards.
    #
    # @return [Vector]
    def persistent!
      check_valid!
      @sealed = true
      deep_freeze(@root, @levels)
      @vector_class.alloc(@root, @size, @levels)
    end

    # @private
    # Permanently disable this editor, discarding any reference to the
    # mutable nodes. Used to guarantee that a session which ends abnormally
    # cannot be resumed through a lingering reference.
    def invalidate!
      @sealed = true
      @root = nil
      @owned = nil
      self
    end

    private

    def check_valid!
      if @sealed
        raise TransientError, "transient used after being sealed"
      elsif !@thread.equal?(Thread.current)
        raise TransientError, "transient used from a thread other than the one which created it"
      end
    end

    # Nodes (plain arrays) which were copied or created during this session
    # are registered in @owned and may be mutated in place. Any other node
    # is still shared with a persistent vector and is copied on first touch.
    def ensure_owned(node)
      if @owned.include?(node)
        node
      else
        copy = node.dup
        @owned[copy] = true
        copy
      end
    end

    def update_root!(index, item)
      while index >= (1 << (Vector::BITS_PER_LEVEL * (@levels + 1)))
        @root = [@root]
        @owned[@root] = true
        @levels += 1
      end
      @root = ensure_owned(@root)
      update_leaf_node!(@root, @levels * Vector::BITS_PER_LEVEL, index, item)
      @size = index + 1 if index >= @size
      self
    end

    def update_leaf_node!(node, bitshift, index, item)
      slot_index = (index >> bitshift) & Vector::INDEX_MASK
      if bitshift > 0
        child = node[slot_index]
        if child.nil?
          child = []
          @owned[child] = true
        else
          child = ensure_owned(child)
        end
        node[slot_index] = child
        update_leaf_node!(child, bitshift - Vector::BITS_PER_LEVEL, index, item)
      else
        node[slot_index] = item
      end
    end

    def remove_at!(node, bitshift, index)
      slot_index = (index >> bitshift) & Vector::INDEX_MASK
      if bitshift == 0
        node.delete_at(slot_index)
      else
        child = ensure_owned(node[slot_index])
        node[slot_index] = child
        remove_at!(child, bitshift - Vector::BITS_PER_LEVEL, index)
        node.delete_at(slot_index) if child.empty?
      end
    end

    def leaf_node_for(node, bitshift, index)
      while bitshift > 0
        node = node[(index >> bitshift) & Vector::INDEX_MASK]
        bitshift -= Vector::BITS_PER_LEVEL
      end
      node
    end

    def traverse_depth_first(node, level, &block)
      return node.each(&block) if level == 0
      node.each { |child| traverse_depth_first(child, level - 1, &block) }
    end

    def deep_freeze(node, level)
      node.each { |child| deep_freeze(child, level - 1) } if level > 0
      node.freeze
    end
  end
end
