module Hamster
  # Shared machinery for short-lived, single-threaded batch editing sessions
  # ("transients") over otherwise immutable collections.
  #
  # A transient session owns any node it creates or copies, marking it with an
  # ownership {Token}. Nodes which are shared with an existing immutable
  # collection are never mutated in place: they are copied on first write
  # (copy-on-write), so the immutable value they belong to can never be
  # corrupted, even if the editing session exits abnormally.
  #
  # When the session is finished (see TransientHash#persistent! and
  # TransientVector#persistent!), the token is invalidated. Every mutation
  # re-checks the token, so any write attempted afterwards -- including writes
  # through stale internal node handles which still reference the token --
  # fails instead of silently corrupting the now-immutable result.
  #
  # @private
  module Transient
    # Raised when a transient is used after it has been persisted.
    #
    # @private
    class InactiveError < FrozenError; end

    # Ownership token for a single transient editing session. Nodes tagged
    # with a token may be mutated in place for as long as the token is alive.
    # Once the session is persisted the token is invalidated, permanently
    # revoking write access to every node it marked.
    #
    # @private
    class Token
      def initialize
        @alive = true
      end

      def alive?
        @alive
      end

      def invalidate!
        @alive = false
        nil
      end
    end

    # Permanently end this editing session. All further use fails.
    #
    # @private
    def invalidate_transient!
      @transient_token.invalidate!
    end

    private

    def initialize_transient!
      @transient_owner = Thread.current
      @transient_token = Token.new
    end

    # Verify that the session is still usable: it must be accessed from the
    # thread which created it, and it must not have been persisted yet.
    def ensure_transient_usable!
      unless Thread.current.equal?(@transient_owner)
        raise ThreadError, "transient may only be used by the thread which created it"
      end
      unless @transient_token.alive?
        raise Transient::InactiveError, "can't use transient after it has been persisted"
      end
      nil
    end
  end
end
