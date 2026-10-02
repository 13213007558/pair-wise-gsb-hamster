require "spec_helper"
require "hamster/list"
require "hamster"

describe Hamster::List do
  describe "#fair_product" do
    # a "counted" infinite list of naturals: each realized element bumps the counter
    def counted_naturals(counter)
      Hamster.stream { counter << counter.size }
    end

    context "with two finite lists" do
      it "returns pairs interleaved along anti-diagonals" do
        expect(L[1, 2].fair_product(L[:a, :b])).to eq(L[[1, :a], [2, :a], [1, :b], [2, :b]])
      end

      it "accepts any enumerable as the other list" do
        expect(L[1, 2].fair_product([:a, :b])).to eq(L[[1, :a], [2, :a], [1, :b], [2, :b]])
      end
    end

    context "with an empty list" do
      it "returns an empty list" do
        expect(L[].fair_product(L[1, 2])).to eq(L[])
        expect(L[1, 2].fair_product(L[])).to eq(L[])
      end
    end

    context "with two infinite lists" do
      let(:naturals) { Hamster.iterate(0) { |n| n + 1 } }

      it "produces pairs in anti-diagonal order" do
        expect(naturals.fair_product(naturals).take(10)).to eq(L[
          [0, 0],
          [1, 0], [0, 1],
          [2, 0], [1, 1], [0, 2],
          [3, 0], [2, 1], [1, 2], [0, 3]
        ])
      end

      it "finds every finite coordinate at a finite index" do
        product = naturals.fair_product(naturals)
        [[0, 0], [1, 0], [0, 1], [3, 4], [50, 100], [100, 50]].each do |target|
          index = product.each_with_index { |pair, idx| break idx if pair == target }
          diagonal = target[0] + target[1]
          expect(index).to eq(diagonal * (diagonal + 1) / 2 + target[1])
        end
      end

      it "mixes finite and infinite lists" do
        expect(L[:a, :b].fair_product(naturals).take(5)).to eq(L[
          [:a, 0], [:b, 0], [:a, 1], [:b, 1], [:a, 2]
        ])
        expect(naturals.fair_product(L[:a, :b]).take(5)).to eq(L[
          [0, :a], [1, :a], [0, :b], [2, :a], [1, :b]
        ])
      end
    end

    describe "laziness" do
      it "only realizes a handful of input elements when taking 10 pairs" do
        left_count, right_count = [], []
        product = counted_naturals(left_count).fair_product(counted_naturals(right_count))
        product.take(10).to_a
        expect(left_count.size).to be <= 6
        expect(right_count.size).to be <= 6
      end

      it "does not re-realize input elements when the prefix is re-traversed" do
        left_count, right_count = [], []
        product = counted_naturals(left_count).fair_product(counted_naturals(right_count))
        product.take(10).to_a
        counts = [left_count.size, right_count.size]
        product.take(10).to_a
        product.take(6).to_a
        expect([left_count.size, right_count.size]).to eq(counts)
      end
    end

    describe "exception ordering" do
      it "produces the pairs before the failing one, then raises" do
        left = Hamster.iterate(0) { |n| n + 1 }.map do |n|
          raise "left boom" if n == 2
          n
        end
        product = left.fair_product(Hamster.iterate(0) { |n| n + 1 })
        seen = []
        expect { product.each { |pair| seen << pair } }.to raise_error("left boom")
        expect(seen).to eq([[0, 0], [1, 0], [0, 1]])
      end
    end
  end
end
