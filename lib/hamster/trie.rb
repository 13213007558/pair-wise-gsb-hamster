module Hamster
  # @private
  class Trie
    def self.[](pairs)
      result = self.new(0)
      pairs.each { |key, val| result.put!(key, val) }
      result
    end

    def self.single_entry(significant_bits, index, key, value)
      entries = []
      entries[index] = [key, value].freeze
      new(significant_bits, 1, entries, [])
    end

    # Returns the number of key-value pairs in the trie.
    attr_reader :size

    def initialize(significant_bits, size = 0, entries = [], children = [])
      @significant_bits = significant_bits
      @entries = entries
      @children = children
      @size = size
    end

    # Returns <tt>true</tt> if the trie contains no key-value pairs.
    def empty?
      size == 0
    end

    # Returns <tt>true</tt> if the given key is present in the trie.
    def key?(key)
      !!get(key)
    end

    # Calls <tt>block</tt> once for each entry in the trie, passing the key-value pair as parameters.
    def each(&block)
      # TODO: Using block.call here is slower than using yield by 5-10%, but
      # the latter segfaults on ruby 2.2 and above. Once that is fixed and
      # broken versions are sufficiently old, we should revert back to yield
      # with a warning that the broken versions are unsupported.
      #
      # For more context:
      # * https://bugs.ruby-lang.org/issues/11451
      # * https://github.com/hamstergem/hamster/issues/189
      @entries.each { |entry| block.call(entry) if entry }
      @children.each do |child|
        child.each(&block) if child
      end
      nil
    end

    def reverse_each(&block)
      @children.reverse_each do |child|
        child.reverse_each(&block) if child
      end
      @entries.reverse_each { |entry| yield(entry) if entry }
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

    # @return [Trie] A copy of `self` with the given value associated with the
    #   key (or `self` if no modification was needed because an identical
    #   key-value pair wes already stored
    def put(key, value)
      index = index_for(key)
      entry = @entries[index]

      if !entry
        entries = @entries.dup
        key = key.dup.freeze if key.is_a?(String) && !key.frozen?
        entries[index] = [key, value].freeze
        Trie.new(@significant_bits, @size + 1, entries, @children)
      elsif entry[0].eql?(key)
        if entry[1].equal?(value)
          self
        else
          entries = @entries.dup
          key = key.dup.freeze if key.is_a?(String) && !key.frozen?
          entries[index] = [key, value].freeze
          Trie.new(@significant_bits, @size, entries, @children)
        end
      else
        child = @children[index]
        if child
          new_child = child.put(key, value)
          if new_child.equal?(child)
            self
          else
            children = @children.dup
            children[index] = new_child
            new_self_size = @size + (new_child.size - child.size)
            Trie.new(@significant_bits, new_self_size, @entries, children)
          end
        else
          children = @children.dup
          children[index] = Trie.new(@significant_bits + 5).put!(key, value)
          Trie.new(@significant_bits, @size + 1, @entries, children)
        end
      end
    end

    # Put multiple elements into a Trie.  This is more efficient than several
    # calls to `#put`.
    #
    # @param key_value_pairs Enumerable of pairs (`[key, value]`)
    # @return [Trie] A copy of `self` after associated the given keys and
    #   values (or `self` if no modifications where needed).
    def bulk_put(key_value_pairs)
      new_entries = nil
      new_children = nil
      new_size = @size

      key_value_pairs.each do |key, value|
        index = index_for(key)
        entry = (new_entries || @entries)[index]

        if !entry
          new_entries ||= @entries.dup
          key = key.dup.freeze if key.is_a?(String) && !key.frozen?
          new_entries[index] = [key, value].freeze
          new_size += 1
        elsif entry[0].eql?(key)
          if !entry[1].equal?(value)
            new_entries ||= @entries.dup
            key = key.dup.freeze if key.is_a?(String) && !key.frozen?
            new_entries[index] = [key, value].freeze
          end
        else
          child = (new_children || @children)[index]
          if child
            new_child = child.put(key, value)
            if !new_child.equal?(child)
              new_children ||= @children.dup
              new_children[index] = new_child
              new_size += new_child.size - child.size
            end
          else
            new_children ||= @children.dup
            new_children[index] = Trie.new(@significant_bits + 5).put!(key, value)
            new_size += 1
          end
        end
      end

      if new_entries || new_children
        Trie.new(@significant_bits, new_size, new_entries || @entries, new_children || @children)
      else
        self
      end
    end

    # Returns a copy combined with another trie. When both tries contain the
    # same key, the block chooses the new value; nil removes the key.
    def combine(other, keep_left = true, keep_right = true, &block)
      return self if equal?(other)
      combine_nodes(self, other, keep_left, keep_right, &block)
    end

    # Combine one bucket from each trie. The pair arguments are entries which
    # occupy that bucket directly. The node arguments are collision children.
    def legacy_combine_bucket(index, left_pair, right_pair, left_node, right_node,
                       keep_left, keep_right, &block)
      legacy_combine_pairs(
        left_pair, left_node,
        right_pair, right_node,
        @significant_bits + 5, keep_left, keep_right, &block
      )
    end

    def combine_pairs(left_pair, left_node, right_pair, right_node, bits,
                      keep_left, keep_right, &block)
      if left_pair && right_pair && left_pair[0].eql?(right_pair[0])
        value = yield(left_pair[1], right_pair[1])
        children = combine_nodes(left_node, right_node, bits + 5,
                                 keep_left, keep_right, &block)
        return children if value.nil?
        return Trie.single_entry(bits, index_for_at(bits, left_pair[0]), left_pair[0], value) unless children
        return left_node if value == left_pair[1] && left_node && !right_node
        return right_node if value == right_pair[1] && right_node && !left_node

        node = children || Trie.new(bits)
        Trie.single_entry(bits, index_for_at(bits, left_pair[0]), left_pair[0], value)
          .combine(node, true, true, &block)
      elsif left_pair && right_pair
        left = Trie.single_entry(bits, index_for_at(bits, left_pair[0]), left_pair[0], left_pair[1])
        right = Trie.single_entry(bits, index_for_at(bits, right_pair[0]), right_pair[0], right_pair[1])
        left = left.combine(left_node || Trie.new(bits), true, true) { |l, r| l } unless left_node
        right = right.combine(right_node || Trie.new(bits), true, true) { |l, r| r } unless right_node
        left.combine(right, keep_left, keep_right, &block)
      elsif left_pair
        if right_node
          pair_node = Trie.single_entry(bits, index_for_at(bits, left_pair[0]), left_pair[0], left_pair[1])
          pair_node = pair_node.combine(left_node, true, true) { |l, _| l } if left_node
          pair_node.combine(right_node, keep_left, keep_right, &block)
        elsif keep_left
          node = Trie.single_entry(bits, index_for_at(bits, left_pair[0]), left_pair[0], left_pair[1])
          left_node ? node.combine(left_node, true, true) { |l, _| l } : node
        end
      elsif right_pair
        if left_node
          pair_node = Trie.single_entry(bits, index_for_at(bits, right_pair[0]), right_pair[0], right_pair[1])
          pair_node = pair_node.combine(right_node, true, true) { |_, r| r } if right_node
          left_node.combine(pair_node, keep_left, keep_right, &block)
        elsif keep_right
          node = Trie.single_entry(bits, index_for_at(bits, right_pair[0]), right_pair[0], right_pair[1])
          right_node ? node.combine(right_node, true, true) { |_, r| r } : node
        end
      else
        combine_nodes(left_node, right_node, bits, keep_left, keep_right, &block)
      end
    end

    def combine_nodes(left_node, right_node, bits, keep_left, keep_right, &block)
      if left_node && right_node
        left_node.combine(right_node, keep_left, keep_right, &block)
      elsif left_node
        keep_left ? left_node : nil
      elsif right_node
        keep_right ? right_node : nil
      end
    end

    def index_for_at(bits, key)
      (key.hash.abs >> bits) & 31
    end

    # Returns <tt>self</tt> after overwriting the element associated with the specified key.
    def put!(key, value)
      index = index_for(key)
      entry = @entries[index]
      if !entry
        @size += 1
        key = key.dup.freeze if key.is_a?(String) && !key.frozen?
        @entries[index] = [key, value].freeze
      elsif entry[0].eql?(key)
        key = key.dup.freeze if key.is_a?(String) && !key.frozen?
        @entries[index] = [key, value].freeze
      else
        child = @children[index]
        if child
          old_child_size = child.size
          @children[index] = child.put!(key, value)
          @size += child.size - old_child_size
        else
          @children[index] = Trie.new(@significant_bits + 5).put!(key, value)
          @size += 1
        end
      end
      self
    end

    # Retrieves the entry corresponding to the given key. If not found, returns <tt>nil</tt>.
    def get(key)
      index = index_for(key)
      entry = @entries[index]
      if entry && entry[0].eql?(key)
        entry
      else
        child = @children[index]
        child.get(key) if child
      end
    end

    # Returns a copy of <tt>self</tt> with the given key (and associated value) deleted. If not found, returns <tt>self</tt>.
    def delete(key)
      find_and_delete(key) || Trie.new(@significant_bits)
    end

    # Delete multiple elements from a Trie.  This is more efficient than
    # several calls to `#delete`.
    #
    # @param keys [Enumerable] The keys to delete
    # @return [Trie]
    def bulk_delete(keys)
      new_entries = nil
      new_children = nil
      new_size = @size

      keys.each do |key|
        index = index_for(key)
        entry = (new_entries || @entries)[index]
        if !entry
          next
        elsif entry[0].eql?(key)
          new_entries ||= @entries.dup
          child = (new_children || @children)[index]
          if child
            # Bring up the first entry from the child into entries
            new_children ||= @children.dup
            new_children[index] = child.delete_at do |entry|
              new_entries[index] = entry
            end
          else
            new_entries[index] = nil
          end
          new_size -= 1
        else
          child = (new_children || @children)[index]
          if child
            copy = child.find_and_delete(key)
            unless copy.equal?(child)
              new_children ||= @children.dup
              new_children[index] = copy
              new_size -= (child.size - copy_size(copy))
            end
          end
        end
      end

      if new_entries || new_children
        Trie.new(@significant_bits, new_size, new_entries || @entries, new_children || @children)
      else
        self
      end
    end

    def include?(key, value)
      entry = get(key)
      entry && value.eql?(entry[1])
    end

    def at(index)
      @entries.each do |entry|
        if entry
          return entry if index == 0
          index -= 1
        end
      end
      @children.each do |child|
        if child
          if child.size >= index+1
            return child.at(index)
          else
            index -= child.size
          end
        end
      end
      nil
    end

    # Returns <tt>true</tt> if . <tt>eql?</tt> is synonymous with <tt>==</tt>
    def eql?(other)
      return true if equal?(other)
      return false unless instance_of?(other.class) && size == other.size
      each do |entry|
        return false unless other.include?(entry[0], entry[1])
      end
      true
    end
    alias :== :eql?

    protected

    # Returns a replacement instance after removing the specified key.
    # If not found, returns <tt>self</tt>.
    # If empty, returns <tt>nil</tt>.
    def find_and_delete(key)
      index = index_for(key)
      entry = @entries[index]
      if entry && entry[0].eql?(key)
        return delete_at(index)
      else
        child = @children[index]
        if child
          copy = child.find_and_delete(key)
          unless copy.equal?(child)
            children = @children.dup
            children[index] = copy
            new_size = @size - (child.size - copy_size(copy))
            return Trie.new(@significant_bits, new_size, @entries, children)
          end
        end
      end
      self
    end

    # Returns a replacement instance after removing the specified entry. If empty, returns <tt>nil</tt>
    def delete_at(index = @entries.index { |e| e })
      yield(@entries[index]) if block_given?
      if size > 1
        entries = @entries.dup
        child = @children[index]
        if child
          children = @children.dup
          children[index] = child.delete_at do |entry|
            entries[index] = entry
          end
        else
          entries[index] = nil
        end
        Trie.new(@significant_bits, @size - 1, entries, children || @children)
      end
    end

    private

    def combine_nodes(left, right, keep_left, keep_right, &block)
      return keep_left ? left : nil unless right
      return keep_right ? right : nil unless left

      left_entries = left.instance_variable_get(:@entries)
      right_entries = right.instance_variable_get(:@entries)
      left_children = left.instance_variable_get(:@children)
      right_children = right.instance_variable_get(:@children)
      entries = nil
      children = nil
      changed = false

      32.times do |index|
        left_entry = left_entries[index]
        right_entry = right_entries[index]
        left_child = left_children[index]
        right_child = right_children[index]

        next unless left_entry || right_entry || left_child || right_child

        if left_entry && right_entry && left_entry[0].eql?(right_entry[0])
          value = yield(left_entry[1], right_entry[1])
          child = combine_nodes(left_child, right_child, keep_left, keep_right, &block)

          if value.nil?
            entries ||= left_entries.dup
            entries[index] = nil
            changed = true
          elsif value != left_entry[1]
            entries ||= left_entries.dup
            entries[index] = [left_entry[0], value].freeze
            changed = true
          end

          if child.nil?
            if left_child
              children ||= left_children.dup
              children[index] = nil
              changed = true
            end
          elsif !child.equal?(left_child)
            children ||= left_children.dup
            children[index] = child
            changed = true
          end
        else
          child = combine_bucket(
            left_child, left_entry,
            right_child, right_entry,
            keep_left, keep_right, &block
          )

          if child.nil?
            if left_entry || left_child
              entries ||= left_entries.dup
              children ||= left_children.dup
              entries[index] = nil
              children[index] = nil
              changed = true
            end
          elsif child.equal?(left_child) && !left_entry
            next
          elsif child.size == 1 &&
                ((left_entry && !right_entry && !left_child && keep_left && child.at(0)[0].eql?(left_entry[0])) ||
                 (right_entry && !left_entry && keep_right && child.at(0)[0].eql?(right_entry[0])))
            entry = child.at(0)
            key_index = (entry[0].hash.abs >> left.instance_variable_get(:@significant_bits)) & 31
            if key_index == index && !left_child && !right_child &&
               ((left_entry && entry[0].eql?(left_entry[0])) ||
                (right_entry && entry[0].eql?(right_entry[0])))
              entries ||= left_entries.dup
              entries[index] = entry
              changed = true
            else
              children ||= left_children.dup
              children[index] = child
              changed = true
            end
          else
            entries ||= left_entries.dup
            children ||= left_children.dup
            entries[index] = nil
            children[index] = child
            changed = true
          end
        end
      end

      return left unless changed

      result_entries = entries || left_entries
      result_children = children || left_children
      new_size = 0
      result_entries.each { |entry| new_size += 1 if entry }
      result_children.each { |node| new_size += node.size if node }
      return nil if new_size == 0

      result = Trie.new(left.instance_variable_get(:@significant_bits), new_size,
                        result_entries, result_children)
      return left if keep_left && result.eql?(left)
      return right if keep_right && result.eql?(right)
      result
    end

    def combine_bucket(left_child, left_entry, right_child, right_entry,
                       keep_left, keep_right, &block)
      if left_entry && right_entry
        if left_entry[0].eql?(right_entry[0])
          value = yield(left_entry[1], right_entry[1])
          child = combine_nodes(left_child, right_child, keep_left, keep_right, &block)
          return child if value.nil?
          pair_bits = (left_child || right_child)
          bits = pair_bits ? pair_bits.instance_variable_get(:@significant_bits) : @significant_bits + 5
          pair = make_pair_node(nil, left_entry, value, bits)
          child ? combine_nodes(pair, child, true, true) { |pair_value, _| pair_value } : pair
        end

        left = make_pair_node(left_child, left_entry, left_entry[1], @significant_bits + 5)
        right = make_pair_node(right_child, right_entry, right_entry[1], @significant_bits + 5)
        combine_nodes(left, right, keep_left, keep_right, &block)
      elsif left_entry
        left = make_pair_node(left_child, left_entry, left_entry[1], @significant_bits + 5)
        right = right_child
        right ? combine_nodes(left, right, keep_left, keep_right, &block) : (keep_left ? left : nil)
      elsif right_entry
        right = make_pair_node(right_child, right_entry, right_entry[1], @significant_bits + 5)
        left = left_child
        left ? combine_nodes(left, right, keep_left, keep_right, &block) : (keep_right ? right : nil)
      else
        combine_nodes(left_child, right_child, keep_left, keep_right, &block)
      end
    end

    def make_pair_node(child, entry, value, bits, existing_child = nil)
      pair_bits = bits
      node = Trie.new(pair_bits)
      node = insert_pair_at(node, pair_bits, entry[0], value)
      child ? combine_nodes(node, child, true, true) { |left, _| left } : node
    end

    def insert_pair_at(node, bits, key, value)
      index = (key.hash.abs >> bits) & 31
      entries = node.instance_variable_get(:@entries)
      children = node.instance_variable_get(:@children)
      existing = entries[index]

      if existing.nil?
        new_entries = entries.dup
        new_entries[index] = [key, value].freeze
        Trie.new(bits, node.size + 1, new_entries, children)
      elsif existing[0].eql?(key)
        node
      else
        existing_child = children[index]
        new_child = if existing_child
          insert_pair_at(existing_child, bits + 5, key, value)
        else
          new_entries = []
          next_index = (key.hash.abs >> (bits + 5)) & 31
          new_entries[next_index] = [key, value].freeze
          Trie.new(bits + 5, 1, new_entries, [])
        end
        new_children = children.dup
        new_children[index] = new_child
        size = node.size + (new_child.size - (existing_child ? existing_child.size : 0))
        Trie.new(bits, size, entries, new_children)
      end
    end


    def index_for(key)
      (key.hash.abs >> @significant_bits) & 31
    end

    def copy_size(copy)
      copy ? copy.size : 0
    end
  end

  # @private
  EmptyTrie = Hamster::Trie.new(0)
end
