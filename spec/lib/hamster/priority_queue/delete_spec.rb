require "spec_helper"

describe Hamster::PriorityQueue do
  describe "#delete" do
    it "removes the element identified by the handle" do
      queue = PQ.new
      queue, keep = queue.insert(1, "keep")
      queue, drop = queue.insert(2, "drop")
      queue = queue.delete(drop)
      expect(queue.size).to eq(1)
      expect(queue.handle?(drop)).to be(false)
      expect(queue.peek).to eq([1, "keep"])
    end

    it "does not modify the receiver" do
      queue = PQ.new
      queue, handle = queue.insert(1, "a")
      queue.delete(handle)
      expect(queue.handle?(handle)).to be(true)
      expect(queue.size).to eq(1)
    end

    it "only removes the member the handle refers to, not equal values" do
      queue = PQ.new
      queue, first = queue.insert(1, "same")
      queue, second = queue.insert(1, "same")
      queue = queue.delete(first)
      expect(queue.handle?(first)).to be(false)
      expect(queue.handle?(second)).to be(true)
      expect(queue.size).to eq(1)
    end

    it "raises UnknownHandleError for a handle which was never a member" do
      queue, = PQ.new.insert(1, "a")
      expect { queue.delete(PQ::Handle.new) }.to raise_error(PQ::UnknownHandleError)
    end

    it "raises DeletedHandleError when the element was already deleted" do
      queue = PQ.new
      queue, handle = queue.insert(1, "a")
      queue = queue.delete(handle)
      expect { queue.delete(handle) }.to raise_error(PQ::DeletedHandleError)
    end

    it "raises DeletedHandleError when the element was already popped" do
      queue = PQ.new
      queue, handle = queue.insert(1, "a")
      _, _, queue = queue.pop
      expect { queue.delete(handle) }.to raise_error(PQ::DeletedHandleError)
    end
  end
end

