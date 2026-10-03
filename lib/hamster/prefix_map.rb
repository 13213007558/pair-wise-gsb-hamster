require "hamster/immutable"
require "hamster/undefined"
require "hamster/enumerable"

module Hamster
  # A `Hamster::PrefixMap` maps string keys to values, organized as an
  # immutable, persistent compressed prefix tree (radix tree) over the Unicode
  # codepoints of its keys. Besides the usual map operations, it supports
  # longest-prefix lookup and lazy enumeration of all entries whose key starts
  # with a given prefix.
  #
  # Keys are compared by their Unicode codepoints. No case folding or Unicode
  # normalization is ever applied: `"A"` and `"a"` are different keys, and so
  # are precomposed and decomposed spellings of the same character. Keys whose
  # bytes are not valid for their encoding are rejected with an
  # `ArgumentError`. The empty string is a valid key, and `nil` is a valid
  # value which is never confused with a missing key.
  #
  #     map = Hamster::PrefixMap["services" => 1, "service" => 2]
  #     map.longest_prefix("services/api")  # => "services"
  #     map.each_prefix("serv").to_a        # => [["service", 2], ["services", 1]]
  #
  # Like the other Hamster collections, every "modifying" method returns a new
  # map and leaves the receiver untouched, so old versions remain usable.
  class PrefixMap
    include Immutable
    include Enumerable

    # @private
    class Edge
      include Immutable

      attr_reader :label, :node

      def initialize(label, node)
        @label = label.freeze
        @node = node
      end
    end

    # @private
    class Node
      include Immutable

      attr_reader :entry, :children

      def initialize(entry = nil, children = {})
        @entry = entry
        @children = children.freeze
      end
    end

    # @private
    EmptyNode = Node.new

    class << self
      # Create a new `PrefixMap` populated with the given key/value pairs.
      #
      # @example
      #   Hamster::PrefixMap["a" => 1, "ab" => 2] # => Hamster::PrefixMap["a" => 1, "ab" => 2]
      #
      # @param pairs [::Enumerable, nil] initial content, or nil for an empty map
      # @return [PrefixMap]
      def [](pairs = nil)
        (pairs.nil? || pairs.empty?) ? empty : new(pairs)
      end

      # Return an empty `PrefixMap`. If used on a subclass, returns an empty
      # instance of that class.
      #
      # @return [PrefixMap]
      def empty
        @empty ||= self.new
      end

      # @private
      def alloc(root, size)
        obj = allocate
        obj.instance_variable_set(:@root, root)
        obj.instance_variable_set(:@size, size)
        obj.__send__(:immutable!)
        obj
      end
    end

    # @param pairs [::Enumerable, nil] initial content, or nil for an empty map
    def initialize(pairs = nil)
      root = EmptyNode
      size = 0
      if pairs
        pairs.each do |key, value|
          cps = codepoints_for(key)
          size += 1 unless node_get(root, cps, 0)
          root = node_put(root, cps, 0, [store_key(key), value].freeze)
        end
      end
      @root = root
      @size = size
    end

    # Return the number of key/value pairs in this map.
    attr_reader :size

    # Return `true` if this map contains no key/value pairs.
    def empty?
      @size == 0
    end

    # Return the value associated with the given key, or `nil` if the key is
    # not present. Use {#key?} to distinguish a missing key from a `nil` value.
    #
    # @param key [String]
    # @return [Object]
    def get(key)
      entry = node_get(@root, codepoints_for(key), 0)
      entry && entry[1]
    end
    alias :[] :get

    # Return the value associated with the given key. If the key is not
    # present, return the default (or the result of the block, or raise
    # `KeyError` if neither is given).
    #
    # @param key [String]
    # @return [Object]
    def fetch(key, default = Undefined)
      entry = node_get(@root, codepoints_for(key), 0)
      if entry
        entry[1]
      elsif block_given?
        yield(key)
      elsif !default.equal?(Undefined)
        default
      else
        raise KeyError, "key not found: #{key.inspect}"
      end
    end

    # Return `true` if the given key is present in this map.
    #
    # @param key [String]
    def key?(key)
      !node_get(@root, codepoints_for(key), 0).nil?
    end
    alias :has_key? :key?
    alias :include? :key?
    alias :member? :key?

    # Return a new `PrefixMap` with the given key/value association added (or
    # replaced, if an equivalent key is already present). If a block is given
    # instead of a value, the block is called with the current value (or
    # `nil`) to compute the new value.
    #
    # @param key [String]
    # @return [PrefixMap]
    def put(key, value = yield(get(key)))
      cps = codepoints_for(key)
      old = node_get(@root, cps, 0)
      if old && old[1].equal?(value)
        self
      else
        entry = [store_key(key), value].freeze
        self.class.alloc(node_put(@root, cps, 0, entry), old ? @size : @size + 1)
      end
    end

    # @private
    # @raise NoMethodError
    def []=(*)
      raise NoMethodError, "Hamster::PrefixMap doesn't support `[]='; use `put' instead"
    end

    # Return a new `PrefixMap` with the given key removed. If the key is not
    # present, return `self`.
    #
    # @param key [String]
    # @return [PrefixMap]
    def delete(key)
      cps = codepoints_for(key)
      return self unless node_get(@root, cps, 0)
      self.class.alloc(node_delete(@root, cps, 0), @size - 1)
    end

    # Return an empty `PrefixMap`.
    #
    # @return [PrefixMap]
    def clear
      self.class.empty
    end

    # Return the longest key in this map which is a prefix of the given string,
    # or `nil` if there is none. If the empty string is a key, it matches
    # every string and acts as a default.
    #
    # @param string [String]
    # @return [String, nil]
    def longest_prefix(string)
      entry = longest_prefix_entry(string)
      entry && entry[0]
    end

    # Like {#longest_prefix}, but returns a `[key, value]` pair (or `nil`).
    #
    # @param string [String]
    # @return [Array, nil]
    def longest_prefix_entry(string)
      cps = codepoints_for(string)
      node = @root
      offset = 0
      best = node.entry
      while offset < cps.length
        edge = node.children[cps[offset]]
        break if edge.nil?
        label = edge.label
        matched = 0
        limit = label.length < cps.length - offset ? label.length : cps.length - offset
        matched += 1 while matched < limit && label[matched] == cps[offset + matched]
        break if matched < label.length
        offset += label.length
        node = edge.node
        best = node.entry if node.entry
      end
      best
    end

    # Call the block once for each key/value pair in this map, passing
    # `[key, value]`. No particular order is guaranteed. Returns an
    # `Enumerator` if no block is given.
    #
    # @return [self, Enumerator]
    def each(&block)
      return enum_for(:each) unless block
      traverse(@root, &block)
      self
    end

    # Call the block once for each key/value pair whose key starts with the
    # given prefix, passing `[key, value]`. The empty string matches every
    # entry. Returns a lazy `Enumerator` if no block is given, so the first
    # few matches can be taken without enumerating the whole subtree.
    #
    # @param prefix [String]
    # @return [self, Enumerator]
    def each_prefix(prefix, &block)
      return enum_for(:each_prefix, prefix) unless block
      node = locate(codepoints_for(prefix))
      traverse(node, &block) if node
      self
    end

    # Return a new `PrefixMap` with only the key/value pairs for which the
    # block returns a true value.
    #
    # @return [PrefixMap, Enumerator]
    def select
      return enum_for(:select) unless block_given?
      result = self.class.empty
      each do |key, value|
        result = result.put(key, value) if yield(key, value)
      end
      result
    end
    alias :find_all :select

    # Return `true` if the other map contains the same keys and values.
    def eql?(other)
      return true if other.equal?(self)
      return false unless other.instance_of?(self.class) && instance_of?(other.class)
      return false if other.size != @size
      each do |key, value|
        return false unless other.key?(key) && other.get(key).eql?(value)
      end
      true
    end
    alias :== :eql?

    # @return [String]
    def inspect
      result = "#{self.class}["
      first = true
      each do |key, value|
        result << ", " unless first
        result << key.inspect << " => " << value.inspect
        first = false
      end
      result << "]"
    end
    alias :to_s :inspect

    private

    def store_key(key)
      key.frozen? ? key : key.dup.freeze
    end

    def codepoints_for(key)
      unless key.is_a?(String)
        raise TypeError, "no implicit conversion of #{key.class} into String"
      end
      unless key.valid_encoding?
        raise ArgumentError, "invalid byte sequence in #{key.encoding}"
      end
      key.codepoints
    end

    def traverse(node)
      stack = [node]
      until stack.empty?
        current = stack.pop
        yield current.entry if current.entry
        current.children.each_value { |edge| stack.push(edge.node) }
      end
      nil
    end

    # Return the node whose subtree contains exactly the keys starting with
    # the given codepoints, or nil if there are none.
    def locate(cps)
      node = @root
      offset = 0
      while offset < cps.length
        edge = node.children[cps[offset]]
        return nil if edge.nil?
        label = edge.label
        remaining = cps.length - offset
        limit = label.length < remaining ? label.length : remaining
        matched = 0
        matched += 1 while matched < limit && label[matched] == cps[offset + matched]
        return nil if matched < label.length && matched < remaining
        return edge.node if matched == remaining
        offset += label.length
        node = edge.node
      end
      node
    end

    def node_get(node, cps, offset)
      return node.entry if offset == cps.length
      edge = node.children[cps[offset]]
      return nil if edge.nil?
      label = edge.label
      finish = offset + label.length
      return nil if finish > cps.length
      return nil unless label == cps[offset, label.length]
      node_get(edge.node, cps, finish)
    end

    def node_put(node, cps, offset, entry)
      if offset == cps.length
        Node.new(entry, node.children)
      else
        first = cps[offset]
        edge = node.children[first]
        if edge.nil?
          leaf = Edge.new(cps[offset..-1], Node.new(entry))
          Node.new(node.entry, node.children.merge(first => leaf))
        else
          label = edge.label
          limit = label.length < cps.length - offset ? label.length : cps.length - offset
          common = 0
          common += 1 while common < limit && label[common] == cps[offset + common]
          if common == label.length
            child = node_put(edge.node, cps, offset + label.length, entry)
            Node.new(node.entry, node.children.merge(first => Edge.new(label, child)))
          else
            rest = label[common..-1]
            middle_children = { rest[0] => Edge.new(rest, edge.node) }
            if offset + common == cps.length
              middle = Node.new(entry, middle_children)
            else
              branch = cps[(offset + common)..-1]
              middle_children[branch[0]] = Edge.new(branch, Node.new(entry))
              middle = Node.new(nil, middle_children)
            end
            Node.new(node.entry, node.children.merge(first => Edge.new(label[0...common], middle)))
          end
        end
      end
    end

    def node_delete(node, cps, offset)
      if offset == cps.length
        Node.new(nil, node.children)
      else
        first = cps[offset]
        edge = node.children[first]
        return node if edge.nil?
        label = edge.label
        finish = offset + label.length
        return node if finish > cps.length
        return node unless label == cps[offset, label.length]
        child = node_delete(edge.node, cps, finish)
        children = node.children
        if child.entry.nil? && child.children.empty?
          remaining = children.dup
          remaining.delete(first)
          Node.new(node.entry, remaining)
        elsif child.entry.nil? && child.children.size == 1
          sub_edge = child.children.values[0]
          merged = Edge.new(label + sub_edge.label, sub_edge.node)
          Node.new(node.entry, children.merge(first => merged))
        else
          Node.new(node.entry, children.merge(first => Edge.new(label, child)))
        end
      end
    end
  end
end
