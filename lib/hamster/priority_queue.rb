require "hamster/immutable"
require "hamster/enumerable"
require "hamster/hash"
require "hamster/set"
require "hamster/sorted_set"

module Hamster

  # A `PriorityQueue` is a persistent (immutable), meldable priority queue.
  # Items are inserted together with a priority, and the item with the
  # smallest priority (as defined by `#<=>`, or by a comparator block given at
  # initialization time) can be inspected and removed efficiently. Items which
  # share the same priority are ordered stably: the one inserted first comes
  # out first.
  #
  # A `PriorityQueue` can be created like this:
  #
  #     Hamster::PriorityQueue.new
  #     Hamster::PriorityQueue.new { |a, b| a <=> b }   # 2-arg comparator
  #     Hamster::PriorityQueue.new { |priority| -priority } # 1-arg sort key
  #
  # Every {#insert} returns, alongside the new queue, a {Handle} which
  # identifies *that one insertion*. Two items with the same value are still
  # distinct members with distinct handles. The handle stays valid in every
  # queue version derived from the one where the insertion happened, and can
  # be used to {#decrease_priority} or {#delete} that specific entry.
  #
  # Like all Hamster collections, a `PriorityQueue` is immutable. Every
  # "modifying" operation returns a new queue and leaves the receiver
  # untouched, so an old version can always be kept and used to explore a
  # different branch (which makes the structure suitable for search
  # algorithms). Two queues can be combined with {#meld}; since both queues
  # keep their element identities, melding never duplicates shared entries
  # and never re-inserts elements from scratch.
  #
  # If two queues which share a common ancestor disagree about the priority
  # of the same entry, {#meld} raises a {ConflictError}, unless a resolver
  # block is given which explicitly picks the surviving priority.
  #
  class PriorityQueue
    include Immutable
    include Hamster::Enumerable

    # Raised when a {Handle} cannot be used with a given queue version.
    class InvalidHandleError < StandardError; end

    # Raised when a {Handle} was never part of the lineage of the queue
    # version it is used with.
    class UnknownHandleError < InvalidHandleError; end

    # Raised when a {Handle} refers to an entry which was part of the
    # queue's lineage, but has already been deleted (or popped) from this
    # version.
    class StaleHandleError < InvalidHandleError; end

    # Raised by {#meld} when both queues contain the same entry (same
    # insertion identity) with different priorities, and no resolver block
    # was given.
    class ConflictError < StandardError
      # @return [Handle] the handle identifying the conflicting entry
      attr_reader :handle
      # @return [Object] the priority of the entry in the receiver of {#meld}
      attr_reader :priority
      # @return [Object] the priority of the entry in the argument of {#meld}
      attr_reader :other_priority

      def initialize(handle, priority, other_priority)
        @handle = handle
        @priority = priority
        @other_priority = other_priority
        super("conflicting priorities for entry #{handle.inspect}: " \
              "#{priority.inspect} vs #{other_priority.inspect}; " \
              "pass a block to #meld to resolve the conflict")
      end
    end

    # A `Handle` is an opaque, stable token which identifies one particular
    # insertion into a {PriorityQueue}. It is obtained from {#insert} and
    # remains meaningful for every queue version derived from the insertion
    # (including queues produced by {#meld}), until the corresponding entry
    # is deleted or popped.
    #
    # Handles are value objects: two handles for the same insertion are
    # `#==`. They carry no reference to any queue, and their identity does
    # not depend on object addresses.
    class Handle
      # @private
      attr_reader :id

      def initialize(id)
        @id = id
        freeze
      end

      def ==(other)
        other.is_a?(Handle) && other.id == @id
      end
      alias_method :eql?, :==

      def hash
        @id.hash
      end

      def inspect
        "#<Hamster::PriorityQueue::Handle id=#{@id}>"
      end
      alias_method :to_s, :inspect
    end

    # @private
    class Entry
      include Immutable
      attr_reader :priority, :value

      def initialize(priority, value)
        @priority = priority
        @value = value
      end

      def ==(other)
        other.is_a?(Entry) && other.priority == @priority && other.value == @value
      end
      alias_method :eql?, :==
    end

    @next_id = 0
    @id_lock = Mutex.new

    class << self
      # @private
      # Monotonic, process-wide source of insertion identities. Ids -- not
      # object addresses -- decide both handle identity and the stable order
      # of equal priorities.
      def next_id
        @id_lock.synchronize { @next_id += 1 }
      end

      # @private
      # "Raw" allocation of a new `PriorityQueue`. Used internally to derive
      # new versions without re-running the public initializer.
      def alloc(comparator, entries, index, retired)
        result = allocate
        result.instance_variable_set(:@comparator, comparator)
        result.instance_variable_set(:@entries, entries)
        result.instance_variable_set(:@index, index)
        result.instance_variable_set(:@retired, retired)
        result
      end
    end

    # Return an empty `PriorityQueue`.
    #
    # @yield [a, b] Optional 2-argument comparator for priorities (like
    #   `Array#sort`), or a 1-argument block deriving a sort key from a
    #   priority (like `Array#sort_by`). Defaults to `#<=>`.
    def initialize(&block)
      @comparator = self.class.normalize_comparator(block)
      comparator = @comparator
      @entries = Hamster::Hash.new
      @index = Hamster::SortedSet.new do |pair_a, pair_b|
        result = comparator.call(pair_a[0], pair_b[0])
        result == 0 ? pair_a[1] <=> pair_b[1] : result
      end
      @retired = Hamster::Set.new
    end

    # Insert `value` with the given `priority`, and identify this insertion
    # with a fresh {Handle}.
    #
    # @param value [Object] the item to store
    # @param priority [Object] its priority; defaults to the value itself
    # @return [Array(PriorityQueue, Handle)] the new queue and a handle which
    #   identifies this insertion
    def insert(value, priority = value)
      id = self.class.next_id
      entries = @entries.put(id, Entry.new(priority, value))
      index = @index.add([priority, id])
      [self.class.alloc(@comparator, entries, index, @retired), Handle.new(id)]
    end
    alias_method :push, :insert

    # Return `true` if this queue contains no items.
    #
    # @return [Boolean]
    def empty?
      @entries.empty?
    end

    # Return the number of items in this queue.
    #
    # @return [Integer]
    def size
      @entries.size
    end
    alias_method :length, :size

    # Return the value with the smallest priority. Ties are broken by
    # insertion order (first in, first out).
    #
    # @return [Object, nil] `nil` if the queue is empty
    def min
      pair = @index.first
      pair && @entries.get(pair[1]).value
    end

    # Return the smallest priority in this queue.
    #
    # @return [Object, nil] `nil` if the queue is empty
    def min_priority
      pair = @index.first
      pair && pair[0]
    end

    # Return a new queue with the minimum item removed. Returns `self` if
    # the queue is empty.
    #
    # @return [PriorityQueue]
    def pop
      pair = @index.first
      return self if pair.nil?
      remove_entry(pair[1], pair[0])
    end

    # Return a new queue in which the entry identified by `handle` has
    # `new_priority`. The new priority must not be greater than the current
    # one (it moves the entry towards the front of the queue, or keeps its
    # urgency). To raise a priority instead, {#delete} the entry and
    # {#insert} it again -- it then becomes a new member with a new handle.
    #
    # @param handle [Handle] a handle obtained from {#insert}
    # @param new_priority [Object]
    # @return [PriorityQueue]
    # @raise [ArgumentError] if `new_priority` is greater than the current one
    # @raise [UnknownHandleError] if `handle` never belonged to this lineage
    # @raise [StaleHandleError] if the entry was already removed
    def decrease_priority(handle, new_priority)
      entry = fetch_entry(handle)
      return self if @comparator.call(new_priority, entry.priority) == 0
      if @comparator.call(new_priority, entry.priority) > 0
        raise ArgumentError,
              "new priority #{new_priority.inspect} is greater than current " \
              "priority #{entry.priority.inspect}"
      end
      id = handle.id
      entries = @entries.put(id, Entry.new(new_priority, entry.value))
      index = @index.delete([entry.priority, id]).add([new_priority, id])
      self.class.alloc(@comparator, entries, index, @retired)
    end

    # Return a new queue with the entry identified by `handle` removed.
    #
    # @param handle [Handle] a handle obtained from {#insert}
    # @return [PriorityQueue]
    # @raise [UnknownHandleError] if `handle` never belonged to this lineage
    # @raise [StaleHandleError] if the entry was already removed
    def delete(handle)
      entry = fetch_entry(handle)
      remove_entry(handle.id, entry.priority)
    end

    # Return `true` if `handle` identifies a live entry in this queue
    # version.
    #
    # @param handle [Handle]
    # @return [Boolean]
    def handle?(handle)
      handle.is_a?(Handle) && @entries.key?(handle.id)
    end

    # Return the priority of the entry identified by `handle`.
    #
    # @param handle [Handle]
    # @return [Object]
    # @raise [UnknownHandleError] if `handle` never belonged to this lineage
    # @raise [StaleHandleError] if the entry was already removed
    def priority_of(handle)
      fetch_entry(handle).priority
    end

    # Return a new queue which contains all entries of this queue and
    # `other`. Both queues keep their element identities: an entry which is
    # present (with the same priority) in both queues appears only once in
    # the result, and handles from either queue stay valid in the result.
    #
    # Entries are merged structurally -- they are never popped out and
    # re-inserted -- so the stable order of equal priorities is preserved,
    # and the result does not depend on object addresses.
    #
    # If the same entry (same insertion identity) has *different* priorities
    # in the two queues -- which can happen when both queues descend from a
    # common ancestor and the entry was changed on both branches -- this is
    # a conflict which the caller must resolve explicitly:
    #
    # @overload meld(other)
    #   @raise [ConflictError] if an entry has conflicting priorities
    # @overload meld(other) { |handle, priority, other_priority| ... }
    #   @yield [handle, priority, other_priority] called once for every
    #     conflicting entry; must return the priority to keep
    #
    # An entry which was deleted on one branch but is still present on the
    # other is kept (presence wins over deletion). The receiver's comparator
    # is used for the merged queue.
    #
    # @param other [PriorityQueue]
    # @return [PriorityQueue]
    def meld(other)
      unless other.is_a?(PriorityQueue)
        raise TypeError, "can only meld another Hamster::PriorityQueue"
      end
      conflicts = []
      entries = @entries.merge(other.entries) do |id, entry, other_entry|
        if @comparator.call(entry.priority, other_entry.priority) == 0
          entry
        elsif block_given?
          resolved = yield(Handle.new(id), entry.priority, other_entry.priority)
          conflicts << [id, entry.priority, other_entry.priority, resolved]
          Entry.new(resolved, entry.value)
        else
          raise ConflictError.new(Handle.new(id), entry.priority, other_entry.priority)
        end
      end
      index = @index.union(other.index)
      conflicts.each do |id, priority, other_priority, resolved|
        index = index.delete([priority, id]).delete([other_priority, id]).add([resolved, id])
      end
      retired = Hamster::Set.new
      @retired.each { |id| retired = retired.add(id) unless entries.key?(id) }
      other.retired.each { |id| retired = retired.add(id) unless entries.key?(id) }
      self.class.alloc(@comparator, entries, index, retired)
    end
    alias_method :merge, :meld

    # Yield each value in pop order (smallest priority first; ties in
    # insertion order).
    #
    # @yield [value]
    # @return [self, Enumerator]
    def each
      return enum_for(:each) unless block_given?
      @index.each { |pair| yield @entries.get(pair[1]).value }
      self
    end

    # Return `true` if `other` is a `PriorityQueue` with the same entries
    # (same insertion identities, priorities, and values).
    def eql?(other)
      other.is_a?(PriorityQueue) && @entries.eql?(other.entries)
    end
    alias_method :==, :eql?

    def inspect
      "Hamster::PriorityQueue[#{map(&:inspect).join(', ')}]"
    end
    alias_method :to_s, :inspect

    # @private
    attr_reader :entries, :index, :retired

    # @private
    def self.normalize_comparator(block)
      if block.nil?
        lambda { |a, b| a <=> b }
      elsif block.arity == 1 || block.arity == -1 || block.arity == -2
        lambda { |a, b| block.call(a) <=> block.call(b) }
      elsif block.arity == 2 || block.arity == -3
        block
      else
        raise ArgumentError, "comparator block must accept 1 or 2 arguments"
      end
    end

    private

    def fetch_entry(handle)
      unless handle.is_a?(Handle)
        raise TypeError, "expected a Hamster::PriorityQueue::Handle, got #{handle.inspect}"
      end
      entry = @entries.get(handle.id)
      return entry if entry
      if @retired.include?(handle.id)
        raise StaleHandleError,
              "#{handle.inspect} refers to an entry which was already removed"
      end
      raise UnknownHandleError,
            "#{handle.inspect} does not belong to this queue version"
    end

    def remove_entry(id, priority)
      entries = @entries.delete(id)
      index = @index.delete([priority, id])
      self.class.alloc(@comparator, entries, index, @retired.add(id))
    end
  end
end
