require "spec_helper"
require "hamster/priority_queue"

describe Hamster::PriorityQueue do
  describe "#insert" do
    it "returns a new queue and a handle" do
      queue, handle = PQ.new.insert("a", 1)
      expect(queue).to be_a(PQ)
      expect(handle).to be_a(PQ::Handle)
    end

    it "is aliased as #push" do
      queue, = PQ.new.push("a", 1)
      expect(queue.size).to eq(1)
    end

    it "leaves the receiver unchanged" do
      queue = PQ.new
      queue.insert("a", 1)
      expect(queue).to be_empty
      expect(queue.size).to eq(0)
    end

    it "defaults the priority to the value itself" do
      queue, = PQ.new.insert(5)
      expect(queue.min).to eq(5)
      expect(queue.min_priority).to eq(5)
    end

    it "orders items by priority" do
      queue = PQ.new
      queue, = queue.insert("low", 10)
      queue, = queue.insert("high", 1)
      queue, = queue.insert("mid", 5)
      expect(queue.to_a).to eq(%w[high mid low])
    end

    it "orders equal priorities stably, first in first out" do
      queue = PQ.new
      queue, = queue.insert("first", 1)
      queue, = queue.insert("second", 1)
      queue, = queue.insert("third", 1)
      expect(queue.to_a).to eq(%w[first second third])
    end

    it "treats two insertions of an equal value as distinct members" do
      queue = PQ.new
      queue, handle1 = queue.insert("same", 1)
      queue, handle2 = queue.insert("same", 1)
      expect(handle1).not_to eq(handle2)
      expect(queue.size).to eq(2)
      expect(queue.to_a).to eq(%w[same same])
    end

    it "never compares values, only priorities" do
      values = 3.times.map { Object.new }
      queue = PQ.new
      values.each { |value| queue, = queue.insert(value, 0) }
      values.each do |value|
        expect(queue.min).to equal(value)
        queue = queue.pop
      end
    end

    it "orders distinct objects with equal priorities by insertion, not object address" do
      values = 5.times.map { String.new("x") }
      queue = PQ.new
      values.each { |value| queue, = queue.insert(value, 0) }
      values.each do |value|
        expect(queue.min).to equal(value)
        queue = queue.pop
      end
    end

    it "supports a 2-argument comparator block" do
      queue = PQ.new { |a, b| b <=> a }
      queue, = queue.insert("a", 1)
      queue, = queue.insert("b", 3)
      queue, = queue.insert("c", 2)
      expect(queue.to_a).to eq(%w[b c a])
    end

    it "supports a 1-argument sort key block" do
      queue = PQ.new { |priority| -priority }
      queue, = queue.insert("a", 1)
      queue, = queue.insert("b", 3)
      queue, = queue.insert("c", 2)
      expect(queue.to_a).to eq(%w[b c a])
    end

    it "rejects a comparator block with unsupported arity" do
      expect { PQ.new { |a, b, c| 0 } }.to raise_error(ArgumentError)
    end
  end

  describe "#min and #min_priority" do
    it "return nil for an empty queue" do
      expect(PQ.new.min).to be_nil
      expect(PQ.new.min_priority).to be_nil
    end
  end

  describe "#pop" do
    it "returns the same queue when empty" do
      queue = PQ.new
      expect(queue.pop).to equal(queue)
    end

    it "removes only the minimum item" do
      queue = PQ.new
      queue, = queue.insert("a", 1)
      queue, = queue.insert("b", 1)
      expect(queue.pop.to_a).to eq(["b"])
    end

    it "leaves the receiver unchanged" do
      queue = PQ.new
      queue, = queue.insert("a", 1)
      queue.pop
      expect(queue.size).to eq(1)
    end
  end

  describe Hamster::PriorityQueue::Handle do
    it "is a value object" do
      queue = PQ.new
      queue, handle1 = queue.insert("a", 1)
      queue, handle2 = queue.insert("b", 1)
      expect(handle1).to eq(handle1)
      expect(handle1).not_to eq(handle2)
      expect(handle1).not_to eq("something else")
      expect({ handle1 => :found }[handle1]).to eq(:found)
    end
  end
end
