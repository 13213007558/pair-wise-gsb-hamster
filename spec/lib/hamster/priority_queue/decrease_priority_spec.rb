require "spec_helper"

describe Hamster::PriorityQueue do
  describe "#decrease_priority" do
    it "moves the element towards the front of the queue" do
      queue = PQ.new
      queue, low = queue.insert(1, "low")
      queue, high = queue.insert(9, "high")
      queue = queue.decrease_priority(high, 0)
      expect(queue.peek).to eq([0, "high"])
      expect(queue.priority_of(low)).to eq(1)
    end

    it "does not modify the receiver" do
      queue = PQ.new
      queue, handle = queue.insert(5, "a")
      queue.decrease_priority(handle, 1)
      expect(queue.priority_of(handle)).to eq(5)
    end

    it "keeps the original insertion order among equal priorities" do
      queue = PQ.new
      queue, first = queue.insert(1, "first")
      queue, second = queue.insert(9, "second")
      queue, third = queue.insert(1, "third")
      queue = queue.decrease_priority(second, 1)
      values = []
      until queue.empty?
        _, value, queue = queue.pop
        values << value
      end
      expect(values).to eq(["first", "second", "third"])
    end

    it "is a no-op when the new priority equals the current one" do
      queue = PQ.new
      queue, handle = queue.insert(5, "a")
      expect(queue.decrease_priority(handle, 5)).to be(queue)
    end

    it "raises ArgumentError when the new priority is greater" do
      queue = PQ.new
      queue, handle = queue.insert(5, "a")
      expect { queue.decrease_priority(handle, 6) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when the priorities are not comparable" do
      queue = PQ.new
      queue, handle = queue.insert(5, "a")
      expect { queue.decrease_priority(handle, "high") }.to raise_error(ArgumentError)
    end

    it "raises UnknownHandleError for a handle which was never a member" do
      queue, = PQ.new.insert(1, "a")
      foreign = PQ::Handle.new
      expect { queue.decrease_priority(foreign, 0) }.to raise_error(PQ::UnknownHandleError)
    end

    it "raises DeletedHandleError for a deleted handle" do
      queue = PQ.new
      queue, handle = queue.insert(1, "a")
      queue = queue.delete(handle)
      expect { queue.decrease_priority(handle, 0) }.to raise_error(PQ::DeletedHandleError)
    end

    it "raises DeletedHandleError for an already popped handle" do
      queue = PQ.new
      queue, handle = queue.insert(1, "a")
      _, _, queue = queue.pop
      expect { queue.decrease_priority(handle, 0) }.to raise_error(PQ::DeletedHandleError)
    end
  end
end

