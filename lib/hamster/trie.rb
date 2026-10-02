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

    # Combines the values stored under matching keys. Unchanged sub-tries are
    # retained. Supported operations are :+ (add), :max, :min, and :- (with
    # negative results truncated to zero).
    #
    # @return [Trie]
    # @private
    def combine(other, operation)
      return self if equal?(other) && (operation == :max || operation == :min)
      return EmptyTrie if equal?(other) && operation == :-
      return self if other.empty? || (empty? && (operation == :min || operation == :-))
      return other if empty?
      combine_tries(self, other, operation)
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

    def combine_tries(left, right, operation)
      entries = left.instance_variable_get(:@entries)
      children = left.instance_variable_get(:@children)
      changed = false

      32.times do |index|
        left_entry = entries[index]
        right_entry = right.instance_variable_get(:@entries)[index]
        left_child = children[index]
        right_child = right.instance_variable_get(:@children)[index]

        if matching_slot_entries?(left_entry, right_entry)
          value = combine_values(left_entry[1], right_entry[1], operation)
          child = nonempty_trie(combine_slot_children(left_child, right_child, operation))
          entry_changed = value == 0 || value != left_entry[1]
          child_changed = child ? !child.equal?(left_child) : !!left_child

          if entry_changed
            entries = entries.dup
            entries[index] = value > 0 ? [left_entry[0], value].freeze : nil
          end
          if child_changed
            children = children.dup
            children[index] = child
          end
          changed ||= entry_changed || child_changed
        elsif left_entry || left_child
          if right_entry || right_child
            entry, child = combine_collided_slot(left_entry, left_child,
                                                right_entry, right_child, operation)
            unless entry.equal?(left_entry)
              entries = entries.dup
              entries[index] = entry
              changed = true
            end
            unless child.equal?(left_child)
              children = children.dup
              children[index] = child
              changed = true
            end
          else
            unless keeps_side_without_other?(operation)
              if left_entry
                entries = entries.dup
                entries[index] = nil
              end
              if left_child
                children = children.dup
                children[index] = nil
              end
              changed = true
            end
          end
        elsif right_entry || right_child
          if keeps_side_without_other?(operation) && operation != :-
            if right_entry
              entries = entries.dup
              entries[index] = right_entry
            end
            if right_child
              children = children.dup
              children[index] = right_child
            end
            changed = true
          end
        end
      end

      return left unless changed
      new_size = entries.compact.size
      children.each { |child| new_size += child.size if child }
      Trie.new(left.instance_variable_get(:@significant_bits), new_size, entries, children)
    end

    def matching_slot_entries?(left_entry, right_entry)
      left_entry && right_entry &&
        left_entry[0].eql?(right_entry[0])
    end

    def combine_slot_children(left_child, right_child, operation)
      if left_child && right_child
        left_child.combine(right_child, operation)
      elsif left_child && keeps_side_without_other?(operation)
        left_child
      elsif right_child && keeps_side_without_other?(operation) && operation != :-
        right_child
      end
    end

    def combine_collided_slot(left_entry, left_child, right_entry, right_child, operation)
      bits = @significant_bits + 5
      if left_entry
        entry = operation == :min ? nil : left_entry
        right_slot = slot_with_entry(right_entry, right_child, bits)
        child = combine_optional_tries(left_child, right_slot, operation)
      else
        entry = (operation == :+ || operation == :max) ? right_entry : nil
        child = combine_optional_tries(left_child, right_child, operation)
        child = combine_optional_tries(child, pair_trie(bits, right_entry), operation) if right_entry
      end
      [entry, child]
    end

    def combine_optional_tries(left, right, operation)
      return right if left.nil? && (operation == :+ || operation == :max)
      return left if right.nil? && operation != :min
      return nil if left.nil? || right.nil?
      nonempty_trie(left.combine(right, operation))
    end

    def slot_with_entry(entry, child, bits)
      return child unless entry
      combine_optional_tries(pair_trie(bits, entry), child, :+)
    end

    def nonempty_trie(trie)
      trie unless trie.nil? || trie.empty?
    end

    def pair_trie(bits, entry)
      entries = []
      entries[(entry[0].hash.abs >> bits) & 31] = entry
      Trie.new(bits, 1, entries, [])
    end

    def combine_values(left, right, operation)
      value = case operation
              when :+ then left + right
              when :max then [left, right].max
              when :min then [left, right].min
              when :- then left - right
              else raise ArgumentError, "unknown trie combination: #{operation.inspect}"
              end
      value > 0 ? value : 0
    end

    def keeps_side_without_other?(operation)
      operation == :+ || operation == :max || operation == :-
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
