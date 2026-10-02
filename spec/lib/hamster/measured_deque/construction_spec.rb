require "spec_helper"
require "hamster/measured_deque"

describe Hamster::MeasuredDeque do
  describe ".empty" do
    it "requires a combining block" do
      expect { Hamster::MeasuredDeque.empty(0) }.to raise_error(ArgumentError)
    end

    it "builds an empty deque" do
      deque = Hamster::MeasuredDeque.empty(0) { |a, b| a + b }
      expect(deque).to be_empty
      expect(deque.size).to eq(0)
      expect(deque.measure).to eq(0)
      expect(deque.to_a).to eq([])
    end

    it "uses the given identity for an empty deque (string monoid)" do
      deque = Hamster::MeasuredDeque.empty("") { |a, b| a + b }
      expect(deque.measure).to eq("")
    end

    it "returns a frozen, immutable instance" do
      deque = Hamster::MeasuredDeque.empty(0) { |a, b| a + b }
      expect(deque).to be_frozen
      expect(deque).to be_immutable
    end
  end

  describe ".new" do
    it "creates a deque from an enumerable, in order" do
      deque = Hamster::MeasuredDeque.new(0, [1, 2, 3]) { |a, b| a + b }
      expect(deque.to_a).to eq([1, 2, 3])
      expect(deque.size).to eq(3)
    end

    it "accepts a callable combine: instead of a block" do
      deque = Hamster::MeasuredDeque.new(0, [1, 2], combine: ->(a, b) { a + b })
      expect(deque.measure).to eq(3)
    end

    it "derives measures with the measure: callable" do
      deque = Hamster::MeasuredDeque.new(0, %w[ab cdef],
               measure: :bytesize.to_proc) { |a, b| a + b }
      expect(deque.measure).to eq(6)
    end

    it "defaults to an empty item list" do
      deque = Hamster::MeasuredDeque.new(0) { |a, b| a + b }
      expect(deque).to be_empty
    end
  end
end
