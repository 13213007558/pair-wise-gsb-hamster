require "spec_helper"
require "hamster/priority_queue"

describe Hamster::PriorityQueue do
  describe "#delete" do
    let!(:queue) do
      queue = PQ.new
      queue, @handle_a = queue.insert("a", 1)
      queue, @handle_b = queue.insert("b", 2)
      queue
    end

    def handle_a; @handle_a; end
    def handle_b; @handle_b; end

    it "removes the entry" do
      expect(queue.delete(handle_a).to_a).to eq(["b"])
    end

    it "leaves the receiver unchanged" do
      queue.delete(handle_a)
      expect(queue.size).to eq(2)
      expect(queue.handle?(handle_a)).to be(true)
    end

    it "removes only one of two members with equal values" do
      queue = PQ.new
      queue, handle1 = queue.insert("same", 1)
      queue, = queue.insert("same", 1)
      expect(queue.delete(handle1).to_a).to eq(["same"])
    end

    it "invalidates the handle in the new version" do
      updated = queue.delete(handle_a)
      expect(updated.handle?(handle_a)).to be(false)
      expect(updated.handle?(handle_b)).to be(true)
    end

    it "raises StaleHandleError when deleting twice from the same version" do
      updated = queue.delete(handle_a)
      expect { updated.delete(handle_a) }.to raise_error(PQ::StaleHandleError)
    end

    it "raises UnknownHandleError for a handle from an unrelated queue" do
      _, foreign = PQ.new.insert("x", 1)
      expect { queue.delete(foreign) }.to raise_error(PQ::UnknownHandleError)
    end

    it "raises TypeError for something which is not a handle" do
      expect { queue.delete("a") }.to raise_error(TypeError)
    end
  end

  describe "#handle? and #priority_of" do
    it "reports live entries" do
      queue = PQ.new
      queue, handle = queue.insert("a", 7)
      expect(queue.handle?(handle)).to be(true)
      expect(queue.priority_of(handle)).to eq(7)
    end

    it "returns false for foreign or non-handle arguments" do
      queue, = PQ.new.insert("a", 1)
      _, foreign = PQ.new.insert("b", 1)
      expect(queue.handle?(foreign)).to be(false)
      expect(queue.handle?(nil)).to be(false)
    end

    it "raises StaleHandleError from #priority_of after deletion" do
      queue = PQ.new
      queue, handle = queue.insert("a", 7)
      expect { queue.delete(handle).priority_of(handle) }
        .to raise_error(PQ::StaleHandleError)
    end
  end
end
