module Hamster
  # @private
  class Editor
    # Raised when a closed editor is asked to perform another edit.
    ClosedError = Class.new(StandardError)

    def initialize
      @owner_thread = Thread.current
      @closed = false
      @result = nil
    end

    # Return `true` if this editor has already produced its immutable result.
    #
    # @return [Boolean]
    def closed?
      @closed
    end
    alias :frozen? :closed?

    # Close the editor and return the immutable collection containing its edits.
    #
    # @return [Object]
    def finish
      unless Thread.current.equal?(@owner_thread)
        raise ThreadError, "editor can only be used by the thread which created it"
      end
      raise ClosedError, "editor has already been closed" if @closed
      @result = commit
      @closed = true
      discard_work
      @result
    end
    alias :close :finish
    alias :commit :finish

    def freeze
      @closed ? @result : finish
    end

    # Discard all edits made through this editor without changing the source.
    #
    # @return [nil]
    def abort
      raise ThreadError, "editor can only be used by the thread which created it" unless Thread.current.equal?(@owner_thread)
      return @result if @closed
      @closed = true
      discard_work
      nil
    end

    private

    def check!
      unless Thread.current.equal?(@owner_thread)
        raise ThreadError, "editor can only be used by the thread which created it"
      end
      raise ClosedError, "editor has already been closed" if @closed
    end

    def discard_work
    end
  end
end
