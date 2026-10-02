require "spec_helper"
require "hamster/measured_deque"

describe Hamster::MeasuredDeque do
  describe "#split" do
    let(:chunks) { Hamster::MeasuredDeque.new("", %w[ab cd ef]) { |a, b| a + b } }

    it "locates the first element whose accumulated measure satisfies the predicate" do
      before, chunk, after = chunks.split { |total| total.bytesize >= 3 }
      expect(before.to_a).to eq(%w[ab])
      expect(chunk).to eq("cd")
      expect(after.to_a).to eq(%w[ef])
    end

    it "uses strict accumulation so a byte offset lands in the right chunk" do
      # offsets 0..1 in "ab", 2..3 in "cd", 4..5 in "ef"
      expectations = {
        0 => "ab", 1 => "ab", 2 => "cd", 3 => "cd", 4 => "ef", 5 => "ef"
      }
      expectations.each do |offset, expected_chunk|
        _before, chunk, _after = chunks.split { |total| total.bytesize > offset }
        expect(chunk).to eq(expected_chunk), "offset #{offset}"
      end
    end

    it "returns the aggregate measures of the two sides in order" do
      before, _chunk, after = chunks.split { |total| total.bytesize > 2 }
      expect(before.measure).to eq("ab")
      expect(after.measure).to eq("ef")
    end

    context "on an empty deque" do
      it "returns [self, nil, self]" do
        deque = Hamster::MeasuredDeque.empty("") { |a, b| a + b }
        before, chunk, after = deque.split { |total| total.bytesize > 0 }
        expect(before).to equal(deque)
        expect(chunk).to be_nil
        expect(after).to equal(deque)
      end
    end

    context "when the predicate never becomes true" do
      it "returns the whole deque before, nil, and an empty deque after" do
        before, chunk, after = chunks.split { |total| total.bytesize > 1000 }
        expect(before.to_a).to eq(%w[ab cd ef])
        expect(chunk).to be_nil
        expect(after).to be_a(Hamster::MeasuredDeque)
        expect(after).to be_empty
        expect(before).to eql(chunks)
      end
    end

    context "when the predicate is true at the identity" do
      it "locates the first element with an empty before" do
        before, chunk, after = chunks.split { |total| total.bytesize >= 0 }
        expect(before).to be_empty
        expect(chunk).to eq("ab")
        expect(after.to_a).to eq(%w[cd ef])
      end
    end

    it "can split off the whole sequence at the final element" do
      before, chunk, after = chunks.split { |total| total == "abcdef" }
      expect(before.to_a).to eq(%w[ab cd])
      expect(chunk).to eq("ef")
      expect(after).to be_empty
    end

    it "works with an additive numeric measure" do
      deque = Hamster::MeasuredDeque.new(0, [1, 2, 3, 4]) { |a, b| a + b }
      before, item, after = deque.split { |total| total >= 6 }
      expect(before.to_a).to eq([1, 2])
      expect(item).to eq(3)
      expect(after.to_a).to eq([4])
    end

    it "keeps string measures in the correct (non-commutative) order" do
      deque = Hamster::MeasuredDeque.new("", %w[a b c d e]) { |a, b| a + b }
      before, item, after = deque.split { |total| total.bytesize >= 3 }
      expect(before.measure).to eq("ab")
      expect(item).to eq("c")
      expect(after.measure).to eq("de")
    end

    it "leaves the receiver unchanged" do
      chunks.split { |total| total.bytesize > 2 }
      expect(chunks.to_a).to eq(%w[ab cd ef])
      expect(chunks.measure).to eq("abcdef")
    end

    it "returns an Enumerator when called without a block" do
      expect(chunks.split).to be_an(Enumerator)
    end

    it "does not scan every element: predicate calls grow only logarithmically" do
      # If splitting walked the whole prefix it would call the predicate O(n)
      # times. A finger tree touches only O(log n) digits/nodes.
      predicate_calls = { 1_000 => nil, 10_000 => nil, 100_000 => nil }
      results = predicate_calls.each_key.map do |n|
        deque = Hamster::MeasuredDeque.new(0, Array.new(n) { 1 }) { |a, b| a + b }
        calls = 0
        deque.split { |total| calls += 1; total >= n / 2 }
        [n, calls]
      end
      results.each do |n, calls|
        expect(calls).to be <= 5 * Math.log2(n).ceil + 5, "n=#{n} calls=#{calls}"
      end
    end
  end

  describe "#take_measure / #drop_measure" do
    let(:deque) { Hamster::MeasuredDeque.new(0, [1, 2, 3, 4]) { |a, b| a + b } }

    it "take_measure returns the elements before the located element" do
      expect(deque.take_measure { |total| total >= 6 }.to_a).to eq([1, 2])
    end

    it "drop_measure returns the located element and the remainder" do
      expect(deque.drop_measure { |total| total >= 6 }.to_a).to eq([3, 4])
    end

    it "take_measure returns everything when nothing is located" do
      expect(deque.take_measure { |total| total > 1000 }.to_a).to eq([1, 2, 3, 4])
    end

    it "drop_measure returns an empty deque when nothing is located" do
      expect(deque.drop_measure { |total| total > 1000 }).to be_empty
    end
  end
end
