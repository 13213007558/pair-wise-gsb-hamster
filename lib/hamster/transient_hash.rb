require "hamster/transient"

module Hamster
  # A `TransientHash` is a short-lived, mutable editing session over a
  # {Hamster::Hash}. It exists to make bulk updates efficient: instead of
  # building a new immutable hash for every single `put`, a batch of
  # changes is applied in place, and a single immutable `Hamster::Hash` is
  # produced at the end with {#persistent!}.
  #
  #     editor = hash.transient
  #     10_000.times { |i| editor.put(i, i * 2) }
  #     new_hash = editor.persistent!
  #
  # Or, using the block form, which persists automatically:
  #
  #     new_hash = hash.transient do |editor|
  #       editor.put(:a, 1)
  #       editor.delete(:b)
  #     end
  #
  # Safety rules:
  #
  # * A transient may only be used by the thread which created it.
  # * Once {#persistent!} has been called, the session is over: any further
  #   use raises {Transient::InactiveError}.
  # * The immutable hash the transient was created from (and any hash
  #   previously derived from it) is never modified, even if the editing
  #   session is abandoned midway, e.g. because of an exception.
  #
  class TransientHash
    include Transient

    # @private
    def initialize(klass, trie, default)
      @klass = klass
      @trie = trie
      @default = default
      initialize_transient!
    end

    # Return the number of key/value pairs currently in the transient.
    #
    # @return [Integer]
    def size
      ensure_transient_usable!
      @trie.size
    end
    alias :length :size

    # Return `true` if the transient contains no key/value pairs.
    #
    # @return [Boolean]
    def empty?
      size == 0
    end

    # Retrieve the value corresponding to the given key. If not found,
    # return `nil` (or the result of the default block, if the underlying
    # hash has one).
    #
    # @param key [Object] The key to look up
    # @return [Object]
    def get(key)
      ensure_transient_usable!
      entry = @trie.get(key)
      if entry
        entry[1]
      elsif @default
        @default.call(key)
      end
    end
    alias :[] :get

    # Return `true` if the given key is present in the transient.
    #
    # @param key [Object] The key to look up
    # @return [Boolean]
    def key?(key)
      ensure_transient_usable!
      @trie.key?(key)
    end
    alias :has_key? :key?
    alias :include? :key?
    alias :member? :key?

    # Associate the given key with the given value, replacing any existing
    # association. Returns `self` so calls can be chained.
    #
    # @param key [Object] The key to store
    # @param value [Object] The value to associate it with
    # @yield [value] The previously stored value, or `nil` if none
    # @yieldreturn [Object] The new value to store
    # @return [self]
    def put(key, value = yield(get(key)))
      ensure_transient_usable!
      ensure_editable_root!
      @trie.put_transient(key, value, @transient_token)
      self
    end

    # Associate the given key with the given value.
    #
    # @param key [Object] The key to store
    # @param value [Object] The value to associate it with
    # @return [Object] the stored value
    def store(key, value)
      put(key, value)
      value
    end
    alias :[]= :store

    # Delete the given key and its associated value.
    #
    # @param key [Object] The key to delete
    # @return [Object] the deleted value, or `nil` if the key was not present
    def delete(key)
      ensure_transient_usable!
      entry = @trie.get(key)
      if entry
        ensure_editable_root!
        @trie.delete_transient(key, @transient_token)
        entry[1]
      end
    end

    # Call the block once for each key/value pair in the transient.
    #
    # @yield [key, value]
    # @return [self]
    def each(&block)
      ensure_transient_usable!
      return to_enum unless block_given?
      @trie.each(&block)
      self
    end
    alias :each_pair :each

    # End this editing session and return an immutable `Hamster::Hash` with
    # the accumulated changes. The transient must not be used afterwards:
    # any further method call will raise {Transient::InactiveError}.
    #
    # @return [Hamster::Hash]
    def persistent!
      ensure_transient_usable!
      invalidate_transient!
      @klass.alloc(@trie, @default)
    end

    private

    # Make sure the root node is owned by this session, copying it first if
    # it is still shared with an immutable hash.
    def ensure_editable_root!
      @trie = @trie.transient_copy(@transient_token) unless @trie.transient_owned_by?(@transient_token)
    end
  end
end
