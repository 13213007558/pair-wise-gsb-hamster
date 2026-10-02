require "hamster/hash"
require "hamster/vector"
require "hamster/undefined"
require "hamster/associable"

module Hamster
  # An `OrderedMap` is an immutable map which retains the insertion order of
  # its keys. Overwriting an existing key does not move it. A key which is
  # deleted and later inserted again is treated as a new key and placed at the
  # end.
  #
  # Deleted positions are represented sparsely in a persistent {Vector}.
  # Updates therefore copy only a small path rather than rebuilding all keys.
  # When enough deleted positions accumulate, the order index is rebuilt once,
  # keeping the cost amortized.
  class OrderedMap
    include Immutable
    include Enumerable
    include Associable

    # @private
    TOMBSTONE = Object.new.freeze
    # @private
    COMPACTION_THRESHOLD = 32

    class << self
      # Create a new `OrderedMap` populated with the given key/value pairs.
      #
      # @param pairs [::Enumerable] initial key/value pairs
      # @return [OrderedMap]
      def [](pairs = nil)
        (pairs.nil? || pairs.empty?) ? empty : new(pairs)
      end

      # Return an empty `OrderedMap`. If used on a subclass, returns an empty
      # instance of that class.
      #
      # @return [OrderedMap]
      def empty
        @empty ||= self.new
      end

      # @private
      def alloc(entries, order, deleted = 0, default_block = nil)
        object = allocate
        object.instance_variable_set(:@entries, entries)
        object.instance_variable_set(:@order, order)
        object.instance_variable_set(:@deleted, deleted)
        object.instance_variable_set(:@default, default_block)
        object.immutable!
        object
      end
    end

    # @param pairs [::Enumerable] initial key/value pairs. If a key occurs more
    #   than once, the first occurrence determines its position and the last
    #   occurrence determines its value.
    # @yield [key] Optional default block used when reading a missing key.
    def initialize(pairs = nil, &block)
      @default = block
      @entries = EmptyHash
      @order = EmptyVector
      @deleted = 0

      if pairs
        trie = Trie.new(0)
        keys = []
        pairs.each do |key, value|
          key = normalize_key(key)
          if trie.key?(key)
            position = trie.get(key)[1]
          else
            position = keys.size
            keys << key
          end
          trie.put!(key, [value, position].freeze)
        end
        @entries = Hamster::Hash.alloc(trie).immutable!
        @order = Vector.new(keys.freeze)
      end
    end

    # Return the default block, or `nil` if there is none.
    # @return [Proc]
    def default_proc
      @default
    end

    # Return the number of key/value pairs.
    # @return [Integer]
    def size
      @entries.size
    end
    alias :length :size

    # Return `true` if this map contains no key/value pairs.
    # @return [Boolean]
    def empty?
      @entries.empty?
    end

    # Return `true` if an `#eql?` key with the same `#hash` is present.
    # @param key [Object]
    # @return [Boolean]
    def key?(key)
      @entries.key?(key)
    end
    alias :has_key? :key?
    alias :include? :key?
    alias :member? :key?

    # Return `true` if any key maps to `value` using `#==`.
    # @param value [Object]
    # @return [Boolean]
    def value?(value)
      each { |_key, stored| return true if value == stored }
      false
    end
    alias :has_value? :value?

    # Return the value associated with `key`, or the default-block result if
    # the key is missing. A stored `nil` is distinguished from a missing key.
    # @param key [Object]
    # @return [Object]
    def get(key)
      return @entries.get(key)[0] if @entries.key?(key)
      @default.call(key) if @default
    end
    alias :[] :get

    # Retrieve a value, a supplied default, a block result, or raise `KeyError`.
    def fetch(key, default = Undefined)
      return @entries.get(key)[0] if @entries.key?(key)
      return yield(key) if block_given?
      return default unless default.equal?(Undefined)
      raise KeyError, "key not found: #{key.inspect}"
    end

    # Return a new map with `key` associated with `value`. An existing key keeps
    # its position. A new key is appended after the current last key.
    #
    # If `value` is omitted, the block receives the current value (or the
    # default-block result for a missing key) and its return value is stored.
    def put(key, value = yield(get(key)))
      key = normalize_key(key)
      existing = @entries.get(key)
      if existing
        return self if existing[0].equal?(value)
        new_entries = @entries.put(key, [value, existing[1]].freeze)
        return self.class.alloc(new_entries, @order, @deleted, @default)
      end

      position = @order.size
      new_entries = @entries.put(key, [value, position].freeze)
      new_order = @order.add(key)
      self.class.alloc(new_entries, new_order, @deleted, @default)
    end
    alias :store :put

    # @private
    def []=(*)
      raise NoMethodError, "#{self.class} doesn't support `[]='; use `put' instead"
    end

    # Return a new map with `key` removed. If the key is later added again, it
    # is appended to the end rather than reclaiming its old position.
    # @param key [Object]
    # @return [OrderedMap]
    def delete(key)
      return self unless @entries.key?(key)

      position = @entries.get(key)[1]
      new_entries = @entries.delete(key)
      new_order = @order.put(position, TOMBSTONE)
      new_deleted = @deleted + 1
      result = self.class.alloc(new_entries, new_order, new_deleted, @default)
      new_deleted >= COMPACTION_THRESHOLD ? result.send(:compact_order) : result
    end

    # Yield each `[key, value]` pair in insertion order.
    # @return [OrderedMap, Enumerator]
    def each(&block)
      return to_enum(:each) unless block_given?
      @order.each do |key|
        next if key.equal?(TOMBSTONE)
        block.call(key, @entries.get(key)[0])
      end
      self
    end
    alias :each_pair :each

    # Yield each pair in reverse insertion order.
    # @return [OrderedMap, Enumerator]
    def reverse_each(&block)
      return enum_for(:reverse_each) unless block_given?
      @order.reverse_each do |key|
        next if key.equal?(TOMBSTONE)
        block.call(key, @entries.get(key)[0])
      end
      self
    end

    # Yield keys in insertion order.
    def each_key(&block)
      return enum_for(:each_key) unless block_given?
      each { |key, _value| block.call(key) }
      self
    end

    # Yield values in insertion order.
    def each_value(&block)
      return enum_for(:each_value) unless block_given?
      each { |_key, value| block.call(value) }
      self
    end

    # Map pairs and gather the result into a new ordered map.
    def map
      return enum_for(:map) unless block_given?
      return self if empty?
      self.class.new(super, &@default)
    end
    alias :collect :map

    # Return a new ordered map containing pairs for which the block is true.
    def select(&block)
      return enum_for(:select) unless block
      selected = []
      each { |key, value| selected << [key, value] if block.call(key, value) }
      self.class.new(selected, &@default)
    end
    alias :find_all :select
    alias :keep_if :select

    def reject(&block)
      return enum_for(:reject) unless block
      select { |key, value| !block.call(key, value) }
    end
    alias :delete_if :reject

    # Return a new ordered map with all `nil` values removed, preserving order.
    def compact
      select { |_key, value| !value.nil? }
    end

    # Merge another map or enumerable of pairs.
    #
    # A key already present in the receiver keeps its original position.
    # Without a block, the other value wins on conflict. With a block, the
    # block receives `(key, receiver_value, other_value)` and its result wins.
    # Keys absent from the receiver are appended in the order `other` yields
    # them. If a new key occurs more than once while merging, its first
    # occurrence determines its appended position and later occurrences update
    # its value.
    def merge(other)
      result = self
      other.each do |key, value|
        if block_given? && result.key?(key)
          result = result.put(key, yield(key, result.get(key), value))
        else
          result = result.put(key, value)
        end
      end
      result
    end
    alias :update :merge

    # Return a new map with all given keys removed.
    def except(*keys)
      keys.reduce(self) { |map, key| map.delete(key) }
    end

    # Return a new map containing the requested keys, preserving this map's
    # key order.
    def slice(*wanted)
      selected = []
      each do |key, value|
        selected << [key, value] if wanted.any? { |candidate| candidate.eql?(key) }
      end
      self.class.new(selected, &@default)
    end

    # Return values for the requested keys as a {Vector}, using `nil` or the
    # default for missing keys.
    def values_at(*wanted)
      Vector.new(wanted.map { |key| get(key) }.freeze)
    end

    # Return values for the requested keys as a {Vector}, raising if any key
    # is missing.
    def fetch_values(*wanted)
      Vector.new(wanted.map { |key| fetch(key) }.freeze)
    end

    # Return all keys as an ordered {Vector}.
    def keys
      Vector.new(each_key.to_a.freeze)
    end

    # Return all values as an ordered {Vector}.
    def values
      Vector.new(each_value.to_a.freeze)
    end

    # Return a new ordered map with keys and values exchanged.
    def invert
      self.class.new(map { |key, value| [value, key] }, &@default)
    end

    # Return a one-dimensional flattening of this map as a {Vector}.
    def flatten(level = 1)
      return Vector.new(self) if level == 0
      array = []
      each { |key, value| array << key; array << value }
      array.flatten!(level - 1) if level > 1
      Vector.new(array.freeze)
    end

    # Return the first pair whose key is `==` to `object`.
    def assoc(object)
      each { |pair| return pair if object == pair[0] }
      nil
    end

    # Return the first pair whose value is `==` to `object`.
    def rassoc(object)
      each { |pair| return pair if object == pair[1] }
      nil
    end

    # Return the first key whose value is `==` to `value`.
    def key(value)
      each { |key, stored| return key if value == stored }
      nil
    end

    # Return a random pair, or `nil` when empty.
    def sample
      to_a.sample
    end

    # Return an empty map of the same class, retaining the default block.
    def clear
      if @default
        self.class.alloc(EmptyHash, EmptyVector, 0, @default)
      else
        self.class.empty
      end
    end

    # Order-sensitive equality: the same pairs must occur in the same order.
    def eql?(other)
      return true if equal?(other)
      return false unless instance_of?(other.class) && size == other.size

      other_pairs = other.each
      each do |key, value|
        other_key, other_value = other_pairs.next
        return false unless key.eql?(other_key) && value.eql?(other_value)
      end
      true
    end

    # Content equality with a Ruby hash ignores order, matching Ruby's `Hash#==`.
    def ==(other)
      eql?(other) || (other.respond_to?(:to_hash) && to_hash == other.to_hash)
    end

    # Return an order-sensitive hash code.
    def hash
      each.reduce(0) do |digest, (key, value)|
        (digest << 5) - digest + key.hash + value.hash
      end
    end

    # Return a programmer-readable representation.
    def inspect
      result = "#{self.class}["
      each_with_index do |(key, value), index|
        result << ", " if index > 0
        result << key.inspect << " => " << value.inspect
      end
      result << "]"
    end

    # @private
    def pretty_print(printer)
      printer.group(1, "#{self.class}[", "]") do
        printer.breakable("")
        printer.seplist(self, nil) do |key, value|
          printer.group do
            key.pretty_print(printer)
            printer.text(" => ")
            printer.group(1) { printer.breakable(""); value.pretty_print(printer) }
          end
        end
      end
    end

    # Convert to a built-in Ruby hash with insertion order retained.
    def to_hash
      output = {}
      each { |key, value| output[key] = value }
      output
    end
    alias :to_h :to_hash

    # Return a proc which looks up a key.
    def to_proc
      lambda { |key| get(key) }
    end

    # @private
    def marshal_dump
      to_hash
    end

    # @private
    def marshal_load(dictionary)
      initialize(dictionary)
      immutable!
    end

    private

    def normalize_key(key)
      if key.is_a?(String) && !key.frozen?
        key.dup.freeze
      else
        key
      end
    end

    def compact_order
      trie = Trie.new(0)
      live_keys = []
      @order.each do |key|
        next if key.equal?(TOMBSTONE)
        trie.put!(key, [@entries.get(key)[0], live_keys.size].freeze)
        live_keys << key
      end
      entries = Hamster::Hash.alloc(trie).immutable!
      self.class.alloc(entries, Vector.new(live_keys.freeze), 0, @default)
    end
  end

  OrderedHash = OrderedMap
  EmptyOrderedMap = OrderedMap.empty
end
