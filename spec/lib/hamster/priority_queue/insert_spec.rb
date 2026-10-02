require "spec_helper"

describe Hamster::PriorityQueue do
  describe "#insert" do
    it "returns the new queue and a handle" do
      queue, handle = PQ.new.insert(1, "a")
      expect(queue).to be_a(PQ)
      expect(handle).to be_a(PQ::Handle)
    end

    it "does not modify the receiver" do
      queue = PQ.new
      queue.insert(1, "a")
      expect(queue.empty?).to be(true)
      expect(queue.size).to eq(0)
    end

    it "increases the size by one" do
      queue, = PQ.new.insert(1, "a")
      queue, = queue.insert(2, "b")
      expect(queue.size).to eq(2)
    end

    it "treats two insertions of an equal value as two distinct members" do
      queue = PQ.new
      queue, first = queue.insert(1, "same")
      queue, second = queue.insert(1, "same")
      expect(first).not_to eq(second)
      expect(queue.size).to eq(2)
      expect(queue.handle?(first)).to be(true)
      expect(queue.handle?(second)).to be(true)
    end

    it "defaults the value to nil" do
      queue, = PQ.new.insert(1)
      expect(queue.peek).to eq([1, nil])
    end
  end

  describe ".empty" do
    it "returns an empty queue" do
      expect(PQ.empty.empty?).to be(true)
      expect(PQ.empty.size).to eq(0)
    end
  end
end

