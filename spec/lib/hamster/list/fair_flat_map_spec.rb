require "spec_helper"
require "hamster/list"

describe Hamster::List do
  describe "#fair_flat_map" do
    context "with a finite list" do
      it "returns a Hamster::List" do
        expect(L[1, 2].fair_flat_map { |x| L[x] }).to be_a(Hamster::List)
      end

      it "interleaves the sublists" do
        result = L[1, 2, 3].fair_flat_map { |x| L[x, x * 10] }
        expect(result).to eq(L[1, 2, 10, 3, 20, 30])
      end

      it "accepts blocks returning other enumerables" do
        expect(L[[1, 2], [3]].fair_flat_map { |x| x }).to eq(L[1, 3, 2])
      end

      it "returns an empty list for an empty receiver" do
        expect(L[].fair_flat_map { |x| L[x] }).to eq(L[])
      end

      it "skips branches which produce empty lists" do
        result = L[1, 2, 3].fair_flat_map { |x| x == 2 ? L[] : L[x, x * 10] }
        expect(result).to eq(L[1, 3, 10, 30])
      end

      it "returns an Enumerator when no block is given" do
        expect(L[1].fair_flat_map).to be_a(Enumerator)
      end
    end

    context "with an infinite list of infinite sublists" do
      let(:naturals) { Hamster.iterate(0, &:next) }

      it "reaches items of every sublist within a finite number of steps" do
        result = naturals.fair_flat_map { |x| naturals.map { |y| [x, y] } }
        expect(result.take(5)).to eq(L[[0, 0], [1, 0], [0, 1], [2, 0], [0, 2]])
      end

      it "only realizes as much of the input as it needs" do
        realized = []
        counted = Hamster.iterate(0) { |n| realized << n; n + 1 }
        counted.fair_flat_map { |x| counted.map { |y| [x, y] } }.take(10).to_a
        expect(realized.size).to be < 100
      end

      it "does not re-run side effects when a prefix is realized again" do
        realized = []
        counted = Hamster.iterate(0) { |n| realized << n; n + 1 }
        result = counted.fair_flat_map { |x| counted.map { |y| [x, y] } }
        result.take(10).to_a
        count = realized.size
        result.take(10).to_a
        result.take(5).to_a
        expect(realized.size).to eq(count)
      end
    end

    context "with a block that raises" do
      it "yields the items before the failing branch, then raises when it is reached" do
        result = L[1, 2, 3].fair_flat_map { |x| x == 2 ? raise("boom") : L[x] }
        expect(result.head).to eq(1)
        expect { result.tail.head }.to raise_error("boom")
      end

      it "raises when the failing branch of an infinite list is reached" do
        naturals = Hamster.iterate(0, &:next)
        result = naturals.fair_flat_map { |x| x == 2 ? raise("boom") : L[x] }
        expect(result.head).to eq(0)
        expect(result.tail.head).to eq(1)
        expect { result.tail.tail.head }.to raise_error("boom")
      end
    end
  end
end
