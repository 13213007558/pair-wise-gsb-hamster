require "spec_helper"
require "hamster/list"

describe Hamster::List do
  describe "#product" do
    context "when passed one or more lists" do
      it "returns a lazy Cartesian product" do
        expect(L[1, 2].product(L[:a, :b])).to be_a(Hamster::List)
      end

      it "does not realize any source elements when the product is built" do
        expect do
          Hamster.stream { fail }.product(Hamster.stream { fail })
        end.not_to raise_error
      end

      it "does not realize any source elements when taking no results" do
        expect do
          Hamster.stream { fail }.product(Hamster.stream { fail }).take(0).to_a
        end.not_to raise_error
      end

      it "enumerates two infinite lists in a fair diagonal order" do
        numbers = Hamster.iterate(0, &:next)
        letters = Hamster.iterate("a") { |letter| letter.succ }

        expect(numbers.product(letters).take(10).to_a).to eq([
          [0, "a"], [0, "b"], [1, "a"],
          [0, "c"], [1, "b"], [2, "a"],
          [0, "d"], [1, "c"], [2, "b"], [3, "a"]
        ])
      end

      it "finishes when all inputs are finite" do
        expect(L[1, 2].product(L[:a, :b], L[:x, :y]).to_a).to eq([
          [1, :a, :x], [1, :a, :y], [1, :b, :x], [2, :a, :x],
          [1, :b, :y], [2, :a, :y], [2, :b, :x], [2, :b, :y]
        ])
      end

      it "continues when the first input is infinite and the rest are finite" do
        numbers = Hamster.iterate(0, &:next)

        expect(numbers.product(L[:a, :b]).take(9).to_a).to eq([
          [0, :a], [0, :b], [1, :a],
          [1, :b], [2, :a], [2, :b],
          [3, :a], [3, :b], [4, :a]
        ])
      end

      it "continues when the first input is finite and a later input is infinite" do
        numbers = Hamster.iterate(0, &:next)

        expect(L[1, 2].product(numbers).take(9).to_a).to eq([
          [1, 0], [1, 1], [2, 0],
          [1, 2], [2, 1], [1, 3],
          [2, 2], [1, 4], [2, 3]
        ])
      end

      it "returns an empty product if any input is empty" do
        expect(L[1, 2].product(L.empty, Hamster.stream { fail }).to_a).to eq([])
        expect(L.empty.product(Hamster.stream { fail }).to_a).to eq([])
      end

      it "only realizes the source elements needed for the requested prefix" do
        counts = [0, 0]
        first = Hamster.stream { counts[0] += 1 }
        second = Hamster.stream { counts[1] += 1 }
        product = first.product(second)

        prefix = product.take(6).to_a

        expect(prefix).to eq([
          [1, 1], [1, 2], [2, 1],
          [1, 3], [2, 2], [3, 1]
        ])
        expect(counts).to eq([3, 3])

        expect(product.take(10).to_a.last(4)).to eq([
          [1, 4], [2, 3], [3, 2], [4, 1]
        ])
        expect(counts).to eq([4, 4])
      end

      it "accepts arrays as additional inputs" do
        expect(L[1, 2].product([:a, :b]).to_a).to eq([
          [1, :a], [1, :b], [2, :a], [2, :b]
        ])
      end

      it "preserves false and nil values" do
        expect(L[false, nil].product(L[1]).to_a).to eq([[false, 1], [nil, 1]])
      end

      it "yields each tuple and returns self when passed a block" do
        yielded = []
        list = L[1, 2]

        expect(list.product(L[:a, :b]) { |tuple| yielded << tuple }).to be(list)
        expect(yielded).to eq([
          [1, :a], [1, :b], [2, :a], [2, :b]
        ])
      end
    end

    context "on a really big list" do
      it "doesn't run out of stack" do
        expect { Hamster.interval(0, STACK_OVERFLOW_DEPTH).product }.not_to raise_error
      end
    end

    [
      [[], 1],
      [[2], 2],
      [[1, 3, 5, 7, 11], 1155],
    ].each do |values, expected|
      context "on #{values.inspect}" do
        it "returns #{expected.inspect}" do
          expect(L[*values].product).to eq(expected)
        end
      end
    end
  end
end
