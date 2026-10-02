require "spec_helper"

describe Hamster::PriorityQueue do
  def drain(queue)
    items = []
    until queue.empty?
      priority, value, queue = queue.pop
      items << [priority, value]
    end
    items
  end

  describe "#meld" do
    it "combines the elements of both queues" do
      left = PQ.new
      left, = left.insert(3, "c")
      left, = left.insert(1, "a")
      right = PQ.new
      right, = right.insert(2, "b")
      right, = right.insert(4, "d")
      merged = left.meld(right)
      expect(merged.size).to eq(4)
      expect(drain(merged)).to eq([[1, "a"], [2, "b"], [3, "c"], [4, "d"]])
    end

    it "leaves both queues unchanged" do
      left, = PQ.new.insert(1, "a")
      right, = PQ.new.insert(2, "b")
      left.meld(right)
      expect(left.size).to eq(1)
      expect(right.size).to eq(1)
    end

    it "melds with an empty queue" do
      queue, = PQ.new.insert(1, "a")
      expect(drain(queue.meld(PQ.new))).to eq([[1, "a"]])
      expect(drain(PQ.new.meld(queue))).to eq([[1, "a"]])
    end

    it "keeps a stable order for equal priorities across the meld" do
      left = PQ.new
      left, = left.insert(0, "first")
      right = PQ.new
      right, = right.insert(0, "second")
      left, = left.insert(0, "third")
      merged = left.meld(right)
      expect(drain(merged).map(&:last)).to eq(["first", "second", "third"])
    end

    it "raises ArgumentError for a non-priority-queue argument" do
      expect { PQ.new.meld([1, 2, 3]) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for an unknown conflict strategy" do
      expect { PQ.new.meld(PQ.new, :bogus) }.to raise_error(ArgumentError)
    end

    it "links the two heaps structurally instead of draining and re-inserting" do
      left = PQ.new
      left, = left.insert(1, "a")
      left, = left.insert(2, "b")
      right = PQ.new
      right, = right.insert(0, "c")
      merged = left.meld(right)
      left_root = left.instance_variable_get(:@heap)
      right_root = right.instance_variable_get(:@heap)
      merged_root = merged.instance_variable_get(:@heap)
      # the merged root is the smaller of the two original roots, with the
      # other original root linked directly underneath it
      expect(merged_root.handle).to eq(right_root.handle)
      expect(merged_root.children.to_a).to include(left_root)
    end

    describe "with branches of a common ancestor" do
      let!(:base) do
        queue = PQ.new
        queue, @handle = queue.insert(5, "shared")
        queue, = queue.insert(7, "other")
        queue
      end

      it "contains the shared element only once" do
        merged = base.meld(base)
        expect(merged.size).to eq(2)
        expect(drain(merged)).to eq([[5, "shared"], [7, "other"]])
      end

      it "takes the changed priority when only one branch changed it" do
        changed = base.decrease_priority(@handle, 2)
        expect(base.meld(changed).priority_of(@handle)).to eq(2)
        expect(changed.meld(base).priority_of(@handle)).to eq(2)
      end

      it "treats a descendant as absorbing its ancestor" do
        descendant = base.decrease_priority(@handle, 2)
        merged = base.meld(descendant)
        expect(merged.size).to eq(2)
        expect(merged.priority_of(@handle)).to eq(2)
      end

      it "raises ConflictError when both branches changed the same element" do
        left = base.decrease_priority(@handle, 2)
        right = base.decrease_priority(@handle, 3)
        expect { left.meld(right) }.to raise_error(PQ::ConflictError)
        expect { right.meld(left) }.to raise_error(PQ::ConflictError)
      end

      it "exposes the handle and both priorities on ConflictError" do
        left = base.decrease_priority(@handle, 2)
        right = base.decrease_priority(@handle, 3)
        begin
          left.meld(right)
          raise "expected ConflictError"
        rescue PQ::ConflictError => error
          expect(error.handle).to eq(@handle)
          expect(error.left_priority).to eq(2)
          expect(error.right_priority).to eq(3)
        end
      end

      it "resolves conflicts with :min" do
        left = base.decrease_priority(@handle, 2)
        right = base.decrease_priority(@handle, 3)
        merged = left.meld(right, :min)
        expect(merged.priority_of(@handle)).to eq(2)
        expect(merged.size).to eq(2)
      end

      it "resolves conflicts with :max" do
        left = base.decrease_priority(@handle, 2)
        right = base.decrease_priority(@handle, 3)
        merged = left.meld(right, :max)
        expect(merged.priority_of(@handle)).to eq(3)
        expect(merged.size).to eq(2)
      end

      it "resolves conflicts with a block" do
        left = base.decrease_priority(@handle, 2)
        right = base.decrease_priority(@handle, 3)
        merged = left.meld(right) { |handle, mine, theirs| 0 }
        expect(merged.priority_of(@handle)).to eq(0)
        expect(merged.peek).to eq([0, "shared"])
      end

      it "never duplicates a conflicting element into two members" do
        left = base.decrease_priority(@handle, 2)
        right = base.decrease_priority(@handle, 3)
        merged = left.meld(right, :min)
        values = drain(merged).map(&:last)
        expect(values.count("shared")).to eq(1)
        expect(values.size).to eq(2)
      end

      it "keeps an element deleted in either branch deleted" do
        deleted = base.delete(@handle)
        expect(deleted.meld(base).handle?(@handle)).to be(false)
        expect(base.meld(deleted).handle?(@handle)).to be(false)
        expect(deleted.meld(base).size).to eq(1)
      end

      it "keeps an element popped in either branch popped" do
        _, _, popped = base.pop
        merged = popped.meld(base)
        expect(merged.handle?(@handle)).to be(false)
        expect(merged.size).to eq(1)
      end

      it "combines insertions made on different branches" do
        left, = base.insert(1, "left-only")
        right, = base.insert(0, "right-only")
        merged = left.meld(right)
        expect(merged.size).to eq(4)
        expect(drain(merged).map(&:last)).to eq(
          ["right-only", "left-only", "shared", "other"]
        )
      end
    end
  end
end

