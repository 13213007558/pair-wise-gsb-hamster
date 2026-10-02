require "hamster/immutable"
require "hamster/hash"
require "hamster/set"
require "hamster/list"

module Hamster

  # A `PriorityQueue` is a persistent (immutable), meldable priority queue.
  # Elements are inserted with a priority and are removed lowest-priority-first.
  # Elements which share the same priority are removed in the order they were
  # inserted (the queue is *stable*). Ordering is fully determined by priority
  # and insertion order; it never depends on object identity or memory
  # addresses.
  #
  # Like all Hamster collections, every "modifying" operation returns a new
  # queue and leaves the receiver untouched, so any old version can keep being
  # used (or branched from) at any time. This makes the queue suitable for
  # search algorithms which explore several alternatives from a shared state.
  #
  # Each call to {#insert} returns a fresh {Handle} which identifies *that
  # insertion*. Inserting the same value twice yields two distinct members
  # with two distinct handles. A handle stays valid across all descendants of
  # the queue it came from, and can be used to {#decrease_priority} or
  # {#delete} the element it refers to.
  #
  # Two queues can be combined with {#meld}; the internal heaps are linked
  # directly, so elements are never drained and re-inserted. When both queues
  # descend from a common ancestor and the same handle was changed to two
  # different priorities, the conflict is reported and must be resolved
  # explicitly (with `:min`, `:max`, or a block); the element is never
  # silently duplicated.
  #
  #     queue = Hamster::PriorityQueue.new
  #     queue, handle = queue.insert(5, "task")
  #     queue = queue.decrease_priority(handle, 1)
  #     priority, value, queue = queue.pop   # => [1, "task", ...]
  #
  class PriorityQueue
    include Immutable

    # Base class for errors raised when a {Handle} cannot be used with a
    # queue.
    class HandleError < StandardError; end

    # Raised when a handle was never a member of this version of the queue
    # (for example a handle belonging to an unrelated queue, or to a sibling
    # branch which inserted it after the two branches diverged).
    class UnknownHandleError < HandleError; end

    # Raised when a handle *was* a member of this queue's lineage but its
    # element has since been removed (by {#delete} or {#pop}).
    class DeletedHandleError < HandleError; end

    # Raised by {#meld} when both queues hold the same handle at conflicting
    # priorities and no conflict resolution strategy was provided.
    class ConflictError < StandardError
      # @return [Handle] the handle whose priority differs between the queues
      attr_reader :handle
      # @return the priority in the receiver of {#meld}
      attr_reader :left_priority
      # @return the priority in the argument of {#meld}
      attr_reader :right_priority

      def initialize(handle, left_priority, right_priority)
        @handle = handle
        @left_priority = left_priority
        @right_priority = right_priority
        super("meld conflict: #{handle.inspect} has been changed to " \
              "conflicting priorities (#{left_priority.inspect} vs " \
              "#{right_priority.inspect}); pass :min, :max, or a block to " \
              "PriorityQueue#meld to resolve the conflict")
      end
    end

    # A `Handle` identifies one particular insertion into a
    # {PriorityQueue}. Two insertions of an equal value are still two
    # distinct members of the queue, identified by two distinct handles.
    #
    # Handles are ordered and compared by a logical sequence number, never
    # by object address, so queue behaviour is deterministic.
    class Handle
      @next_id = 0
      @next_id_mutex = Mutex.new

      # @private
      def self.next_id
        @next_id_mutex.synchronize { @next_id += 1 }
      end

      # Logical sequence number of this handle. Monotonically increasing in
      # allocation order, globally unique within the process.
      attr_reader :id

      def initialize
        @id = Handle.next_id
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
    Entry = Struct.new(:priority, :value, :version)

    # A node of the internal pairing heap. Nodes are immutable; the heap is
    # fully persistent.
    #
    # @private
    class Node
      attr_reader :priority, :handle, :value, :version, :children

      def initialize(priority, handle, value, version, children)
        @priority = priority
        @handle = handle
        @value = value
        @version = version
        @children = children
        freeze
      end
    end

    class << self
      # Return an empty `PriorityQueue`.
      #
      # @return [PriorityQueue]
      def empty
        @empty ||= alloc(nil, Hamster::Hash.new, Hamster::Set.new)
      end

      # "Raw" allocation of a new `PriorityQueue`. Used internally to create
      # a new instance quickly after computing new internal state.
      #
      # @private
      def alloc(heap, entries, tombstones)
        result = allocate
        result.instance_variable_set(:@heap, heap)
        result.instance_variable_set(:@entries, entries)
        result.instance_variable_set(:@tombstones, tombstones)
        result.immutable!
        result
      end
    end

    # Return an empty `PriorityQueue`.
    def initialize
      @heap = nil
      @entries = Hamster::Hash.new
      @tombstones = Hamster::Set.new
    end

    # @return [Integer] the number of elements in the queue
    def size
      @entries.size
    end
    alias_method :length, :size

    # @return [Boolean] true if the queue contains no elements
    def empty?
      @entries.empty?
    end

    # Insert `value` with the given `priority`. Lower priorities come out of
    # the queue first; ties are broken by insertion order.
    #
    # @param priority the priority of the new element; must be comparable
    #   (via `#<=>`) with the priorities of all other elements
    # @param value the payload to associate with this insertion
    # @return [Array(PriorityQueue, Handle)] the new queue and a handle
    #   identifying this exact insertion
    def insert(priority, value = nil)
      handle = Handle.new
      entry = Entry.new(priority, value, 0)
      node = Node.new(priority, handle, value, 0, EmptyList)
      queue = self.class.alloc(
        merge_nodes(node, @heap),
        @entries.put(handle, entry),
        @tombstones
      )
      [queue, handle]
    end

    # @return [Array(Object, Object), nil] the lowest priority and its
    #   associated value, or nil if the queue is empty
    def peek
      heap = live_heap
      heap && [heap.priority, heap.value]
    end

    # Remove the minimal element.
    #
    # @return [Array(Object, Object, PriorityQueue), nil] the priority, the
    #   value, and the new queue; or nil if the queue is empty
    def pop
      heap = live_heap
      return nil if heap.nil?
      entry = @entries.get(heap.handle)
      new_queue = self.class.alloc(
        merge_pairs(heap.children),
        @entries.delete(heap.handle),
        @tombstones.add(heap.handle)
      )
      [heap.priority, entry.value, new_queue]
    end

    # Lower the priority of the element identified by `handle`. The element
    # keeps its original insertion-order position among elements which share
    # its new priority.
    #
    # @param handle [Handle] a handle returned by {#insert}
    # @param new_priority must be less than or equal to the current priority
    # @return [PriorityQueue]
    # @raise [UnknownHandleError] if the handle is not a member of this queue
    # @raise [DeletedHandleError] if the handle's element was removed
    # @raise [ArgumentError] if `new_priority` is greater than the current
    #   priority, or not comparable with it
    def decrease_priority(handle, new_priority)
      entry = @entries.get(handle)
      raise_handle_error!(handle) if entry.nil?
      cmp = compare_priorities(new_priority, entry.priority)
      if cmp > 0
        raise ArgumentError, "new priority #{new_priority.inspect} is greater " \
                             "than current priority #{entry.priority.inspect}"
      end
      return self if cmp == 0
      new_entry = Entry.new(new_priority, entry.value, entry.version + 1)
      node = Node.new(new_priority, handle, entry.value, entry.version + 1, EmptyList)
      self.class.alloc(
        merge_nodes(node, @heap),
        @entries.put(handle, new_entry),
        @tombstones
      )
    end

    # Remove the element identified by `handle`.
    #
    # @param handle [Handle] a handle returned by {#insert}
    # @return [PriorityQueue]
    # @raise [UnknownHandleError] if the handle is not a member of this queue
    # @raise [DeletedHandleError] if the handle's element was already removed
    def delete(handle)
      raise_handle_error!(handle) if @entries.get(handle).nil?
      self.class.alloc(
        @heap,
        @entries.delete(handle),
        @tombstones.add(handle)
      )
    end

    # @param handle [Handle]
    # @return [Boolean] true if `handle` identifies a live element of this
    #   queue
    def handle?(handle)
      @entries.key?(handle)
    end
    alias_method :member?, :handle?
    alias_method :include?, :handle?

    # @param handle [Handle] a handle returned by {#insert}
    # @return the current priority of the element identified by `handle`
    # @raise [UnknownHandleError] if the handle is not a member of this queue
    # @raise [DeletedHandleError] if the handle's element was removed
    def priority_of(handle)
      entry = @entries.get(handle)
      raise_handle_error!(handle) if entry.nil?
      entry.priority
    end

    # Combine this queue with `other`, returning a new queue containing the
    # elements of both. Neither receiver is modified, and the internal heaps
    # are linked directly -- elements are never drained and re-inserted.
    #
    # Handles are globally unique, so an element which both queues inherited
    # from a common ancestor appears only once in the result. If one branch
    # changed an element's priority and the other left it alone, the changed
    # priority wins. If an element was deleted (or popped) in either branch,
    # it stays deleted.
    #
    # If both branches changed the *same* element to *different* priorities,
    # the conflict must be resolved explicitly:
    #
    # - `meld(other, :min)` keeps the lower priority,
    # - `meld(other, :max)` keeps the higher priority,
    # - `meld(other) { |handle, mine, theirs| ... }` calls the block with
    #   the handle and both priorities, and keeps the block's return value.
    #
    # Without a strategy, a {ConflictError} is raised. A conflicting element
    # is never silently duplicated into two members.
    #
    # @param other [PriorityQueue]
    # @param strategy [:min, :max, #call] conflict resolution strategy
    # @yield [handle, my_priority, their_priority] optional conflict resolver
    # @return [PriorityQueue]
    # @raise [ConflictError] on unresolved priority conflicts
    def meld(other, strategy = nil, &block)
      unless other.is_a?(PriorityQueue)
        raise ArgumentError, "can only meld with another Hamster::PriorityQueue"
      end
      resolver = block || resolver_for(strategy)

      if @entries.size <= other.entries.size
        small, big = self, other
      else
        small, big = other, self
      end

      merged = big.entries
      resolved_nodes = []

      small.entries.each do |handle, s_entry|
        next if big.tombstones.include?(handle)
        b_entry = big.entries.get(handle)
        if b_entry.nil?
          merged = merged.put(handle, s_entry)
        elsif s_entry.version > b_entry.version
          merged = merged.put(handle, s_entry)
        elsif s_entry.version < b_entry.version
          # big holds the later version; keep it
        elsif s_entry.priority == b_entry.priority
          # identical state; keep it
        else
          my_entry, their_entry = small.equal?(self) ? [s_entry, b_entry] : [b_entry, s_entry]
          unless resolver
            raise ConflictError.new(handle, my_entry.priority, their_entry.priority)
          end
          new_priority = resolver.call(handle, my_entry.priority, their_entry.priority)
          new_entry = Entry.new(new_priority, b_entry.value, s_entry.version + 1)
          merged = merged.put(handle, new_entry)
          resolved_nodes << Node.new(new_priority, handle, b_entry.value,
                                     s_entry.version + 1, EmptyList)
        end
      end

      # Deletion (including popping) is sticky: an element removed on either
      # branch stays removed in the result.
      small.tombstones.each do |handle|
        merged = merged.delete(handle) if merged.key?(handle)
      end

      heap = merge_nodes(@heap, other.heap)
      resolved_nodes.each { |node| heap = merge_nodes(node, heap) }

      self.class.alloc(heap, merged, @tombstones.union(other.tombstones))
    end

    def inspect
      "#<Hamster::PriorityQueue size=#{size}>"
    end
    alias_method :to_s, :inspect

    protected

    attr_reader :heap, :entries, :tombstones

    private

    # Raise the error which matches the state of `handle` in this queue:
    # {DeletedHandleError} if it was removed, {UnknownHandleError} if it was
    # never a member of this version.
    def raise_handle_error!(handle)
      if @tombstones.include?(handle)
        raise DeletedHandleError, "#{handle.inspect} refers to an element " \
                                  "which was removed from this queue"
      else
        raise UnknownHandleError, "#{handle.inspect} is not a member of this queue"
      end
    end

    def resolver_for(strategy)
      case strategy
      when nil
        nil
      when :min
        ->(handle, mine, theirs) { compare_priorities(mine, theirs) <= 0 ? mine : theirs }
      when :max
        ->(handle, mine, theirs) { compare_priorities(mine, theirs) <= 0 ? theirs : mine }
      when Proc
        strategy
      else
        raise ArgumentError, "unknown meld strategy #{strategy.inspect}; " \
                             "use :min, :max, a callable, or a block"
      end
    end

    def compare_priorities(prio_a, prio_b)
      cmp = prio_a <=> prio_b
      if cmp.nil?
        raise ArgumentError, "cannot compare priorities #{prio_a.inspect} " \
                             "and #{prio_b.inspect}"
      end
      cmp
    end

    # Total order on heap nodes: by priority, then by the handle's logical
    # sequence number (insertion order). Never by object address.
    def compare_nodes(node_a, node_b)
      cmp = compare_priorities(node_a.priority, node_b.priority)
      cmp = node_a.handle.id <=> node_b.handle.id if cmp == 0
      cmp
    end

    def merge_nodes(node_a, node_b)
      return node_b if node_a.nil?
      return node_a if node_b.nil?
      if compare_nodes(node_a, node_b) <= 0
        Node.new(node_a.priority, node_a.handle, node_a.value, node_a.version,
                 node_a.children.cons(node_b))
      else
        Node.new(node_b.priority, node_b.handle, node_b.value, node_b.version,
                 node_b.children.cons(node_a))
      end
    end

    # Combine the children of a removed root into a single heap: pair up
    # adjacent heaps left to right, then fold the results right to left.
    def merge_pairs(children)
      heaps = children.to_a
      return nil if heaps.empty?
      pairs = []
      index = 0
      while index + 1 < heaps.size
        pairs << merge_nodes(heaps[index], heaps[index + 1])
        index += 2
      end
      pairs << heaps[index] if index < heaps.size
      result = pairs.pop
      while (pair = pairs.pop)
        result = merge_nodes(pair, result)
      end
      result
    end

    # The heap may contain stale nodes (superseded by {#decrease_priority},
    # {#delete}, {#pop}, or {#meld}). Discard stale roots until the root is a
    # live entry, so {#peek} and {#pop} see the true minimum.
    def live_heap
      heap = @heap
      while heap
        entry = @entries.get(heap.handle)
        break if entry && entry.version == heap.version
        heap = merge_pairs(heap.children)
      end
      heap
    end
  end
end
