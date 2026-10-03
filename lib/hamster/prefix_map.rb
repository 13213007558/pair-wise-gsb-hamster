require "hamster/immutable"
require "hamster/undefined"

module Hamster
  class PrefixMap
    include Immutable
    include Enumerable

    UTF8 = Encoding::UTF_8

    class RadixNode
      attr_reader :prefix, :value, :children

      def self.empty
        new("", Undefined, {})
      end

      def initialize(prefix, value = Undefined, children = {})
        @prefix = prefix
        @value = value
        @children = children.dup.freeze
        @ordered_children = @children.sort_by { |edge, _| edge.ord }.map { |_, child| child }.freeze
        @size = (terminal? ? 1 : 0)
        @ordered_children.each { |child| @size += child.size }
        freeze
      end

      def terminal?
        !@value.equal?(Undefined)
      end

      def size
        @size
      end

      def insert(key, value)
        common_length = common_prefix_length(@prefix, key)

        if common_length == @prefix.length
          insert_after_matching_prefix(key, value)
        else
          split_edge(key, value, common_length)
        end
      end

      def remove(key, root = false)
        return self unless key.start_with?(@prefix)

        if key.length == @prefix.length
          return self unless terminal?
          node = self.class.new(@prefix, Undefined, @children)
          return root ? node : node.compact
        end

        remainder = suffix(key, @prefix.length)
        child = @children[remainder[0]]
        return self unless child

        new_child = child.remove(remainder)
        return self if new_child.equal?(child)

        new_children = @children.dup
        if new_child.nil?
          new_children.delete(remainder[0])
        else
          new_children[remainder[0]] = new_child
        end

        node = self.class.new(@prefix, @value, new_children)
        root ? node : node.compact
      end

      def traverse(ancestor, &block)
        key = (ancestor + @prefix).freeze
        yield(key, @value) if terminal?
        @ordered_children.each { |child| child.traverse(key, &block) }
      end

      protected

      def compact
        return nil if !terminal? && @children.empty?
        return self if terminal? || @children.size != 1

        child = @ordered_children.first
        self.class.new(@prefix + child.prefix, child.value, child.children)
      end

      private

      def insert_after_matching_prefix(key, value)
        remainder = suffix(key, @prefix.length)

        if remainder.empty?
          return self if terminal? && value == @value
          return self.class.new(@prefix, value, @children)
        end

        child = @children[remainder[0]]
        new_child = child ? child.insert(remainder, value) : self.class.new(remainder, value)
        return self if new_child.equal?(child)

        self.class.new(@prefix, @value, @children.merge(remainder[0] => new_child))
      end

      def split_edge(key, value, common_length)
        common_prefix = @prefix[0, common_length]
        old_suffix = suffix(@prefix, common_length)
        new_suffix = suffix(key, common_length)
        old_node = self.class.new(old_suffix, @value, @children)

        if new_suffix.empty?
          self.class.new(common_prefix, value, old_suffix[0] => old_node)
        else
          new_node = self.class.new(new_suffix, value)
          children = { old_suffix[0] => old_node, new_suffix[0] => new_node }
          self.class.new(common_prefix, Undefined, children)
        end
      end

      def common_prefix_length(left, right)
        left_codepoints = left.each_codepoint
        right_codepoints = right.each_codepoint
        length = 0

        loop do
          begin
            left_codepoint = left_codepoints.next
            right_codepoint = right_codepoints.next
          rescue StopIteration
            return length
          end
          return length unless left_codepoint == right_codepoint
          length += 1
        end
      end

      def suffix(string, start)
        string[start, string.length - start]
      end
    end

    class << self
      def [](pairs = nil)
        if pairs.nil? || (pairs.respond_to?(:empty?) && pairs.empty?)
          empty
        else
          new(pairs)
        end
      end

      def empty
        @empty ||= new
      end

      def alloc(root = RadixNode.empty)
        obj = allocate
        obj.instance_variable_set(:@__hamster_immutable_memory__, Object.new)
        obj.tap do |map|
          map.instance_variable_set(:@root, root)
          map.send(:freeze)
        end
      end
    end

    def initialize(pairs = nil)
      @root = RadixNode.empty
      if pairs
        pairs.each { |key, value| @root = @root.insert(normalize_key(key), value) }
      end
    end

    def size
      @root.size
    end
    alias :length :size

    def empty?
      @root.size.zero?
    end

    def put(key, value = Undefined)
      key = normalize_key(key)
      if value.equal?(Undefined)
        raise ArgumentError, "wrong number of arguments (given 1, expected 2)" unless block_given?
        value = yield(key?(key) ? get(key) : nil)
      end

      root = @root.insert(key, value)
      root.equal?(@root) ? self : self.class.alloc(root)
    end
    alias :store :put

    def []=(*)
      raise NoMethodError, "Hamster::PrefixMap doesn't support `[]='; use `put' instead"
    end

    def delete(key)
      root = @root.remove(normalize_key(key), true)
      root = RadixNode.empty if root.nil?

      return self if root.equal?(@root)
      return self.class.empty if root.size.zero?
      self.class.alloc(root)
    end

    def delete?(key)
      key?(key) ? delete(key) : false
    end

    def clear
      self.class.empty
    end

    def key?(key)
      !find_entry(normalize_key(key)).equal?(Undefined)
    end
    alias :has_key? :key?
    alias :include? :key?
    alias :member? :key?

    def get(key)
      entry = find_entry(normalize_key(key))
      entry.equal?(Undefined) ? nil : entry
    end
    alias :[] :get

    def fetch(key, default = Undefined)
      entry = find_entry(normalize_key(key))
      return entry unless entry.equal?(Undefined)
      return yield(key) if block_given?
      return default unless default.equal?(Undefined)
      raise KeyError, "key not found: #{key.inspect}"
    end

    def longest_prefix(key)
      key = normalize_key(key)
      node = @root
      remainder = key
      matched = ""
      result = node.terminal? ? ["".freeze, node.value] : nil

      loop do
        break unless remainder.start_with?(node.prefix)
        current_matched = (matched + node.prefix).freeze
        result = [current_matched, node.value] if node.terminal?
        break if remainder.length == node.prefix.length

        next_remainder = suffix(remainder, node.prefix.length)
        child = node.children[next_remainder[0]]
        break unless child

        node = child
        remainder = next_remainder
        matched = current_matched
      end

      result
    end
    alias :longest_prefix_pair :longest_prefix
    alias :longest_prefix_match :longest_prefix

    def longest_prefix_key(key)
      pair = longest_prefix(key)
      pair && pair[0]
    end

    def longest_prefix_value(key)
      pair = longest_prefix(key)
      pair && pair[1]
    end

    def each(prefix = nil, &block)
      return enum_for(:each, prefix) unless block_given?

      if prefix.nil?
        @root.traverse("", &block)
      else
        node, ancestor = subtree_for(normalize_key(prefix))
        node.traverse(ancestor, &block) if node
      end
      self
    end
    alias :each_pair :each
    alias :each_with_prefix :each
    alias :with_prefix :each
    alias :each_prefix :each

    def each_key(prefix = nil)
      return enum_for(:each_key, prefix) unless block_given?
      each(prefix) { |key, _| yield(key) }
      self
    end

    def each_value(prefix = nil)
      return enum_for(:each_value, prefix) unless block_given?
      each(prefix) { |_, value| yield(value) }
      self
    end

    def select
      return enum_for(:select) unless block_given?
      pairs = []
      each { |key, value| pairs << [key, value] if yield(key, value) }
      self.class.new(pairs)
    end

    def merge(other)
      result = self
      other.each { |key, value| result = result.put(key, value) }
      result
    end

    def eql?(other)
      return true if equal?(other)
      return false unless instance_of?(other.class) && size == other.size

      to_a.each_with_index do |(key, value), index|
        other_key, other_value = other.to_a[index]
        return false unless key.eql?(other_key) && value.eql?(other_value)
      end
      true
    end

    def ==(other)
      eql?(other) || (other.respond_to?(:to_hash) && to_hash == other.to_hash)
    end

    def hash
      to_a.reduce(0) do |digest, pair|
        (digest << 32) - digest + pair[0].hash + pair[1].hash
      end
    end

    def inspect
      result = "#{self.class}["
      index = 0
      each do |key, value|
        result << ", " if index > 0
        result << key.inspect << " => " << value.inspect
        index += 1
      end
      result << "]"
    end

    def pretty_print(pp)
      pp.group(1, "#{self.class}[", "]") do
        pp.breakable ""
        pp.seplist(self, nil) do |key, value|
          pp.group do
            key.pretty_print(pp)
            pp.text " => "
            pp.group(1) do
              pp.breakable ""
              value.pretty_print(pp)
            end
          end
        end
      end
    end

    def to_hash
      result = {}
      each { |key, value| result[key] = value }
      result
    end
    alias :to_h :to_hash

    def marshal_dump
      to_hash
    end

    def marshal_load(dictionary)
      @root = RadixNode.empty
      dictionary.each { |key, value| @root = @root.insert(normalize_key(key), value) }
    end

    private

    def normalize_key(key)
      raise TypeError, "key must be a String" unless key.is_a?(::String)

      normalized = key.encoding == UTF8 ? key.dup : key.encode(UTF8)
      unless normalized.valid_encoding?
        raise ArgumentError, "key must have a valid Unicode encoding"
      end
      normalized.freeze
    rescue ::EncodingError
      raise ArgumentError, "key must have a valid Unicode encoding"
    end

    def find_entry(key)
      node = @root
      remainder = key

      loop do
        return Undefined unless remainder.start_with?(node.prefix)
        return node.value if remainder.length == node.prefix.length

        remainder = suffix(remainder, node.prefix.length)
        child = node.children[remainder[0]]
        return Undefined unless child
        node = child
      end
    end

    def subtree_for(prefix)
      node = @root
      remainder = prefix
      ancestor = ""

      loop do
        return [node, ancestor] if node.prefix.start_with?(remainder)
        return nil unless remainder.start_with?(node.prefix)

        child_remainder = suffix(remainder, node.prefix.length)
        child = node.children[child_remainder[0]]
        return nil unless child

        ancestor = (ancestor + node.prefix).freeze
        remainder = child_remainder
        node = child
      end
    end

    def suffix(string, start)
      string[start, string.length - start]
    end
  end
end
