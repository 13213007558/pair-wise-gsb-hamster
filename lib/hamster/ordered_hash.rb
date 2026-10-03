require "hamster/immutable"
require "hamster/undefined"
require "hamster/enumerable"
require "hamster/trie"
require "hamster/vector"
require "hamster/associable"

module Hamster
  # An `OrderedHash` maps a set of unique keys to corresponding values, just
  # like {Hamster::Hash}, but it also preserves the order in which keys were
  # first inserted. Iteration ({#each}, {#each_key}, {#each_value}), reverse
  # iteration ({#reverse_each}), positional key lookup ({#key_at}), and the
  # results of {#keys}, {#values}, {#to_hash}, and {#inspect} all follow
  # insertion order, exactly like the built-in Ruby `Hash` ("RubyHash").
  #
  # The ordering rules are the same as RubyHash:
  #
  # * Storing a value for a key which is already present replaces the value,
  #   but the key keeps its original position.
  # * Deleting a key and storing it again moves it to the most recently
  #   inserted position.
  # * {#merge} keeps the position of keys which are already present in the
  #   receiver (only their values are updated). Keys which are new appear
  #   after all existing keys, in the order they occur in the merged
  #   collection.
  #
  # Like {Hamster::Hash}, an `OrderedHash` is immutable: every "modifying"
  # method returns a new `OrderedHash` and leaves the receiver unchanged.
  # This makes it cheap to keep many versions around, or to "fork" a hash
  # and evolve each copy independently.
  #
  # New versions are created efficiently: {#put} and {#delete} never copy
  # the full list of keys. Internally, a {Trie} maps each key to a slot in a
  # persistent {Vector} of `[key, value]` pairs, so successive versions
  # share almost all of their structure. Slots freed by {#delete} become
  # holes, and the holes are compacted away in a single pass (amortized)
  # whenever they outnumber the live entries, so positional access with
  # {#key_at} does not get slower as the hash goes through many deletions.
  # These internal slot numbers are never exposed: every public method only
  # ever returns the keys and values you stored.
  #
  # Two keys which have the same `#hash` code but are not `#eql?` to each
  # other are still distinct members of an `OrderedHash`, each with its own
  # position in the insertion order.
  #
  #     hash = Hamster::OrderedHash[a: 100, b: 200]
  #     hash.put(:c, 300)         # => Hamster::OrderedHash[a: 100, b: 200, c: 300]
  #     hash.put(:a, 999)         # => Hamster::OrderedHash[a: 999, b: 200]
  #     hash.delete(:a).put(:a, 1) # => Hamster::OrderedHash[b: 200, a: 1]
  class OrderedHash
    include Immutable
    include Enumerable
    include Associable

    # @private
    # Minimum number of key slots (live entries plus holes) before
    # #delete will consider compacting the key vector.
    COMPACTION_MIN_SLOTS = 16

    class << self
      # Create a new `OrderedHash` populated with the given key/value pairs.
      #
      # @example
      #   Hamster::OrderedHash["A" => 1, "B" => 2] # => Hamster::OrderedHash["A" => 1, "B" => 2]
      #   Hamster::OrderedHash[["A", 1], ["B", 2]] # => Hamster::OrderedHash["A" => 1, "B" => 2]
      #
      # @param pairs [::Enumerable] initial content of the hash. An empty hash is returned if not provided.
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

      # "Raw" allocation of a new `OrderedHash`. Used internally to create
      # a new instance quickly after obtaining modified internal
      # structures.
      #
      # @return [OrderedHash]
      # @private
      def alloc(trie, keys, size, block = nil)
        obj = allocate
        obj.instance_variable_set(:@trie, trie)
        obj.instance_variable_set(:@keys, keys)
        obj.instance_variable_set(:@size, size)
        obj.instance_variable_set(:@default, block)
        obj
      end
    end

    # @param pairs [::Enumerable] initial content of the hash. An empty hash is returned if not provided.
    # @yield [key] Optional _default block_ to be stored and used to calculate the default value of a missing key. It will not be yielded during this method. It will not be preserved when marshalling.
    # @yieldparam key Key that was not present in the hash.
    def initialize(pairs = nil, &block)
      trie = Trie.new(0)
      entries = []
      if pairs
        pairs.each do |key, value|
          existing = trie.get(key)
          if existing
            entries[existing[1]] = [existing[0], value].freeze
          else
            key = normalize_key(key)
            trie.put!(key, entries.size)
            entries << [key, value].freeze
          end
        end
      end
      @trie = entries.empty? ? EmptyTrie : trie
      @keys = entries.empty? ? EmptyVector : Vector.new(entries.freeze)
      @size = entries.size
      @default = block
    end

    # Return the default block if there is one. Otherwise, return `nil`.
    #
    # @return [Proc]
    def default_proc
      @default
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
      @trie.key?(key)
    end
    alias :has_key? :key?
    alias :include? :key?
    alias :member?  :key?

    # Return `true` if this `OrderedHash` has one or more keys which map to
    # the provided value.
    #
    # @param value [Object] The value to check for
    # @return [Boolean]
    def value?(value)
      each { |k, v| return true if value == v }
      false
    end
    alias :has_value? :value?

    # Retrieve the value corresponding to the provided key object. If not
    # found, and this `OrderedHash` has a default block, the default block
    # is called to provide the value. Otherwise, return `nil`.
    #
    # @param key [Object] The key to look up
    # @return [Object]
    def get(key)
      entry = @trie.get(key)
      if entry
        @keys.get(entry[1])[1]
      elsif @default
        @default.call(key)
      end
    end
    alias :[] :get

    # Retrieve the value corresponding to the given key object, or use the
    # provided default value or block, or otherwise raise a `KeyError`.
    #
    # @overload fetch(key)
    #   Retrieve the value corresponding to the given key, or raise a
    #   `KeyError` if it is not found.
    #   @param key [Object] The key to look up
    # @overload fetch(key) { |key| ... }
    #   Retrieve the value corresponding to the given key, or call the
    #   optional code block (with the missing key) and get its return value.
    #   @yield [key] The key which was not found
    #   @yieldreturn [Object] Object to return since the key was not found
    #   @param key [Object] The key to look up
    # @overload fetch(key, default)
    #   Retrieve the value corresponding to the given key, or else return
    #   the provided `default`.
    #   @param key [Object] The key to look up
    #   @param default [Object] Object to return if the key is not found
    #
    # @return [Object]
    def fetch(key, default = Undefined)
      entry = @trie.get(key)
      if entry
        @keys.get(entry[1])[1]
      elsif block_given?
        yield(key)
      elsif default != Undefined
        default
      else
        raise KeyError, "key not found: #{key.inspect}"
      end
    end

    # Return a new `OrderedHash` with the existing key/value associations,
    # plus an association between the provided key and value. If the key is
    # new, it is appended at the end of the insertion order. If an
    # equivalent key is already present, its value is replaced and it keeps
    # its original position.
    #
    # If the `value` argument is missing, but an optional code block is
    # provided, it will be passed the existing value (or `nil` if there is
    # none) and what it returns will replace the existing value.
    #
    # @example
    #   h = Hamster::OrderedHash["A" => 1, "B" => 2]
    #   h.put("C", 3)  # => Hamster::OrderedHash["A" => 1, "B" => 2, "C" => 3]
    #   h.put("A", 9)  # => Hamster::OrderedHash["A" => 9, "B" => 2]
    #
    # @param key [Object] The key to store
    # @param value [Object] The value to associate it with
    # @yield [value] The previously stored value, or `nil` if none.
    # @yieldreturn [Object] The new value to store
    # @return [OrderedHash]
    def put(key, value = yield(get(key)))
      entry = @trie.get(key)
      if entry
        pair = @keys.get(entry[1])
        return self if pair[1].equal?(value)
        derive_new_hash(@trie, @keys.put(entry[1], [pair[0], value].freeze), @size)
      else
        key = normalize_key(key)
        derive_new_hash(@trie.put(key, @keys.size), @keys.add([key, value].freeze), @size + 1)
      end
    end

    # An alias for {#put} to match RubyHash's API. Does not support
    # {#put}'s block form.
    #
    # @see #put
    # @param key [Object] The key to store
    # @param value [Object] The value to associate it with
    # @return [OrderedHash]
    def store(key, value)
      put(key, value)
    end

    # @private
    # @raise NoMethodError
    def []=(*)
      raise NoMethodError, "Hamster::OrderedHash doesn't support `[]='; use `put' instead"
    end

    # Return a new `OrderedHash` with `key` removed. The remaining keys
    # keep their relative order. If `key` is not present, return `self`.
    #
    # @example
    #   Hamster::OrderedHash["A" => 1, "B" => 2, "C" => 3].delete("B")
    #   # => Hamster::OrderedHash["A" => 1, "C" => 3]
    #
    # @param key [Object] The key to remove
    # @return [OrderedHash]
    def delete(key)
      entry = @trie.get(key)
      return self unless entry
      trie = @trie.delete(key)
      keys = @keys.put(entry[1], nil)
      size = @size - 1
      if size > 0 && keys.size >= COMPACTION_MIN_SLOTS && (keys.size - size) > size
        trie, keys = compact_slots(keys)
      end
      derive_new_hash(trie, keys, size)
    end

    # Call the block once for each key/value pair in this `OrderedHash`,
    # passing the key/value pair as parameters. Pairs are yielded in
    # insertion order.
    #
    # @yield [key, value] Once for each key/value pair.
    # @return [self]
    def each
      return to_enum if not block_given?
      @keys.each do |pair|
        yield(pair) if pair
      end
      self
    end
    alias :each_pair :each

    # Call the block once for each key/value pair in this `OrderedHash`,
    # passing the key/value pair as parameters. Iteration order is the
    # opposite of {#each}: most recently inserted first.
    #
    # @yield [key, value] Once for each key/value pair.
    # @return [self]
    def reverse_each
      return enum_for(:reverse_each) if not block_given?
      @keys.reverse_each do |pair|
        yield(pair) if pair
      end
      self
    end

    # Call the block once for each key in this `OrderedHash`, in insertion
    # order.
    #
    # @yield [key] Once for each key.
    # @return [self]
    def each_key
      return enum_for(:each_key) if not block_given?
      each { |key, _| yield key }
      self
    end

    # Call the block once for each value in this `OrderedHash`, in
    # insertion order.
    #
    # @yield [value] Once for each value.
    # @return [self]
    def each_value
      return enum_for(:each_value) if not block_given?
      each { |_, value| yield value }
      self
    end

    # Return the key at the given `index` in the insertion order, without
    # modifying the hash. Like RubyHash, the first inserted key is at index
    # 0. Negative indices count back from the most recently inserted key,
    # so `key_at(-1)` returns the last inserted key. Return `nil` if the
    # index is out of range.
    #
    # @example
    #   h = Hamster::OrderedHash["A" => 1, "B" => 2, "C" => 3]
    #   h.key_at(0)  # => "A"
    #   h.key_at(-1) # => "C"
    #   h.key_at(3)  # => nil
    #
    # @param index [Integer] The position of the key to retrieve
    # @return [Object]
    def key_at(index)
      index += @size if index < 0
      return nil if index < 0 || index >= @size
      position = 0
      @keys.each do |pair|
        next unless pair
        return pair[0] if position == index
        position += 1
      end
      nil
    end

    # Return a new `OrderedHash` containing all the key/value pairs from
    # this `OrderedHash` and `other`. Keys which are only present in one of
    # the two are kept as they are. Keys which are present in both keep the
    # position they have in this `OrderedHash`; if no block is provided,
    # their value is the one from `other`, otherwise it is determined by
    # calling the block. Keys which only appear in `other` are appended
    # after all existing keys, in the order they occur in `other`.
    #
    # `other` can be an `OrderedHash`, a `Hamster::Hash`, a built-in Ruby
    # `Hash`, or any `Enumerable` object which yields `[key, value]` pairs.
    #
    # @example
    #   h1 = Hamster::OrderedHash["A" => 1, "B" => 2, "C" => 3]
    #   h2 = Hamster::OrderedHash["C" => 70, "D" => 80]
    #   h1.merge(h2)
    #   # => Hamster::OrderedHash["A" => 1, "B" => 2, "C" => 70, "D" => 80]
    #   h1.merge(h2) { |key, v1, v2| v1 + v2 }
    #   # => Hamster::OrderedHash["A" => 1, "B" => 2, "C" => 73, "D" => 80]
    #
    # @param other [::Enumerable] The collection to merge with
    # @yieldparam key [Object] The key which was present in both collections
    # @yieldparam my_value [Object] The associated value from this `OrderedHash`
    # @yieldparam other_value [Object] The associated value from the other collection
    # @yieldreturn [Object] The value to associate this key with in the new `OrderedHash`
    # @return [OrderedHash]
    def merge(other)
      trie = @trie
      keys = @keys
      size = @size
      other.each do |key, value|
        entry = trie.get(key)
        if entry
          pair = keys.get(entry[1])
          value = yield(key, pair[1], value) if block_given?
          next if pair[1].equal?(value)
          keys = keys.put(entry[1], [pair[0], value].freeze)
        else
          key = normalize_key(key)
          trie = trie.put(key, keys.size)
          keys = keys.add([key, value].freeze)
          size += 1
        end
      end
      derive_new_hash(trie, keys, size)
    end

    # Return a new `OrderedHash` with all the key/value pairs for which the
    # block returns true. Pairs are retained in their original insertion
    # order.
    #
    # @example
    #   h = Hamster::OrderedHash["A" => 1, "B" => 2, "C" => 3]
    #   h.select { |k, v| v >= 2 } # => Hamster::OrderedHash["B" => 2, "C" => 3]
    #
    # @yield [key, value] Once for each key/value pair.
    # @yieldreturn Truthy if this pair should be present in the new `OrderedHash`.
    # @return [OrderedHash]
    def select(&block)
      return enum_for(:select) unless block_given?
      trie = Trie.new(0)
      entries = []
      each do |pair|
        next unless block.call(pair)
        trie.put!(pair[0], entries.size)
        entries << pair
      end
      keys = entries.empty? ? EmptyVector : Vector.new(entries.freeze)
      derive_new_hash(trie, keys, entries.size)
    end
    alias :find_all :select
    alias :keep_if  :select

    # Return a new {Vector} of the keys in this `OrderedHash`, in
    # insertion order.
    #
    # @example
    #   Hamster::OrderedHash["A" => 1, "B" => 2].keys # => Hamster::Vector["A", "B"]
    #
    # @return [Vector]
    def keys
      Vector.new(each_key.to_a.freeze)
    end

    # Return a new {Vector} of the values in this `OrderedHash`, in
    # insertion order.
    #
    # @example
    #   Hamster::OrderedHash["A" => 1, "B" => 2].values # => Hamster::Vector[1, 2]
    #
    # @return [Vector]
    def values
      Vector.new(each_value.to_a.freeze)
    end

    # Searches through the `OrderedHash`, comparing `obj` with each key
    # (using `#==`), in insertion order. When a matching key is found,
    # return the `[key, value]` pair as an array. Return `nil` if no match
    # is found.
    #
    # @param obj [Object] The key to search for (using #==)
    # @return [Array]
    def assoc(obj)
      each { |entry| return entry if obj == entry[0] }
      nil
    end

    # Searches through the `OrderedHash`, comparing `obj` with each value
    # (using `#==`), in insertion order. When a matching value is found,
    # return the `[key, value]` pair as an array. Return `nil` if no match
    # is found.
    #
    # @param obj [Object] The value to search for (using #==)
    # @return [Array]
    def rassoc(obj)
      each { |entry| return entry if obj == entry[1] }
      nil
    end

    # Searches through the `OrderedHash`, comparing `value` with each
    # value (using `#==`), in insertion order. When a matching value is
    # found, return its associated key object. Return `nil` if no match is
    # found.
    #
    # @param value [Object] The value to search for (using #==)
    # @return [Object]
    def key(value)
      each { |entry| return entry[0] if value == entry[1] }
      nil
    end

    # Return an empty `OrderedHash` instance, of the same class as this
    # one. Useful if you have multiple subclasses of `OrderedHash` and want
    # to treat them polymorphically. Maintains the default block, if there
    # is one.
    #
    # @return [OrderedHash]
    def clear
      if @default
        self.class.alloc(EmptyTrie, EmptyVector, 0, @default)
      else
        self.class.empty
      end
    end

    # Return true if `other` has the same type and contents as this
    # `OrderedHash`. Like RubyHash, the insertion order of the keys is
    # irrelevant for the comparison.
    #
    # @param other [Object] The collection to compare with
    # @return [Boolean]
    def eql?(other)
      return true if other.equal?(self)
      return false unless instance_of?(other.class) && size == other.size
      each do |key, value|
        return false unless other.key?(key) && value.eql?(other.get(key))
      end
      true
    end

    # Return true if `other` has the same contents as this `OrderedHash`.
    # Will convert `other` to a Ruby `Hash` using `#to_hash` if necessary.
    #
    # @param other [Object] The object to compare with
    # @return [Boolean]
    def ==(other)
      eql?(other) || (other.respond_to?(:to_hash) && to_hash == other.to_hash)
    end

    # See `Object#hash`. The hash code does not depend on the insertion
    # order of the keys, so that any two `OrderedHash`es which are `#eql?`
    # also have the same hash code.
    #
    # @return [Integer]
    def hash
      reduce(0) do |hash, (key, value)|
        hash + (key.hash ^ value.hash)
      end
    end

    # Return the contents of this `OrderedHash` as a programmer-readable
    # `String`, in insertion order. If all the keys and values are
    # serializable as Ruby literal strings, the returned string can be
    # passed to `eval` to reconstitute an equivalent `OrderedHash`. The
    # default block (if there is one) will be lost when doing this,
    # however.
    #
    # @return [String]
    def inspect
      result = "#{self.class}["
      i = 0
      each do |key, val|
        result << ", " if i > 0
        result << key.inspect << " => " << val.inspect
        i += 1
      end
      result << "]"
    end

    # Allows this `OrderedHash` to be printed at the `pry` console, or
    # using `pp` (from the Ruby standard library), in a way which takes
    # the amount of horizontal space on the screen into account, and which
    # indents nested structures to make them easier to read.
    #
    # @private
    def pretty_print(pp)
      pp.group(1, "#{self.class}[", "]") do
        pp.breakable ""
        pp.seplist(self, nil) do |key, val|
          pp.group do
            key.pretty_print(pp)
            pp.text " => "
            pp.group(1) do
              pp.breakable ""
              val.pretty_print(pp)
            end
          end
        end
      end
    end

    # Convert this `OrderedHash` to an instance of Ruby's built-in `Hash`.
    # The returned `Hash` iterates in the same (insertion) order.
    #
    # @return [::Hash]
    def to_hash
      output = {}
      each do |key, value|
        output[key] = value
      end
      output
    end
    alias :to_h :to_hash

    # Return a Proc which accepts a key as an argument and returns the
    # value. The Proc behaves like {#get} (when the key is missing, it
    # returns nil or the result of the default proc).
    #
    # @return [Proc]
    def to_proc
      lambda { |key| get(key) }
    end

    # @return [::Hash]
    # @private
    def marshal_dump
      to_hash
    end

    # @private
    def marshal_load(dictionary)
      trie = Trie.new(0)
      entries = []
      dictionary.each do |key, value|
        key = normalize_key(key)
        trie.put!(key, entries.size)
        entries << [key, value].freeze
      end
      @trie = entries.empty? ? EmptyTrie : trie
      @keys = entries.empty? ? EmptyVector : Vector.new(entries.freeze)
      @size = entries.size
      @default = nil
    end

    private

    # Duplicate and freeze unfrozen String keys, matching RubyHash's
    # behaviour. All other keys are stored as they are.
    def normalize_key(key)
      (key.is_a?(String) && !key.frozen?) ? key.dup.freeze : key
    end

    # Rebuild the internal structures from the live entries of `keys` (a
    # {Vector} of `[key, value]` pairs with `nil` holes), so that the slots
    # become dense again. Returns a `[trie, keys]` pair. Called from
    # {#delete} when the holes left behind by deletions outnumber the live
    # entries, which keeps positional access by {#key_at} from degrading
    # over time. Runs in O(n) time, amortized over the deletions which
    # created the holes.
    #
    # @private
    def compact_slots(keys)
      trie = Trie.new(0)
      entries = []
      keys.each do |pair|
        next unless pair
        trie.put!(pair[0], entries.size)
        entries << pair
      end
      [trie, Vector.new(entries.freeze)]
    end

    # Return a new `OrderedHash` which is derived from this one, using the
    # given internal structures. The new `OrderedHash` will retain the
    # existing default block, if there is one.
    #
    # @private
    def derive_new_hash(trie, keys, size)
      if size == 0
        if @default
          self.class.alloc(EmptyTrie, EmptyVector, 0, @default)
        else
          self.class.empty
        end
      elsif trie.equal?(@trie) && keys.equal?(@keys)
        self
      else
        self.class.alloc(trie, keys, size, @default)
      end
    end
  end

  # The canonical empty `OrderedHash`. Returned by `OrderedHash[]` when
  # invoked with no arguments; also returned by `OrderedHash.empty`. Prefer
  # using this one rather than creating many empty hashes using
  # `OrderedHash.new`.
  #
  # @private
  EmptyOrderedHash = Hamster::OrderedHash.empty
end
