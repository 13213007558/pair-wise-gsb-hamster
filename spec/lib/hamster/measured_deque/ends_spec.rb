require "spec_helper"
require "hamster/measured_deque"

describe Hamster::MeasuredDeque do
  let(:sum) { ->(a, b) { a + b } }

  describe "#push / #unshift / #pop / #shift" do
    it "adds at the rear and front" do
      deque = Hamster::MeasuredDeque.empty(0, &sum)
      deque = deque.push(1).push(2).unshift(0)
      expect(deque.to_a).to eq([0, 1, 2])
      expect(deque.first).to eq(0)
      expect(deque.last).to eq(2)
    end

    it "updates the cached measure from either end" do
      deque = Hamster::MeasuredDeque.empty(0, &sum)
      expect(deque.push(5).measure).to eq(5)
      expect(deque.unshift(7).measure).to eq(7)
      expect(deque.push(1).push(2).unshift(3).measure).to eq(6)
    end

    it "removes from either end" do
      deque = Hamster::MeasuredDeque.new(0, [1, 2, 3], &sum)
      expect(deque.pop.to_a).to eq([1, 2])
      expect(deque.shift.to_a).to eq([2, 3])
      expect(deque.pop.measure).to eq(3)
      expect(deque.shift.measure).to eq(5)
    end

    it "leaves the receiver unchanged" do
      deque = Hamster::MeasuredDeque.new(0, [1, 2], &sum)
      deque.push(3)
      deque.unshift(0)
      deque.pop
      deque.shift
      expect(deque.to_a).to eq([1, 2])
      expect(deque.measure).to eq(3)
    end

    it "returns frozen results" do
      deque = Hamster::MeasuredDeque.new(0, [1], &sum)
      expect(deque.push(2)).to be_frozen
      expect(deque.unshift(0)).to be_frozen
      expect(deque.pop).to be_frozen
      expect(deque.shift).to be_frozen
    end

    it "pops and shifts an empty deque to itself" do
      deque = Hamster::MeasuredDeque.empty(0, &sum)
      expect(deque.pop).to equal(deque)
      expect(deque.shift).to equal(deque)
      expect(deque.first).to be_nil
      expect(deque.last).to be_nil
    end

    it "supports enqueue/dequeue aliases" do
      deque = Hamster::MeasuredDeque.empty(0, &sum).enqueue(1).enqueue(2)
      expect(deque.dequeue.to_a).to eq([2])
    end
  end

  describe "#first / #last" do
    it "track the ends as the deque changes shape" do
      deque = Hamster::MeasuredDeque.empty(0, &sum)
      50.times { |i| deque = deque.push(i) }
      expect(deque.first).to eq(0)
      expect(deque.last).to eq(49)
      30.times { deque = deque.shift }
      expect(deque.first).to eq(30)
      15.times { deque = deque.pop }
      expect(deque.to_a).to eq([30, 31, 32, 33, 34])
      expect(deque.last).to eq(34)
    end
  end

  describe "#clear" do
    it "returns an empty deque keeping the same monoid" do
      deque = Hamster::MeasuredDeque.new(0, [1, 2], &sum).clear
      expect(deque).to be_empty
      expect(deque.measure).to eq(0)
    end
  end
end
