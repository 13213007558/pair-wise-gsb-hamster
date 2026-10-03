require "hamster/hash"
require "hamster/ordered_trie"
require "hamster/vector"

module Hamster
  # An `OrderedHash` is an immutable {Hash} which enumerates its pairs in
  # insertion order. Key lookup uses the same `#hash` and `#eql?` rules as a
  # Ruby Hash. Storing a new value under an existing key updates the value in
  # place; deleting the key and reinserting it moves the key to the end.
  #
  # During {#merge}, keys already present in the receiver keep their original
  # position; keys only present in the merged collection are appended in that
  # collection's iteration order. This matches Ruby Hash's merge behavior.
  #
  # @example
  #   hash = Hamster::OrderedHash["a" => 1, "b" => 2]
  #   hash.put("a", 10).keys # => Hamster::Vector["a", "b"]
  #   hash.delete("a").put("a", 10).to_a
  #   # => [["b", 2], ["a", 10]]
  class OrderedHash < Hash
    class << self
      def alloc(trie = EmptyOrderedTrie, block = nil)
        trie = EmptyOrderedTrie if trie.nil? || trie.empty?
        obj = allocate
        obj.instance_variable_set(:@trie, trie)
        obj.instance_variable_set(:@default, block)
        obj
      end
    end

    def initialize(pairs = nil, &block)
      @trie = pairs ? OrderedTrie[pairs] : EmptyOrderedTrie
      @default = block
    end

    # Return the key at the given zero-based insertion position. Negative
    # positions count from the end. Returns `nil` if the position does not
    # exist.
    #
    # @param index [Integer] insertion position
    # @return [Object]
    def key_at(index)
      entry = @trie.at(index)
      entry && entry[0]
    end

    # Return a {Vector} containing the keys in insertion order.
    #
    # @return [Vector]
    def keys
      Vector.new(each_key.to_a)
    end

    # Return the `[key, value]` pair at the given zero-based insertion
    # position. Negative positions count from the end. Returns `nil` if the
    # position does not exist.
    #
    # @param index [Integer] insertion position
    # @return [Array]
    def pair_at(index)
      @trie.at(index)
    end
    alias :at :pair_at

    def slice(*wanted)
      trie = OrderedTrie.new
      wanted.each { |key| trie.send(:put_pair!, key, get(key)) if key?(key) }
      self.class.alloc(trie, @default)
    end

    def marshal_load(dictionary)
      @trie = OrderedTrie[dictionary]
    end
  end

  EmptyOrderedHash = OrderedHash.empty
end
