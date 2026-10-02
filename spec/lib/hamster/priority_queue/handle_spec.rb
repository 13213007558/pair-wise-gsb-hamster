require "spec_helper"

describe Hamster::PriorityQueue do
  describe "handles" do
    it "identify one insertion: equal values get distinct handles" do
      queue = PQ.new
      queue, first = queue.insert(1, "same")
      queue, second = queue.insert(1, "same")
      expect(first).not_to eq(second)
      queue = queue.decrease_priority(second, 0)
      expect(queue.priority_of(first)).to eq(1)
      expect(queue.priority_of(second)).to eq(0)
    end

    it "are ordered by a logical sequence number, not object address" do
      first = PQ::Handle.new
      second = PQ::Handle.new
      expect(second.id).to be > first.id
    end
  end

  describe "#handle?" do
    it "is true for live members and false otherwise" do
      queue = PQ.new
      queue, handle = queue.insert(1, "a")
      expect(queue.handle?(handle)).to be(true)
      expect(queue.member?(handle)).to be(true)
      expect(queue.include?(handle)).to be(true)
      queue = queue.delete(handle)
      expect(queue.handle?(handle)).to be(false)
      expect(queue.handle?(PQ::Handle.new)).to be(false)
    end
  end

  describe "#priority_of" do
    it "returns the current priority" do
      queue = PQ.new
      queue, handle = queue.insert(5, "a")
      expect(queue.priority_of(handle)).to eq(5)
      queue = queue.decrease_priority(handle, 2)
      expect(queue.priority_of(handle)).to eq(2)
    end

    it "distinguishes deleted handles from handles which never belonged" do
      queue = PQ.new
      queue, deleted = queue.insert(1, "a")
      queue = queue.delete(deleted)
      never = PQ::Handle.new
      expect { queue.priority_of(deleted) }.to raise_error(PQ::DeletedHandleError)
      expect { queue.priority_of(never) }.to raise_error(PQ::UnknownHandleError)
    end
  end

  describe "handle errors" do
    it "are distinguishable but share a common ancestor" do
      expect(PQ::DeletedHandleError.ancestors).to include(PQ::HandleError)
      expect(PQ::UnknownHandleError.ancestors).to include(PQ::HandleError)
      expect(PQ::DeletedHandleError).not_to eq(PQ::UnknownHandleError)
    end

    it "treats a handle from an unrelated queue as unknown" do
      _, foreign = PQ.new.insert(1, "a")
      queue, = PQ.new.insert(1, "b")
      expect { queue.priority_of(foreign) }.to raise_error(PQ::UnknownHandleError)
    end

    it "treats a handle inserted only into a sibling branch as unknown" do
      base, = PQ.new.insert(1, "base")
      _, sibling_only = base.insert(2, "sibling")
      expect { base.priority_of(sibling_only) }.to raise_error(PQ::UnknownHandleError)
    end
  end
end

