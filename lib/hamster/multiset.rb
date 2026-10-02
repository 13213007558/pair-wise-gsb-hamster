require "hamster/immutable"
require "hamster/enumerable"
require "hamster/trie"

module Hamster

  # An immutable collection which keeps a non-negative multiplicity for every
  # distinct item. Items are considered identical when they have the same
  # `#hash` and are `#eql?`. Zero multiplicities are never stored.
  #
  # Binary operations combine multiplicities as follows:
  #
  # - `+`: add multiplicities
  # - `|`: take the larger multiplicity
  # - `&`: take the smaller multiplicity
  # - `-`: subtract and truncate the result at zero
  #
  # @example
  #   Hamster::Multiset["a", "a", "b"] + Hamster::Multiset["a", "b", "b"]
  #   # => Hamster::Multiset["a", "a", "a", "b", "b", "b"]
  #
  class Multiset
    include Immutable
    include Enumerable

    class << self
      # Create a new `Multiset`. A single mapping of items to multiplicities is
      # interpreted as explicit multiplicities; any other argument is treated
      # as an `Enumerable` of occurrences.
      #
      # @return [Multiset]
      def [](*items)
        items.length == 1 ? new(items.first) : new(items)
      end

      # Return an empty `Multiset`. If used on a subclass, returns an empty
      # instance of that class.
      #
      # @return [Multiset]
      def empty
        @empty ||= alloc(EmptyTrie)
      end

      # "Raw" allocation of a new `Multiset`.
      #
      # @return [Multiset]
      # @private
      def alloc(trie)
        total = 0
        trie.each { |_, multiplicity| total += multiplicity }
        allocate.tap do |multiset|
          multiset.instance_variable_set(:@trie, trie)
          multiset.instance_variable_set(:@total, total)
        end
      end
    end

    # @param items [Enumerable, Object] occurrences, or an item-to-multiplicity mapping
    def initialize(items = [])
      @trie = Trie.new(0)
      @total = 0

      if items.is_a?(Multiset)
        @trie = items.instance_variable_get(:@trie)
        @total = items.instance_variable_get(:@total)
      elsif count_mapping?(items)
        items.each_pair { |item, multiplicity| put_initial_multiplicity(item, multiplicity) }
      elsif pair_list?(items)
        items.each { |item, multiplicity| put_initial_multiplicity(item, multiplicity) }
      elsif items.is_a?(::Enumerable)
        items.each { |item| add_initial_occurrence(item) }
      else
        add_initial_occurrence(items)
      end
    end

    # Return `true` if this multiset contains no occurrences.
    # @return [Boolean]
    def empty?
      @trie.empty?
    end

    # Return the total number of occurrences in this multiset.
    # @return [Integer]
    def size
      @total
    end
    alias :length :size
    alias :cardinality :size
    alias :total_count :size
    alias :total_multiplicity :size

    # Return the number of distinct items in this multiset.
    # @return [Integer]
    def distinct_size
      @trie.size
    end
    alias :distinct_count :distinct_size
    alias :number_of_distinct_elements :distinct_size
    alias :unique_size :distinct_size

    # Yield each occurrence. An item with multiplicity 3 is yielded three
    # times. If no block is given, an `Enumerator` is returned.
    #
    # @return [self, Enumerator]
    def each
      return to_enum(:each) unless block_given?
      @trie.each do |item, multiplicity|
        multiplicity.times { yield(item) }
      end
      self
    end

    # Yield each distinct item once with its multiplicity.
    # @return [self, Enumerator]
    def each_pair
      return to_enum(:each_pair) unless block_given?
      @trie.each { |item, multiplicity| yield(item, multiplicity) }
      self
    end
    alias :each_with_multiplicity :each_pair

    def reverse_each
      return enum_for(:reverse_each) unless block_given?
      @trie.reverse_each do |item, multiplicity|
        multiplicity.times { yield(item) }
      end
      self
    end

    # Return the multiplicity of `item`, or zero if it is absent.
    # @return [Integer]
    def multiplicity(item)
      entry = @trie.get(item)
      entry ? entry[1] : 0
    end
    alias :count_for :multiplicity
    alias :copies :multiplicity

    def [](item)
      multiplicity(item)
    end

    def count(item = nil)
      item.nil? && !block_given? ? size : super
    end

    # Return `true` if this multiset contains at least one occurrence of item.
    # @return [Boolean]
    def include?(item)
      @trie.key?(item)
    end
    alias :member? :include?

    # Return a new multiset with `multiplicity` additional occurrences.
    # @return [Multiset]
    def add(item, multiplicity = 1)
      validate_non_negative_integer(multiplicity)
      return self if multiplicity == 0
      new_trie(@trie.put(item, self.multiplicity(item) + multiplicity))
    end
    alias :<< :add
    alias :increment :add

    # Set the absolute multiplicity of an item. A multiplicity of zero removes
    # the item entirely.
    # @return [Multiset]
    def put(item, multiplicity)
      validate_non_negative_integer(multiplicity)
      return delete(item) if multiplicity == 0
      new_trie(@trie.put(item, multiplicity))
    end
    alias :set_multiplicity :put

    # Remove one or all occurrences of an item. The result is truncated at
    # zero, so items whose multiplicity reaches zero disappear.
    # @return [Multiset]
    def delete(item, multiplicity = nil)
      if multiplicity.nil?
        new_trie(@trie.delete(item))
      else
        validate_non_negative_integer(multiplicity)
        return self if multiplicity == 0
        remaining = self.multiplicity(item) - multiplicity
        remaining <= 0 ? new_trie(@trie.delete(item)) : new_trie(@trie.put(item, remaining))
      end
    end
    alias :remove :delete

    # Return the multiplicity-wise sum of the two multisets.
    # @return [Multiset]
    def sum(other)
      combine(other, :+)
    end
    alias :+ :sum
    alias :merge :sum
    alias :multiplicities_add :sum

    # Return the multiplicity-wise maximum (union).
    # @return [Multiset]
    def union(other)
      combine(other, :max)
    end
    alias :| :union
    alias :maximum_union :union

    # Return the multiplicity-wise minimum (intersection).
    # @return [Multiset]
    def intersection(other)
      combine(other, :min)
    end
    alias :& :intersection
    alias :minimum_intersection :intersection

    # Subtract multiplicities, truncating each item at zero.
    # @return [Multiset]
    def difference(other)
      combine(other, :-)
    end
    alias :- :difference
    alias :subtract :difference
    alias :truncated_difference :difference

    # Return a new multiset with all occurrences of filtered-in distinct
    # items retained.
    # @return [Multiset]
    def select
      return enum_for(:select) unless block_given?
      new_trie(@trie.select { |item, _| yield(item) })
    end
    alias :find_all :select

    def map
      return enum_for(:map) unless block_given?
      return self if empty?
      self.class.new(super)
    end
    alias :collect :map

    # Return one occurrence from this multiset.
    # @return [Object]
    def first
      entry = @trie.at(0)
      entry && entry[0]
    end

    # Return an empty multiset of the same class.
    # @return [Multiset]
    def clear
      self.class.empty
    end

    # Return the distinct items and their multiplicities as a Ruby Hash.
    # @return [Hash]
    def to_counts
      result = {}
      each_pair { |item, multiplicity| result[item] = multiplicity }
      result
    end
    alias :to_h :to_counts

    # Return `true` if `other` has the same type and item multiplicities.
    # @return [Boolean]
    def eql?(other)
      return true if equal?(other)
      return false unless instance_of?(other.class)
      other_trie = other.instance_variable_get(:@trie)
      @trie.eql?(other_trie)
    end
    alias :== :eql?

    def hash
      result = 0
      @trie.each do |item, multiplicity|
        result ^= item.hash ^ multiplicity.hash
      end
      result
    end

    undef :each_index

    # @private
    def marshal_dump
      to_counts
    end

    # @private
    def marshal_load(counts)
      initialize(counts)
      immutable!
    end

    private

    def count_mapping?(object)
      object.respond_to?(:each_pair)
    end

    def pair_list?(object)
      object.is_a?(::Array) &&
        !object.empty? &&
        object.all? { |item| item.is_a?(::Array) && item.length == 2 }
    end

    def add_initial_occurrence(item)
      @total += 1
      @trie.put!(item, multiplicity(item) + 1)
    end

    def put_initial_multiplicity(item, multiplicity)
      validate_non_negative_integer(multiplicity)
      return if multiplicity == 0
      @total += multiplicity
      @trie.put!(item, multiplicity)
    end

    def validate_non_negative_integer(value)
      return if value.is_a?(::Integer) && value >= 0
      raise ArgumentError, "multiplicity must be a non-negative Integer"
    end

    def combine(other, operation)
      other_trie = trie_for(other)
      new_trie(@trie.combine(other_trie, operation))
    end

    def trie_for(object)
      case object
      when Multiset
        object.instance_variable_get(:@trie)
      else
        self.class.new(object).instance_variable_get(:@trie)
      end
    end

    def new_trie(trie)
      if trie.equal?(@trie)
        self
      elsif trie.empty?
        self.class.empty
      else
        self.class.alloc(trie)
      end
    end
  end

  # @private
  EmptyMultiset = Hamster::Multiset.empty

  # Compatibility alias.
  MultiSet = Multiset
end
