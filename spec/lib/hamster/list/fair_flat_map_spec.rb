require "spec_helper"
require "hamster/list"
require "hamster"

describe Hamster::List do
  describe "#fair_flat_map" do
    it "returns an Enumerator when no block is given" do
      expect(L[1, 2].fair_flat_map).to be_a(Enumerator)
    end

    context "with an empty list" do
      it "returns an empty list" do
        expect(L[].fair_flat_map { |x| [x] }).to eq(L[])
      end
    end

    context "with a block that returns empty lists" do
      it "returns an empty list" do
        expect(L[1, 2, 3].fair_flat_map { [] }).to eq(L[])
      end
    end

    context "with finite lists" do
      it "interleaves the lists along anti-diagonals" do
        result = L[1, 2, 3].fair_flat_map { |x| L[x, x * 10, x * 100] }
        expect(result).to eq(L[1, 2, 10, 3, 20, 100, 30, 200, 300])
      end

      it "accepts arrays returned by the block" do
        expect(L[1, 2].fair_flat_map { |x| [x, x] }).to eq(L[1, 2, 1, 2])
      end
    end

    context "with empty branches mixed in" do
      it "skips them without disturbing the fair order" do
        result = L[1, 2, 3].fair_flat_map { |x| x == 2 ? L[] : L[x, x * 10] }
        expect(result).to eq(L[1, 10, 3, 30])
      end
    end

    context "with an infinite list of infinite lists" do
      let(:naturals) { Hamster.iterate(0) { |n| n + 1 } }

      it "reaches every finite coordinate in a finite number of steps" do
        result = naturals.fair_flat_map { |n| naturals.map { |m| [n, m] } }
        expect(result.take(10)).to eq(L[
          [0, 0],
          [1, 0], [0, 1],
          [2, 0], [1, 1], [0, 2],
          [3, 0], [2, 1], [1, 2], [0, 3]
        ])
      end
    end

    describe "laziness" do
      # a "counted" infinite list of naturals: each realized element bumps the counter
      def counted_naturals(counter)
        Hamster.stream { counter << counter.size }
      end

      it "only realizes a small prefix of the inputs when taking 10 items" do
        outer_count = []
        inner_counts = Hash.new { |hash, key| hash[key] = [] }
        outer = counted_naturals(outer_count)
        result = outer.fair_flat_map { |n| counted_naturals(inner_counts[n]) }
        result.take(10).to_a
        expect(outer_count.size).to be <= 6
        expect(inner_counts.values.map(&:size).reduce(0, :+)).to be <= 21
      end

      it "calls the block only once per item, even when the prefix is re-traversed" do
        calls = []
        result = Hamster.iterate(0) { |n| n + 1 }.fair_flat_map do |n|
          calls << n
          L[n]
        end
        result.take(3).to_a
        expect(calls).to eq(calls.uniq)
        count = calls.size
        result.take(3).to_a
        result.take(2).to_a
        expect(calls.size).to eq(count)
      end

      it "does not re-realize input elements when the prefix is re-traversed" do
        realized = []
        result = counted_naturals(realized).fair_flat_map { |n| L[n] }
        result.take(5).to_a
        count = realized.size
        result.take(5).to_a
        result.take(3).to_a
        expect(realized.size).to eq(count)
      end
    end

    describe "exception ordering" do
      it "yields the elements before the failing one, then raises" do
        result = Hamster.iterate(0) { |n| n + 1 }.fair_flat_map do |n|
          n == 2 ? (raise "boom") : L[n]
        end
        seen = []
        expect { result.each { |x| seen << x } }.to raise_error("boom")
        expect(seen).to eq([0, 1])
      end

      it "raises at the position of the failing element inside a branch" do
        failing = Hamster.stream { raise "branch boom" }
        result = L[0, 1].fair_flat_map { |n| n == 1 ? failing : L[n, n] }
        seen = []
        expect { result.each { |x| seen << x } }.to raise_error("branch boom")
        expect(seen).to eq([0])
      end
    end
  end
end
