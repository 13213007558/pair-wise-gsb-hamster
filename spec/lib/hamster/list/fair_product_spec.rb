require "spec_helper"
require "hamster/list"

describe Hamster::List do
  describe "#fair_product" do
    context "with finite lists" do
      it "returns all combinations as pairs" do
        result = L[1, 2].fair_product(L[:a, :b])
        expect(result).to eq(L[[1, :a], [2, :a], [1, :b], [2, :b]])
      end

      it "accepts any enumerable as the argument" do
        expect(L[1, 2].fair_product([:a, :b])).to eq(L[[1, :a], [2, :a], [1, :b], [2, :b]])
      end

      it "returns an empty list when the receiver is empty" do
        expect(L[].fair_product(L[1, 2])).to eq(L[])
      end

      it "returns an empty list when the argument is empty" do
        expect(L[1, 2].fair_product(L[])).to eq(L[])
      end
    end

    context "with one finite and one infinite list" do
      let(:naturals) { Hamster.iterate(0, &:next) }

      it "pairs every item of a finite receiver with the infinite list" do
        result = L[1, 2].fair_product(naturals).take(6)
        expect(result).to eq(L[[1, 0], [2, 0], [1, 1], [2, 1], [1, 2], [2, 2]])
      end

      it "pairs every item of an infinite receiver with the finite list" do
        result = naturals.fair_product(L[:a, :b]).take(5)
        expect(result).to eq(L[[0, :a], [1, :a], [0, :b], [2, :a], [1, :b]])
      end
    end

    context "with two infinite lists" do
      let(:naturals) { Hamster.iterate(0, &:next) }

      it "produces a fair prefix instead of reusing the first left item forever" do
        expect(naturals.fair_product(naturals).take(10)).to eq(L[
          [0, 0], [1, 0], [0, 1], [2, 0], [0, 2],
          [1, 1], [0, 3], [3, 0], [0, 4], [1, 2]
        ])
      end

      it "finds every finite target coordinate within a finite prefix" do
        product = naturals.fair_product(naturals)
        [[0, 0], [3, 4], [5, 9], [8, 8]].each do |target|
          found = product.each_with_index.find { |pair, _index| pair == target }
          expect(found).not_to be_nil
          expect(found[1]).to be < 10_000
        end
      end

      it "only realizes as much of the inputs as it needs" do
        realized = []
        counted = Hamster.iterate(0) { |n| realized << n; n + 1 }
        counted.fair_product(counted).take(10).to_a
        expect(realized.size).to be < 100
      end

      it "does not re-run side effects when a prefix is realized again" do
        realized = []
        counted = Hamster.iterate(0) { |n| realized << n; n + 1 }
        product = counted.fair_product(counted)
        product.take(10).to_a
        count = realized.size
        product.take(10).to_a
        product.take(5).to_a
        expect(realized.size).to eq(count)
      end
    end

    context "with a branch that raises" do
      it "yields the pairs before the failure, then raises when it is reached" do
        naturals = Hamster.iterate(0, &:next)
        boom = L[0, 1].append(Hamster::LazyList.new { raise "boom" })
        result = naturals.fair_product(boom)
        expect(result.each.take(4)).to eq([[0, 0], [1, 0], [0, 1], [2, 0]])
        expect { result.drop(4).head }.to raise_error("boom")
      end
    end
  end
end
