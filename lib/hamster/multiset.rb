require "hamster/immutable"
require "hamster/enumerable"
require "hamster/trie"

module Hamster
  # A `Hamster::Multiset` is an unordered collection which keeps track of how
  # many times each distinct item occurs. Item identity follows the same
  # `#hash` and `#eql?` rules as {Hamster::Set}.
  #
  # All multiplicities must be non-negative Integers. An item with a
  # multiplicity of zero is removed from the underlying trie. Operations return
  # new multisets and leave existing multisets unchanged.
  class Multiset
    include Immutable
    include Enumerable

    class << self
      # Create a new multiset from the given occurrences. Unlike {.new}, an
      # array argument is always treated as one item rather than a
      # key/multiplicity pair.
      def [](*items)
        return empty if items.empty?
        multiset = allocate
        multiset.send(:initialize, items, false)
        multiset.send(:immutable!)
        multiset
      end

      # Return an empty multiset. If used on a subclass, returns an empty
      # instance of that class.
      def empty
        @empty ||= alloc(EmptyTrie, 0)
      end

      # @private
      def alloc(trie = EmptyTrie, total = 0)
        allocate.tap do |multiset|
          multiset.instance_variable_set(:@trie, trie)
          multiset.instance_variable_set(:@total, total)
        end
      end
    end

    # A Hash (or any object responding to `#each_pair`) uses its values as
    # multiplicities. An array of `[item, multiplicity]` pairs is accepted too.
    # Any other Enumerable is treated as a sequence of individual occurrences.
    def initialize(items = nil, pairs = nil)
      @trie = Trie.new(0)
      @total = 0

      return if items.nil?

      if pairs.nil?
        pairs = items.respond_to?(:each_pair) || pair_array?(items)
      end

      if pairs
        if items.respond_to?(:each_pair)
          items.each_pair { |item, multiplicity| put_count!(item, multiplicity) }
        else
          items.each { |item, multiplicity| put_count!(item, multiplicity) }
        end
      else
        items.each { |item| put_count!(item, 1) }
      end
    end

    # Return `true` if this multiset contains no occurrences.
    def empty?
      @trie.empty?
    end

    # Return the total number of occurrences, including repeated items.
    def size
      @total
    end
    alias :length :size
    alias :cardinality :size
    alias :total_multiplicity :size
    alias :total :size
    alias :total_count :size

    # Return the number of distinct items.
    def distinct_size
      @trie.size
    end
    alias :distinct_count :distinct_size
    alias :unique_size :distinct_size
    alias :number_of_distinct_items :distinct_size
    alias :element_count :size

    # Return a new multiset with one additional occurrence of each item yielded
    # by the block. To replace a multiplicity, use {#put} with a pair.
    def map
      return enum_for(:map) unless block_given?
      return self if empty?
      self.class[*super]
    end
    alias :collect :map

    # Return the multiplicity of `item`, or 0 if it is absent.
    def multiplicity(item)
      entry = @trie.get(item)
      entry ? entry[1] : 0
    end
    alias :count_of :multiplicity
    alias :multiplicities :multiplicity
    alias :[] :multiplicity

    # Return a new multiset with `count` additional occurrences of `item`.
    def add(item, count = 1)
      validate_multiplicity(count)
      return self if count == 0
      put(item, multiplicity(item) + count)
    end
    alias :increment :add

    # Return a new multiset with up to `count` occurrences of `item` removed.
    # The resulting multiplicity is truncated at zero.
    def remove(item, count = 1)
      validate_multiplicity(count)
      current = multiplicity(item)
      return self if count == 0 || current == 0
      remaining = current - count
      return delete(item) if remaining <= 0
      trie = @trie.put(item, remaining)
      new_trie(trie, @total - count)
    end
    alias :decrement :remove

    # Return a new multiset in which `item` has the given multiplicity. A
    # multiplicity of zero removes the item.
    def put(item, count)
      validate_multiplicity(count)
      current = multiplicity(item)
      return self if count == current

      trie = count == 0 ? @trie.delete(item) : @trie.put(item, count)
      new_trie(trie, @total - current + count)
    end
    alias :set_multiplicity :put

    # Return a new multiset with occurrences of `item` removed. Without a
    # count, all occurrences are removed. With a count, removal is truncated at
    # zero.
    def delete(item, count = nil)
      return remove(item, count) unless count.nil?
      current = multiplicity(item)
      return self if current == 0
      new_trie(@trie.delete(item), @total - current)
    end

    # Call the block once for every occurrence in this multiset.
    def each
      return to_enum unless block_given?
      each_with_multiplicity do |item, multiplicity|
        multiplicity.times { yield(item) }
      end
      self
    end

    # Call the block once for each distinct item, passing its multiplicity.
    def each_with_multiplicity
      return enum_for(:each_with_multiplicity) unless block_given?
      @trie.each { |item, multiplicity| yield(item, multiplicity) }
      self
    end
    alias :each_pair :each_with_multiplicity

    # Return `true` if at least one occurrence of `item` is present.
    def include?(item)
      @trie.key?(item)
    end
    alias :member? :include?

    # Return a new multiset containing the items for which the block returns
    # true. Their multiplicities are preserved.
    def select
      return enum_for(:select) unless block_given?
      pairs = []
      each_with_multiplicity do |item, multiplicity|
        pairs << [item, multiplicity] if yield(item)
      end
      self.class.new(pairs, true)
    end
    alias :find_all :select

    # Return one distinct item from this multiset, or `nil` when empty.
    def first
      entry = @trie.at(0)
      entry && entry[0]
    end

    # Add corresponding multiplicities.
    def sum(other)
      other = coerce(other)
      combine(other) { |left, right| left + right }
    end
    alias :+ :sum
    alias :concat :sum

    # Keep the larger multiplicity for each item.
    def union(other)
      other = coerce(other)
      combine(other) { |left, right| [left, right].max }
    end
    alias :| :union
    alias :merge :union

    # Keep the smaller multiplicity for items present in both multisets.
    def intersection(other)
      other = coerce(other)
      combine(other, false, false) { |left, right| [left, right].min }
    end
    alias :& :intersection

    # Subtract corresponding multiplicities, truncating each result at zero.
    def difference(other)
      other = coerce(other)
      combine(other, true, false) do |left, right|
        left > right ? left - right : nil
      end
    end
    alias :- :difference
    alias :subtract :difference

    # Return an empty multiset of the same class.
    def clear
      self.class.empty
    end

    # Return `true` when `other` is the same class with equal multiplicities.
    def eql?(other)
      return true if other.equal?(self)
      return false unless instance_of?(other.class)
      other_trie = other.instance_variable_get(:@trie)
      return false if @trie.size != other_trie.size
      @trie.each { |item, multiplicity| return false unless other_trie.include?(item, multiplicity) }
      true
    end

    # See `Object#hash`.
    def hash
      each_with_multiplicity.reduce(0) { |hash, (item, count)| ((hash << 5) - hash) ^ item.hash ^ count }
    end

    # @private
    def marshal_dump
      each_with_multiplicity.each_with_object({}) { |(item, count), output| output[item] = count }
    end

    # @private
    def marshal_load(pairs)
      @trie = Trie.new(0)
      @total = 0
      pairs.each { |item, count| put_count!(item, count) }
    end

    private

    def pair_array?(items)
      items.is_a?(::Array) &&
        !items.empty? &&
        items.all? { |item| item.is_a?(::Array) && item.length == 2 && item[1].is_a?(::Integer) }
    end

    def put_count!(item, count)
      validate_multiplicity(count)
      return if count == 0
      current = multiplicity(item)
      @trie.put!(item, current + count)
      @total += count
    end

    def validate_multiplicity(count)
      unless count.is_a?(::Integer)
        raise ArgumentError, "multiplicity must be an Integer: #{count.inspect}"
      end
      raise ArgumentError, "multiplicity cannot be negative: #{count}" if count < 0
    end

    def coerce(other)
      return other if other.is_a?(Multiset)
      self.class.new(other)
    end

    def combine(other, keep_left = true, keep_right = true)
      trie = @trie.combine(other.instance_variable_get(:@trie), keep_left, keep_right) do |left, right|
        yield(left, right)
      end
      new_trie(trie)
    end

    def new_trie(trie, total = nil)
      return self.class.empty if trie.nil? || trie.empty?
      return self if trie.equal?(@trie)
      total ||= trie.reduce(0) { |sum, (_, count)| sum + count }
      self.class.alloc(trie, total)
    end
  end

  MultiSet = Multiset
  Bag = Multiset
  EmptyMultiset = Hamster::Multiset.empty
end
