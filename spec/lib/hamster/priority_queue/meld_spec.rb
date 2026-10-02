require "spec_helper"
require "hamster/priority_queue"

describe Hamster::PriorityQueue do
  describe "#meld" do
    it "combines two disjoint queues" do
      left = PQ.new
      left, = left.insert("a", 1)
      left, = left.insert("c", 3)
      right = PQ.new
      right, = right.insert("b", 2)
      right, = right.insert("d", 4)
      expect(left.meld(right).to_a).to eq(%w[a b c d])
      expect(left.meld(right).size).to eq(4)
    end

    it "is aliased as #merge" do
      left, = PQ.new.insert("a", 1)
      right, = PQ.new.insert("b", 2)
      expect(left.merge(right).to_a).to eq(%w[a b])
    end

    it "leaves both receivers unchanged" do
      left, = PQ.new.insert("a", 1)
      right, = PQ.new.insert("b", 2)
      left.meld(right)
      expect(left.size).to eq(1)
      expect(right.size).to eq(1)
    end

    it "raises TypeError for a non-queue argument" do
      queue, = PQ.new.insert("a", 1)
      expect { queue.meld([["b", 2]]) }.to raise_error(TypeError)
    end

    it "melding a queue with itself changes nothing" do
      queue = PQ.new
      queue, = queue.insert("a", 1)
      queue, = queue.insert("b", 2)
      expect(queue.meld(queue)).to eql(queue)
      expect(queue.meld(queue).size).to eq(2)
    end

    context "for queues which share a common ancestor" do
      let!(:base) do
        queue = PQ.new
        queue, @shared = queue.insert("shared", 5)
        queue
      end

      def shared; @shared; end

      it "does not duplicate entries which are identical on both branches" do
        left = base
        left, = left.insert("left", 1)
        right = base
        right, = right.insert("right", 2)
        merged = left.meld(right)
        expect(merged.size).to eq(3)
        expect(merged.to_a).to eq(%w[left right shared])
      end

      it "keeps handles from both branches valid in the merged queue" do
        left, left_handle = base.insert("left", 1)
        right, right_handle = base.insert("right", 2)
        merged = left.meld(right)
        expect(merged.handle?(shared)).to be(true)
        expect(merged.handle?(left_handle)).to be(true)
        expect(merged.handle?(right_handle)).to be(true)
        expect(merged.delete(left_handle).to_a).to eq(%w[right shared])
      end

      it "treats a priority changed on only one branch as a conflict too" do
        left = base.decrease_priority(shared, 1)
        right = base
        right, = right.insert("right", 3)
        expect { left.meld(right) }.to raise_error(PQ::ConflictError)
        merged = left.meld(right) { |_handle, a, b| [a, b].min }
        expect(merged.priority_of(shared)).to eq(1)
        expect(merged.min).to eq("shared")
      end

      it "raises ConflictError when the same entry has different priorities" do
        left = base.decrease_priority(shared, 1)
        right = base.decrease_priority(shared, 2)
        expect { left.meld(right) }.to raise_error(PQ::ConflictError) do |error|
          expect(error.handle).to eq(shared)
          expect(error.priority).to eq(1)
          expect(error.other_priority).to eq(2)
        end
      end

      it "never silently duplicates a conflicting entry" do
        left = base.decrease_priority(shared, 1)
        right = base.decrease_priority(shared, 2)
        merged = left.meld(right) { |_handle, a, b| [a, b].min }
        expect(merged.size).to eq(1)
        expect(merged.priority_of(shared)).to eq(1)
      end

      it "lets the caller resolve conflicts explicitly with a block" do
        left = base.decrease_priority(shared, 1)
        right = base.decrease_priority(shared, 2)
        seen = []
        merged = left.meld(right) do |handle, priority, other_priority|
          seen << [handle, priority, other_priority]
          42
        end
        expect(seen).to eq([[shared, 1, 2]])
        expect(merged.priority_of(shared)).to eq(42)
        expect(merged.min_priority).to eq(42)
      end

      it "keeps an entry which was deleted on one branch but is present on the other" do
        left = base.delete(shared)
        right = base.decrease_priority(shared, 1)
        merged = left.meld(right)
        expect(merged.handle?(shared)).to be(true)
        expect(merged.priority_of(shared)).to eq(1)
      end

      it "still reports a deleted entry as stale after it is removed from the merged queue" do
        left = base.delete(shared)
        merged = left.meld(base)
        expect { merged.delete(shared).delete(shared) }
          .to raise_error(PQ::StaleHandleError)
      end

      it "raises UnknownHandleError for handles foreign to both queues" do
        _, foreign = PQ.new.insert("x", 1)
        merged = base.meld(base)
        expect { merged.delete(foreign) }.to raise_error(PQ::UnknownHandleError)
      end
    end

    context "stable ordering" do
      it "orders equal priorities by insertion time, even across queues" do
        left = PQ.new
        right = PQ.new
        left, = left.insert("first", 0)
        right, = right.insert("second", 0)
        left, = left.insert("third", 0)
        right, = right.insert("fourth", 0)
        expect(left.meld(right).to_a).to eq(%w[first second third fourth])
        expect(right.meld(left).to_a).to eq(%w[first second third fourth])
      end

      it "does not depend on object addresses" do
        left = PQ.new
        right = PQ.new
        objects = 6.times.map { Object.new }
        left, = left.insert(objects[0], 0)
        right, = right.insert(objects[1], 0)
        left, = left.insert(objects[2], 0)
        right, = right.insert(objects[3], 0)
        left, = left.insert(objects[4], 0)
        right, = right.insert(objects[5], 0)
        merged = left.meld(right)
        objects.each do |object|
          expect(merged.min).to equal(object)
          merged = merged.pop
        end
      end

      it "preserves element identities instead of popping and re-inserting" do
        queue = PQ.new
        queue, handle = queue.insert("kept", 1)
        queue, = queue.insert("other", 2)
        merged = queue.meld(PQ.new)
        # a pop-and-reinsert meld would mint fresh identities; the original
        # handle must still address the same entry
        expect(merged.handle?(handle)).to be(true)
        expect(merged.priority_of(handle)).to eq(1)
      end
    end
  end
end
