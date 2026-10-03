require "hamster/trie"
require "hamster/sorted_set"

module Hamster
  # @private
  class OrderedTrie
    EmptyOrder = SortedSet.new([]) { |left, right| left[0] <=> right[0] }

    def self.[](pairs)
      new(0).tap do |trie|
        pairs.each { |key, value| trie.send(:put_pair!, key, value) }
      end
    end

    attr_reader :size

    def initialize(size = 0, entries = nil, serials = nil, order = nil, serial = 0)
      @size = size
      @entries = entries || EmptyTrie
      @serials = serials || EmptyTrie
      @order = order || EmptyOrder
      @serial = serial
    end

    def empty?
      @size == 0
    end

    def key?(key)
      @entries.key?(key)
    end

    def get(key)
      @entries.get(key)
    end

    def each(&block)
      @order.each { |node| block.call([node[1], node[2]]) }
      nil
    end

    def reverse_each(&block)
      @order.reverse_each { |node| yield([node[1], node[2]]) }
      nil
    end

    def reduce(memo)
      each { |entry| memo = yield(memo, entry) }
      memo
    end

    def select
      keys_to_delete = []
      each { |entry| keys_to_delete << entry[0] unless yield(entry) }
      bulk_delete(keys_to_delete)
    end

    def put(key, value)
      entry = @entries.get(key)
      if entry
        return self if entry[1].equal?(value)
        key = freeze_key(key)
        sequence = @serials.get(key)[1]
        node = order_node(sequence, key, value)
        OrderedTrie.new(@size, @entries.put(key, value), @serials,
          replace_order_node(node), @serial)
      else
        key = freeze_key(key)
        sequence = @serial
        node = order_node(sequence, key, value)
        OrderedTrie.new(@size + 1, @entries.put(key, value),
          @serials.put(key, sequence), @order.add(node), @serial + 1)
      end
    end

    def bulk_put(pairs)
      entries = @entries
      serials = @serials
      order = @order
      serial = @serial
      size = @size

      pairs.each do |key, value|
        existing = entries.get(key)
        if existing
          unless existing[1].equal?(value)
            key = freeze_key(key)
            sequence = serials.get(key)[1]
            node = order_node(sequence, key, value)
            entries = entries.put(key, value)
            order = order.delete(node).add(node)
          end
        else
          key = freeze_key(key)
          sequence = serial
          node = order_node(sequence, key, value)
          entries = entries.put(key, value)
          serials = serials.put(key, sequence)
          order = order.add(node)
          serial += 1
          size += 1
        end
      end

      if entries.equal?(@entries)
        self
      else
        OrderedTrie.new(size, entries, serials, order, serial)
      end
    end

    def delete(key)
      entry = @entries.get(key)
      return self unless entry
      sequence = @serials.get(key)[1]
      new_entries = @entries.delete(key)
      new_serials = @serials.delete(key)
      new_order = @order.delete(order_node(sequence, key, entry[1]))
      if new_entries.empty?
        OrderedTrie.new
      else
        OrderedTrie.new(@size - 1, new_entries, new_serials, new_order, @serial)
      end
    end

    def bulk_delete(keys)
      entries = @entries
      serials = @serials
      order = @order
      size = @size

      keys.each do |key|
        entry = entries.get(key)
        next unless entry
        sequence = serials.get(key)[1]
        entries = entries.delete(key)
        serials = serials.delete(key)
        order = order.delete(order_node(sequence, key, entry[1]))
        size -= 1
      end

      if entries.equal?(@entries)
        self
      elsif entries.empty?
        OrderedTrie.new
      else
        OrderedTrie.new(size, entries, serials, order, @serial)
      end
    end

    def include?(key, value)
      entry = get(key)
      entry && value.eql?(entry[1])
    end

    def at(index)
      node = @order.at(index)
      node && [node[1], node[2]]
    end

    def eql?(other)
      return true if equal?(other)
      return false unless other.is_a?(OrderedTrie) && size == other.size
      each do |entry|
        return false unless other.include?(entry[0], entry[1])
      end
      true
    end
    alias :== :eql?

    private

    def put_pair!(key, value)
      existing = @entries.get(key)
      key = freeze_key(key)
      if existing
        sequence = @serials.get(key)[1]
        node = order_node(sequence, key, value)
        @entries = @entries.put(key, value)
        @order = @order.delete(node).add(node)
      else
        sequence = @serial
        node = order_node(sequence, key, value)
        @entries = @entries.put(key, value)
        @serials = @serials.put(key, sequence)
        @order = @order.add(node)
        @serial += 1
        @size += 1
      end
      self
    end

    def replace_order_node(node)
      @order.delete(node).add(node)
    end

    def order_node(sequence, key, value)
      [sequence, key, value].freeze
    end

    def freeze_key(key)
      key.is_a?(::String) && !key.frozen? ? key.dup.freeze : key
    end
  end

  EmptyOrderedTrie = OrderedTrie.new
end
