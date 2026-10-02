require "spec_helper"
require "hamster/priority_queue"

describe Hamster::PriorityQueue do
  describe "#decrease_priority" do
    let!(:queue) do
      queue = PQ.new
      queue, @handle_a = queue.insert("a", 5)
      queue, @handle_b = queue.insert("b", 10)
      queue
    end

    def handle_a; @handle_a; end
    def handle_b; @handle_b; end

    it "moves the entry towards the front" do
      updated = queue.decrease_priority(handle_b, 1)
      expect(updated.min).to eq("b")
      expect(updated.priority_of(handle_b)).to eq(1)
    end

    it "leaves the receiver unchanged" do
      queue.decrease_priority(handle_b, 1)
      expect(queue.priority_of(handle_b)).to eq(10)
      expect(queue.min).to eq("a")
    end

    it "accepts an equal priority" do
      updated = queue.decrease_priority(handle_b, 10)
      expect(updated.priority_of(handle_b)).to eq(10)
      expect(updated.to_a).to eq(queue.to_a)
    end

    it "raises ArgumentError when the new priority is greater" do
      expect { queue.decrease_priority(handle_a, 6) }.to raise_error(ArgumentError)
    end

    it "respects a custom comparator when checking the direction" do
      queue = PQ.new { |a, b| b <=> a }
      queue, handle = queue.insert("a", 5)
      expect { queue.decrease_priority(handle, 1) }.to raise_error(ArgumentError)
      expect(queue.decrease_priority(handle, 9).priority_of(handle)).to eq(9)
    end

    it "keeps the entry retrievable under the same handle" do
      updated = queue.decrease_priority(handle_b, 1)
      expect(updated.handle?(handle_b)).to be(true)
      expect(updated.delete(handle_b).to_a).to eq(["a"])
    end

    context "with a handle which is not part of this version" do
      it "raises UnknownHandleError for a handle from an unrelated queue" do
        _, foreign = PQ.new.insert("x", 1)
        expect { queue.decrease_priority(foreign, 0) }
          .to raise_error(PQ::UnknownHandleError)
      end

      it "raises UnknownHandleError for a handle inserted only into a sibling branch" do
        _, foreign = queue.insert("x", 1)
        expect { queue.decrease_priority(foreign, 0) }
          .to raise_error(PQ::UnknownHandleError)
      end

      it "raises StaleHandleError for a deleted entry" do
        stale = queue.delete(handle_a)
        expect { stale.decrease_priority(handle_a, 0) }
          .to raise_error(PQ::StaleHandleError)
      end

      it "raises StaleHandleError for a popped entry" do
        popped = queue.pop
        expect { popped.decrease_priority(handle_a, 0) }
          .to raise_error(PQ::StaleHandleError)
      end

      it "raises TypeError for something which is not a handle" do
        expect { queue.decrease_priority(42, 0) }.to raise_error(TypeError)
      end

      it "distinguishes the error classes under a common ancestor" do
        expect(PQ::UnknownHandleError.ancestors).to include(PQ::InvalidHandleError)
        expect(PQ::StaleHandleError.ancestors).to include(PQ::InvalidHandleError)
        expect(PQ::UnknownHandleError).not_to eq(PQ::StaleHandleError)
      end
    end
  end
end
