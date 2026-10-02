module Hamster
  # @private
  class Trie
    def self.[](pairs)
      result = self.new(0)
      pairs.each { |key, val| result.put!(key, val) }
      result
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

    # Returns the node to use after associating the given key and value,
    # mutating nodes in place when they are exclusively owned by the given
    # +token+. Nodes not owned by the token (including all nodes reachable
    # from any persistent collection) are copied before modification, so
    # existing persistent structures are never affected.
    #
    # Used by Hamster::TransientHash to batch many updates without
    # allocating new nodes for every single one.
    #
    # @private
    def put_mutating(key, value, token)
      index = index_for(key)
      entry = @entries[index]

      if !entry
        node = editable_copy(token)
        key = key.dup.freeze if key.is_a?(String) && !key.frozen?
        node.set_entry(index, [key, value].freeze)
        node.adjust_size(1)
      elsif entry[0].eql?(key)
        if entry[1].equal?(value)
          return self
        end
        node = editable_copy(token)
        key = key.dup.freeze if key.is_a?(String) && !key.frozen?
        node.set_entry(index, [key, value].freeze)
      else
        child = @children[index]
        if child
          old_child_size = child.size
          new_child = child.put_mutating(key, value, token)
          delta = new_child.size - old_child_size
          if new_child.equal?(child) && delta == 0
            return self
          end
          node = editable_copy(token)
          node.set_child(index, new_child)
          node.adjust_size(delta) if delta != 0
        else
          node = editable_copy(token)
          node.set_child(index, Trie.new(@significant_bits + 5).put!(key, value))
          node.adjust_size(1)
        end
      end
      node
    end

    # Returns the node to use after removing the given key, mutating nodes in
    # place when they are exclusively owned by the given token (see
    # put_mutating). Returns nil if the trie became empty.
    #
    # @private
    def delete_mutating(key, token)
      index = index_for(key)
      entry = @entries[index]
      if entry && entry[0].eql?(key)
        delete_at_mutating(token, index)
      else
        child = @children[index]
        return self unless child
        old_child_size = child.size
        new_child = child.delete_mutating(key, token)
        new_child_size = new_child ? new_child.size : 0
        delta = new_child_size - old_child_size
        return self if delta == 0
        node = editable_copy(token)
        node.set_child(index, new_child)
        node.adjust_size(delta)
        node
      end
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

    # In-place (ownership-aware) variant of delete_at. Returns the node to
    # use, or nil if the trie became empty.
    #
    # @private
    def delete_at_mutating(token, index = @entries.index { |e| e })
      yield(@entries[index]) if block_given?
      return nil if @size <= 1
      node = editable_copy(token)
      child = @children[index]
      if child
        node.set_child(index, child.delete_at_mutating(token) do |entry|
          node.set_entry(index, entry)
        end)
      else
        node.set_entry(index, nil)
      end
      node.adjust_size(-1)
      node
    end

    # Returns self if this node is exclusively owned by the given token,
    # otherwise returns a shallow copy of this node which is owned by the
    # token. Owned nodes are only reachable from the owning transient
    # editing session, so they can safely be mutated in place.
    #
    # @private
    def editable_copy(token)
      if @owner.equal?(token)
        self
      else
        copy = Trie.new(@significant_bits, @size, @entries.dup, @children.dup)
        copy.owner = token
        copy
      end
    end

    protected

    attr_writer :owner

    def set_entry(index, entry)
      @entries[index] = entry
    end

    def set_child(index, child)
      @children[index] = child
    end

    def adjust_size(delta)
      @size += delta
    end

    private

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
