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

  describe "#pop" do
    it "returns nil when the queue is empty" do
      expect(PQ.new.pop).to be_nil
    end

    it "returns the priority, the value, and the new queue" do
      queue, = PQ.new.insert(1, "a")
      priority, value, rest = queue.pop
      expect(priority).to eq(1)
      expect(value).to eq("a")
      expect(rest.empty?).to be(true)
    end

    it "does not modify the receiver" do
      queue, = PQ.new.insert(1, "a")
      queue.pop
      expect(queue.size).to eq(1)
    end

    it "returns elements lowest-priority-first" do
      queue = PQ.new
      [[5, "e"], [1, "a"], [3, "c"], [2, "b"], [4, "d"]].each do |priority, value|
        queue, = queue.insert(priority, value)
      end
      expect(drain(queue)).to eq([[1, "a"], [2, "b"], [3, "c"], [4, "d"], [5, "e"]])
    end

    it "is stable: equal priorities come out in insertion order" do
      queue = PQ.new
      values = (1..30).map { |n| "item-#{n}" }
      values.each { |value| queue, = queue.insert(0, value) }
      expect(drain(queue).map(&:last)).to eq(values)
    end

    it "does not depend on object addresses for ordering" do
      # Interleave allocations of unrelated garbage between insertions; pop
      # order must still be exactly insertion order.
      queue = PQ.new
      values = (1..20).map { |n| "item-#{n}".dup }
      values.each do |value|
        garbage = (1..5).map { Object.new }
        queue, = queue.insert(0, value)
        expect(garbage.size).to eq(5)
      end
      expect(drain(queue).map(&:last)).to eq(values)
    end
  end

  describe "#peek" do
    it "returns nil when the queue is empty" do
      expect(PQ.new.peek).to be_nil
    end

    it "returns the minimum without removing it" do
      queue = PQ.new
      queue, = queue.insert(2, "b")
      queue, = queue.insert(1, "a")
      expect(queue.peek).to eq([1, "a"])
      expect(queue.size).to eq(2)
      expect(queue.peek).to eq([1, "a"])
    end
  end
end

