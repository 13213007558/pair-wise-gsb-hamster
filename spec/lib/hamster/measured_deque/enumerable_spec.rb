require "spec_helper"
require "hamster/measured_deque"

describe Hamster::MeasuredDeque do
  let(:sum) { ->(a, b) { a + b } }
  let(:deque) { Hamster::MeasuredDeque.new(0, [1, 2, 3, 4], &sum) }

  describe "#each" do
    it "yields front to back and returns self" do
      seen = []
      result = deque.each { |x| seen << x }
      expect(seen).to eq([1, 2, 3, 4])
      expect(result).to equal(deque)
    end

    it "returns an Enumerator without a block" do
      expect(deque.each).to be_an(Enumerator)
      expect(deque.each.to_a).to eq([1, 2, 3, 4])
    end

    it "supports Enumerable methods" do
      expect(deque.map { |x| x * 2 }.to_a).to eq([2, 4, 6, 8])
      expect(deque.select(&:even?).to_a).to eq([2, 4])
      expect(deque.reject(&:even?).to_a).to eq([1, 3])
      expect(deque.reduce(:+)).to eq(10)
      expect(deque.include?(3)).to be(true)
    end
  end

  describe "#map" do
    it "returns a MeasuredDeque with the same monoid" do
      mapped = deque.map { |x| x + 10 }
      expect(mapped).to be_a(Hamster::MeasuredDeque)
      expect(mapped.measure).to eq(50)
    end
  end

  describe "#partition" do
    it "returns two measured deques" do
      evens, odds = deque.partition(&:even?)
      expect(evens.to_a).to eq([2, 4])
      expect(odds.to_a).to eq([1, 3])
      expect(evens.measure).to eq(6)
      expect(odds.measure).to eq(4)
    end
  end

  describe "#group_by" do
    it "groups into a Hamster::Hash of measured deques" do
      groups = deque.group_by(&:even?)
      expect(groups).to be_a(Hamster::Hash)
      expect(groups[true].to_a).to eq([2, 4])
      expect(groups[false].to_a).to eq([1, 3])
    end
  end

  describe "#eql?" do
    it "compares element order" do
      a = Hamster::MeasuredDeque.new(0, [1, 2], &sum)
      b = Hamster::MeasuredDeque.new(0, [1, 2], &sum)
      c = Hamster::MeasuredDeque.new(0, [2, 1], &sum)
      expect(a).to eql(b)
      expect(a == b).to be(true)
      expect(a).to_not eql(c)
      expect(a).to_not eql([1, 2])
    end
  end

  describe "#inspect" do
    it "renders elements in order" do
      deque = Hamster::MeasuredDeque.new("", %w[a b]) { |a, b| a + b }
      expect(deque.inspect).to eq("Hamster::MeasuredDeque[\"a\", \"b\"]")
    end
  end
end
