require "hamster/trie"
require "hamster/undefined"

module Hamster
  # A `TransientHash` is a mutable, single-threaded editing session for a
  # {Hamster::Hash}. It is obtained from {Hamster::Hash#transient}, used to
  # perform a batch of updates, and finally sealed back into an immutable
  # {Hamster::Hash} with {#persistent!}.
  #
  # Unlike {Hamster::MutableHash} (which repeatedly replaces one persistent
  # version with another), a `TransientHash` mutates trie nodes in place
  # whenever they are exclusively owned by this editing session. Nodes which
  # are still shared with the original hash (or any other persistent
  # collection derived from it) are copied before they are modified, so the
  # original collection and all its other branches are never affected.
  #
  # A `TransientHash` may only be used from the thread which created it, and
  # only until it is sealed with {#persistent!} (or invalidated by an
  # exception propagating out of the block form of {Hamster::Hash#transient}).
  # Any use after that raises a `RuntimeError`.
  #
  # @example
  #   hash = Hamster::Hash[a: 1, b: 2]
  #   hash.transient do |t|
  #     1000.times { |i| t.put(i, i * 2) }
  #     t.delete(:a)
  #   end # => sealed Hamster::Hash
  class TransientHash
    # @private
    def initialize(trie, default, klass)
      @trie = trie
      @default = default
      @class = klass
      @token = Object.new
      @thread = Thread.current
      @active = true
    end

    # Return the number of key/value pairs currently in the edited hash.
    # @return [Integer]
    def size
      ensure_valid!
      @trie.size
    end
    alias :length :size

    # Return `true` if the edited hash currently contains no key/value pairs.
    # @return [Boolean]
    def empty?
      ensure_valid!
      @trie.empty?
    end

    # Return `true` if the given key is currently present in the edited hash.
    # @return [Boolean]
    def key?(key)
      ensure_valid!
      @trie.key?(key)
    end
    alias :has_key? :key?
    alias :include? :key?
    alias :member? :key?

    # Retrieve the value corresponding to the given key, like
    # {Hamster::Hash#get}. If the key is not present and the original hash
    # has a default block, it is used to compute the result.
    #
    # @param key [Object] The key to look up
    # @return [Object]
    def get(key)
      ensure_valid!
      entry = @trie.get(key)
      if entry
        entry[1]
      elsif @default
        @default.call(key)
      end
    end
    alias :[] :get

    # Retrieve the value corresponding to the given key, or use the provided
    # default value or block, or otherwise raise a `KeyError`. Mirrors
    # {Hamster::Hash#fetch}.
    #
    # @param key [Object] The key to look up
    # @return [Object]
    def fetch(key, default = Undefined)
      ensure_valid!
      entry = @trie.get(key)
      if entry
        entry[1]
      elsif block_given?
        yield(key)
      elsif default != Undefined
        default
      else
        raise KeyError, "key not found: #{key.inspect}"
      end
    end

    # Associate the given key with the given value in the edited hash.
    # If a block is given instead of a value, it is called with the
    # previously stored value (or `nil`) and its return value is stored.
    # Mirrors the key-handling contract of {Hamster::Hash#put}: unfrozen
    # `String` keys are duplicated and frozen.
    #
    # @param key [Object] The key to store
    # @param value [Object] The value to associate it with
    # @yield [value] The previously stored value, or `nil` if none
    # @return [self]
    def put(key, value = yield(get(key)))
      ensure_valid!
      @trie = @trie.put_mutating(key, value, @token)
      self
    end

    # Like {#put}, but returns the stored value, to match RubyHash's API.
    #
    # @param key [Object] The key to store
    # @param value [Object] The value to associate it with
    # @return [Object] the stored value
    def store(key, value)
      put(key, value)
      value
    end
    alias :[]= :store

    # Remove the given key (and its associated value) from the edited hash.
    #
    # @param key [Object] The key to remove
    # @return [Object] the previously associated value, or `nil` if none
    def delete(key)
      ensure_valid!
      old_value = get(key)
      @trie = @trie.delete_mutating(key, @token) || EmptyTrie
      old_value
    end

    # End the editing session and return an immutable {Hamster::Hash} with
    # all the changes applied. The original hash is left unchanged.
    #
    # After this method is called, any further use of this editor raises a
    # `RuntimeError`.
    #
    # @return [Hamster::Hash]
    def persistent!
      ensure_valid!
      @active = false
      trie, default, klass = @trie, @default, @class
      @trie = @default = @class = @token = @thread = nil
      if trie.empty? && default.nil?
        klass.empty
      else
        klass.alloc(trie, default)
      end
    end

    # Invalidate this editor without producing a persistent hash. Used
    # internally when an exception escapes the block form of
    # {Hamster::Hash#transient}, so that a half-finished editing session
    # can never be resumed through a retained reference. Does nothing if
    # the editor has already been sealed.
    #
    # @private
    def invalidate!
      @active = false
      @trie = @default = @class = @token = @thread = nil
      nil
    end

    private

    def ensure_valid!
      if !@active
        raise RuntimeError, "transient hash used after its editing session ended"
      elsif !Thread.current.equal?(@thread)
        raise RuntimeError, "transient hash used from a thread other than the one which created it"
      end
    end
  end

  # A `TransientVector` is a mutable, single-threaded editing session for a
  # {Hamster::Vector}. It is obtained from {Hamster::Vector#transient}, used
  # to perform a batch of updates, and finally sealed back into an immutable
  # {Hamster::Vector} with {#persistent!}.
  #
  # Nodes (arrays) which were created during this editing session are
  # mutated in place; nodes still shared with the original vector (or any
  # other persistent vector derived from it) are copied before they are
  # modified, so existing persistent collections are never affected.
  #
  # A `TransientVector` may only be used from the thread which created it,
  # and only until it is sealed with {#persistent!} (or invalidated by an
  # exception propagating out of the block form of
  # {Hamster::Vector#transient}). Any use after that raises a
  # `RuntimeError`.
  #
  # @example
  #   vector = Hamster::Vector[1, 2, 3]
  #   vector.transient do |t|
  #     1000.times { |i| t.add(i) }
  #     t.put(0, 99)
  #   end # => sealed Hamster::Vector
  class TransientVector
    # Vector tree constants are referenced through Hamster::Vector at
    # runtime (not copied here) to avoid load-order dependencies.
    #
    # @private
    def initialize(root, size, levels, klass)
      @root = root
      @size = size
      @levels = levels
      @class = klass
      @owned = {}.compare_by_identity
      @thread = Thread.current
      @active = true
    end

    # Return the number of items currently in the edited vector.
    # @return [Integer]
    def size
      ensure_valid!
      @size
    end
    alias :length :size

    # Return `true` if the edited vector currently contains no items.
    # @return [Boolean]
    def empty?
      ensure_valid!
      @size == 0
    end

    # Retrieve the item at `index`, like {Hamster::Vector#get}. Negative
    # indices count back from the end. Returns `nil` if the index is out
    # of range.
    #
    # @param index [Integer] The index to retrieve
    # @return [Object]
    def get(index)
      ensure_valid!
      return nil if @size == 0
      index += @size if index < 0
      return nil if index >= @size || index < 0
      leaf_node_for(@root, @levels * Vector::BITS_PER_LEVEL, index)[index & Vector::INDEX_MASK]
    end
    alias :at :get
    alias :[] :get

    # Retrieve the item at `index`, or use the provided default value or
    # block, or otherwise raise an `IndexError`. Mirrors
    # {Hamster::Vector#fetch}.
    #
    # @param index [Integer] The index to look up
    # @return [Object]
    def fetch(index, default = (missing_default = true))
      ensure_valid!
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

    # Add `item` after the last occupied position in the edited vector.
    #
    # @param item [Object] The object to append
    # @return [self]
    def add(item)
      ensure_valid!
      set_in_place(@size, item)
      self
    end
    alias :<< :add
    alias :push :add

    # Replace the item at the given `index` with `item`, following the same
    # boundary contract as {Hamster::Vector#put}: negative indices count
    # back from the end, an `IndexError` is raised if `index` is less than
    # `-size`, and indices beyond the end pad the vector with `nil`s.
    #
    # If a block is given instead of an item, it is called with the existing
    # value at `index` (or `nil`) and its return value is stored.
    #
    # @param index [Integer] The index to update. May be negative.
    # @param item [Object] The object to store at that position
    # @yield [existing] Once with the existing value at the given index
    # @return [self]
    def put(index, item = yield(get(index)))
      ensure_valid!
      raise IndexError, "index #{index} outside of vector bounds" if index < -@size
      index += @size if index < 0
      if index > @size
        set_in_place(@size, nil) while @size < index
        set_in_place(index, item)
      else
        set_in_place(index, item)
      end
      self
    end
    alias :set :put

    # End the editing session and return an immutable {Hamster::Vector} with
    # all the changes applied. The original vector is left unchanged.
    #
    # After this method is called, any further use of this editor raises a
    # `RuntimeError`.
    #
    # @return [Hamster::Vector]
    def persistent!
      ensure_valid!
      @active = false
      @owned.each_key(&:freeze)
      root, size, levels, klass = @root, @size, @levels, @class
      @root = @owned = @class = @thread = nil
      klass.alloc(root, size, levels)
    end

    # Invalidate this editor without producing a persistent vector. Used
    # internally when an exception escapes the block form of
    # {Hamster::Vector#transient}, so that a half-finished editing session
    # can never be resumed through a retained reference. Does nothing if
    # the editor has already been sealed.
    #
    # @private
    def invalidate!
      @active = false
      @root = @owned = @class = @thread = nil
      nil
    end

    private

    def ensure_valid!
      if !@active
        raise RuntimeError, "transient vector used after its editing session ended"
      elsif !Thread.current.equal?(@thread)
        raise RuntimeError, "transient vector used from a thread other than the one which created it"
      end
    end

    def leaf_node_for(node, bitshift, index)
      while bitshift > 0
        node = node[(index >> bitshift) & Vector::INDEX_MASK]
        bitshift -= Vector::BITS_PER_LEVEL
      end
      node
    end

    def set_in_place(index, item)
      while index >= (1 << (Vector::BITS_PER_LEVEL * (@levels + 1)))
        @root = register_owned([@root])
        @levels += 1
      end
      @root = mutable_update(@root, @levels * Vector::BITS_PER_LEVEL, index, item)
      @size = index + 1 if index >= @size
    end

    def mutable_update(node, bitshift, index, item)
      node = editable(node)
      slot_index = (index >> bitshift) & Vector::INDEX_MASK
      if bitshift > 0
        child = node[slot_index]
        child = register_owned([]) if child.nil?
        node[slot_index] = mutable_update(child, bitshift - Vector::BITS_PER_LEVEL, index, item)
      else
        node[slot_index] = item
      end
      node
    end

    def editable(node)
      if @owned.key?(node)
        node
      else
        register_owned(node.dup)
      end
    end

    def register_owned(node)
      @owned[node] = true
      node
    end
  end
end
