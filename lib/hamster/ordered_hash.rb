require "hamster/immutable"
require "hamster/undefined"
require "hamster/enumerable"
require "hamster/hash"
require "hamster/vector"

module Hamster
  # A `Hamster::OrderedHash` maps unique keys to values, just like
  # `Hamster::Hash`, but additionally preserves the *insertion order* of its
  # keys when enumerating, just like Ruby's built-in Hash (RubyHash). This
  # makes it suitable for things like configuration editors, where the order
  # in which fields were defined must survive round-trips through
  # transformation pipelines.
  #
  # Like all Hamster collections, it is immutable and persistent: every
  # "modifying" method returns a new `OrderedHash` and leaves the receiver
  # untouched, so any number of historical versions can be retained and used
  # concurrently.
  #
  #     ordered = Hamster::OrderedHash[font_size: 10, font_family: "Arial"]
  #     ordered.put(:color, "red")
  #     # => Hamster::OrderedHash[:font_size => 10, :font_family => "Arial", :color => "red"]
  #
  # == Ordering guarantees
  #
  # * A key which is added for the first time takes the next position at the
  #   *end* of the order.
  # * Re-storing an existing key with {#put} (or via {#merge}) replaces its
  #   value but *does not move* the key from its original position.
  # * {#delete} removes a key from the order entirely. If the same key is
  #   later re-added, it is treated as a new key and placed at the *end*.
  # * {#merge} processes the other collection in *its* iteration order. On
  #   conflicting keys the *value from the other collection wins*, but the key
  #   keeps its existing position; keys which are not yet present are appended
  #   at the end, in the order the other collection yields them.
  #
  # == Internal representation and compaction
  #
  # Key/value lookup is delegated to a `Hamster::Hash` (a hash array mapped
  # trie), so keys which share the same `#hash` code but are not `#eql?`
  # coexist without problems, and lookups stay effectively constant time. The
  # insertion order is tracked separately in a `Hamster::Vector` of
  # `[key, value]` pairs, while the hash maps each key to its slot index in
  # that vector. Because both structures are persistent, {#put} and {#delete}
  # only copy a path of O(log32 n) nodes -- the whole key array is never
  # rebuilt on ordinary updates.
  #
  # Deletions leave tombstone slots in the vector. To keep those "holes" from
  # accumulating without bound, the structure is *compacted* (slots and slot
  # indices rebuilt in a single pass) whenever the number of tombstones
  # exceeds the number of live entries. This bounds the slot vector to at most
  # twice the live size and keeps the amortized cost of {#delete} constant.
  # Compaction only ever builds a *new* version: previously returned versions
  # keep their own slot vectors and continue to enumerate correctly.
  #
  # Two keys are considered the same when they are `#eql?` and have the same
  # `#hash` code, exactly like `Hamster::Hash` and RubyHash.
  class OrderedHash
    include Immutable
    include Hamster::Enumerable

    # Marks a slot whose key was deleted. Never exposed through the public API.
    # @private
    TOMBSTONE = Object.new.freeze

    class << self
      # Create a new `OrderedHash` populated with the given key/value pairs.
      #
      # @example
      #   Hamster::OrderedHash["A" => 1, "B" => 2] # => Hamster::OrderedHash["A" => 1, "B" => 2]
      #   Hamster::OrderedHash[["A", 1], ["B", 2]] # => Hamster::OrderedHash["A" => 1, "B" => 2]
      #
      # @param pairs [::Enumerable] initial content, in insertion order. An
      #   empty `OrderedHash` is returned if not provided.
      # @return [OrderedHash]
      def [](pairs = nil)
        (pairs.nil? || pairs.empty?) ? empty : new(pairs)
      end

      # Return an empty `OrderedHash`. If used on a subclass, returns an
      # empty instance of that class.
      #
      # @return [OrderedHash]
      def empty
        @empty ||= self.new
      end

      # "Raw" allocation of a new `OrderedHash`. Used internally to create a
      # new instance quickly once the component structures are known.
      #
      # @return [OrderedHash]
      # @private
      def alloc(hash = EmptyHash, slots = EmptyVector, size = 0, holes = 0)
        obj = allocate
        obj.instance_variable_set(:@hash, hash)
        obj.instance_variable_set(:@slots, slots)
        obj.instance_variable_set(:@size, size)
        obj.instance_variable_set(:@holes, holes)
        obj
      end
    end

    # @param pairs [::Enumerable] initial content, in insertion order. An
    #   empty `OrderedHash` is created if not provided.
    def initialize(pairs = nil)
      hash  = EmptyHash
      slots = EmptyVector
      size  = 0
      if pairs
        pairs.each do |key, value|
          slot = hash.get(key)
          if slot
            slots = slots.put(slot, [slots.get(slot)[0], value].freeze)
          else
            key = key.dup.freeze if key.is_a?(String) && !key.frozen?
            hash  = hash.put(key, slots.size)
            slots = slots.add([key, value].freeze)
            size += 1
          end
        end
      end
      @hash  = hash
      @slots = slots
      @size  = size
      @holes = 0
    end

    # Return the number of key/value pairs in this `OrderedHash`.
    #
    # @return [Integer]
    def size
      @size
    end
    # Return the number of key/value pairs in this `OrderedHash`.
    #
    # @return [Integer]
    def size
      @size
    end
    alias :length :size

    # Return `true` if this `OrderedHash` contains no key/value pairs.
    #
    # @return [Boolean]
    def empty?
      @size == 0
    end

    # Return `true` if the given key object is present in this
    # `OrderedHash`. More precisely, return `true` if a key with the same
    # `#hash` code, and which is also `#eql?` to the given key object, is
    # present.
    #
    # @param key [Object] The key to check for
    # @return [Boolean]
    def key?(key)
      @hash.key?(key)
    end
    alias :has_key? :key?
    alias :include? :key?
    alias :member? :key?

    # Return the value associated with the given key, or `nil` if the key is
    # not present.
    #
    # @param key [Object] The key to look up
    # @return [Object]
    def get(key)
      slot = @hash.get(key)
      slot && @slots.get(slot)[1]
    end
    alias :[] :get

    # Return the value associated with the given key. If the key is not
    # present, return the `default` value, or the result of the optional
    # block, or raise a `KeyError` if neither is given.
    #
    # @param key [Object] The key to look up
    # @param default [Object] Value to return if `key` is not present
    # @yield [key] Block to compute the return value when `key` is missing
    # @return [Object]
    def fetch(key, default = Undefined)
      slot = @hash.get(key)
      if slot
        @slots.get(slot)[1]
      elsif block_given?
        yield key
      elsif default != Undefined
        default
      else
        raise KeyError, "key not found: #{key.inspect}"
      end
    end

    # Return `true` if the given value is present in this `OrderedHash`.
    #
    # @param value [Object] The value to check for
    # @return [Boolean]
    def value?(value)
      each { |_key, val| return true if value == val }
      false
    end
    alias :has_value? :value?

    # Return a new `OrderedHash` with the given key associated with the given
    # value. If an equivalent key is already present, its value is replaced
    # but the key *keeps its original position* in the order. Otherwise the
    # key is appended at the *end* of the order.
    #
    # If the `value` argument is missing, but an optional code block is
    # provided, it will be passed the existing value (or `nil` if there is
    # none) and what it returns will be stored instead.
    #
    # @example
    #   h = Hamster::OrderedHash["A" => 1, "B" => 2]
    #   h.put("C", 3)              # => Hamster::OrderedHash["A" => 1, "B" => 2, "C" => 3]
    #   h.put("B", 20)             # => Hamster::OrderedHash["A" => 1, "B" => 20]
    #   h.put("B") { |v| v * 10 }  # => Hamster::OrderedHash["A" => 1, "B" => 20]
    #
    # @param key [Object] The key to store
    # @param value [Object] The value to associate it with
    # @yield [value] The previously stored value, or `nil` if none
    # @yieldreturn [Object] The new value to store
    # @return [OrderedHash]
    def put(key, value = yield(get(key)))
      slot = @hash.get(key)
      if slot
        pair = @slots.get(slot)
        if pair[1].equal?(value)
          self
        else
          self.class.alloc(@hash, @slots.put(slot, [pair[0], value].freeze), @size, @holes)
        end
      else
        key = key.dup.freeze if key.is_a?(String) && !key.frozen?
        self.class.alloc(@hash.put(key, @slots.size), @slots.add([key, value].freeze), @size + 1, @holes)
      end
    end

    # Return a new `OrderedHash` with the given key (and its associated
    # value) removed. If the key is not present, return `self`. The key's
    # position in the order is released: re-adding the key later places it at
    # the *end* of the order.
    #
    # @param key [Object] The key to remove
    # @return [OrderedHash]
    def delete(key)
      slot = @hash.get(key)
      return self unless slot
      hash  = @hash.delete(key)
      slots = @slots.put(slot, TOMBSTONE)
      size  = @size - 1
      holes = @holes + 1
      if holes > size
        self.class.alloc(hash, slots, size, holes).send(:compact_slots)
      else
        self.class.alloc(hash, slots, size, holes)
      end
    end

    # Return a new `OrderedHash` combining the key/value pairs of this
    # `OrderedHash` and `other`. `other` may be any `Enumerable` of
    # two-element `[key, value]` pairs (including a RubyHash, a
    # `Hamster::Hash`, or another `OrderedHash`) and is processed in its
    # own iteration order:
    #
    # * If a key is already present, the *value from `other` wins*, but the
    #   key keeps its original position in the order.
    # * If a key is not yet present, it is appended at the *end* of the
    #   order, in the order `other` yields it.
    #
    # @example
    #   h = Hamster::OrderedHash["A" => 1, "B" => 2]
    #   h.merge("B" => 20, "C" => 3) # => Hamster::OrderedHash["A" => 1, "B" => 20, "C" => 3]
    #
    # @param other [::Enumerable] The pairs to merge in
    # @return [OrderedHash]
    def merge(other)
      result = self
      other.each { |key, value| result = result.put(key, value) }
      result
    end

    # Call the given block once for each key/value pair, in insertion order.
    # Returns `self`. If no block is given, returns an `Enumerator`.
    #
    # @yield [key, value]
    # @return [self, Enumerator]
    def each(&block)
      return to_enum if not block_given?
      @slots.each do |pair|
        block.call(pair[0], pair[1]) unless pair.equal?(TOMBSTONE)
      end
      self
    end

    # Call the given block once for each key/value pair, in reverse insertion
    # order. Returns `self`. If no block is given, returns an `Enumerator`.
    #
    # @yield [key, value]
    # @return [self, Enumerator]
    def reverse_each(&block)
      return enum_for(:reverse_each) if not block_given?
      @slots.reverse_each do |pair|
        block.call(pair[0], pair[1]) unless pair.equal?(TOMBSTONE)
      end
      self
    end

    # Call the given block once for each key, in insertion order. Returns
    # `self`. If no block is given, returns an `Enumerator`.
    #
    # @yield [key]
    # @return [self, Enumerator]
    def each_key
      return enum_for(:each_key) if not block_given?
      each { |key, _value| yield key }
      self
    end

    # Call the given block once for each value, in insertion order. Returns
    # `self`. If no block is given, returns an `Enumerator`.
    #
    # @yield [value]
    # @return [self, Enumerator]
    def each_value
      return enum_for(:each_value) if not block_given?
      each { |_key, value| yield value }
      self
    end

    # Return the keys of this `OrderedHash` as a frozen `Array`, in
    # insertion order.
    #
    # @return [Array]
    def keys
      result = []
      each { |key, _value| result << key }
      result.freeze
    end

    # Return the values of this `OrderedHash` as a frozen `Array`, in
    # insertion order.
    #
    # @return [Array]
    def values
      result = []
      each { |_key, value| result << value }
      result.freeze
    end

    # Return a new `OrderedHash` containing only the pairs for which the
    # block evaluates to true. The relative order of the remaining pairs is
    # preserved.
    #
    # @yield [key, value]
    # @return [OrderedHash, Enumerator]
    def select(&block)
      return enum_for(:select) if not block_given?
      result = self.class.empty
      each do |key, value|
        result = result.put(key, value) if block.call(key, value)
      end
      result
    end

    # Return an empty `OrderedHash`.
    #
    # @return [OrderedHash]
    def clear
      self.class.empty
    end

    # Return the contents of this `OrderedHash` as a frozen `Array` of
    # `[key, value]` pairs, in insertion order.
    #
    # @return [Array]
    def to_a
      result = []
      each { |key, value| result << [key, value] }
      result.freeze
    end

    # Return the contents of this `OrderedHash` as a RubyHash. Since
    # RubyHash also preserves insertion order, the resulting hash enumerates
    # in the same order.
    #
    # @return [::Hash]
    def to_hash
      result = {}
      each { |key, value| result[key] = value }
      result
    end

    # Return true if `other` is an `OrderedHash` of the same class with the
    # same keys, values, and key order.
    #
    # @param other [Object] The collection to compare with
    # @return [Boolean]
    def eql?(other)
      return true if other.equal?(self)
      return false unless instance_of?(other.class)
      return false unless size == other.size
      other_pairs = other.to_a
      to_a.each_with_index do |(key, value), index|
        other_key, other_value = other_pairs[index]
        return false unless key.eql?(other_key) && value.eql?(other_value)
      end
      true
    end

    # Return true if `other` is an `OrderedHash` with the same keys,
    # values, and key order.
    #
    # @param other [Object] The object to compare with
    # @return [Boolean]
    def ==(other)
      return true if other.equal?(self)
      other.is_a?(OrderedHash) && size == other.size && to_a == other.to_a
    end

    # Return the contents of this `OrderedHash` as a programmer-readable
    # `String`, in insertion order.
    #
    # @return [String]
    def inspect
      result = "#{self.class}["
      i = 0
      each do |key, value|
        result << ", " if i > 0
        result << key.inspect << " => " << value.inspect
        i += 1
      end
      result << "]"
    end
    alias :to_s :inspect

    private

    # Rebuild the slot vector and slot indices in a single pass, dropping all
    # tombstones. Returns a new `OrderedHash` with no holes.
    def compact_slots
      hash  = EmptyHash
      slots = EmptyVector
      @slots.each do |pair|
        next if pair.equal?(TOMBSTONE)
        hash  = hash.put(pair[0], slots.size)
        slots = slots.add(pair)
      end
      self.class.alloc(hash, slots, @size, 0)
    end
  end

  # The canonical empty `OrderedHash`.
  EmptyOrderedHash = Hamster::OrderedHash.empty
end
