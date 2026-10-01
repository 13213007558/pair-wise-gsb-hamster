require "spec_helper"
require "hamster/list"

describe Hamster::List do
  describe "#product" do
    context "when passed one or more lists" do
      it "is lazy" do
        expect { Hamster.stream { fail }.product(Hamster.stream { fail }) }.not_to raise_error
      end

      it "uses fair diagonal order for finite inputs" do
        expect(L[0, 1, 2].product(L[:a, :b]).to_a).to eq([
          [0, :a],
          [0, :b], [1, :a],
          [1, :b], [2, :a],
          [2, :b]
        ])
      end

      it "uses fair diagonal order for more than two inputs" do
        expect(L[0, 1].product(L[:a, :b], L[:x, :y]).to_a).to eq([
          [0, :a, :x],
          [0, :a, :y], [0, :b, :x], [1, :a, :x],
          [0, :b, :y], [1, :a, :y], [1, :b, :x],
          [1, :b, :y]
        ])
      end

      it "supports a large finite number of input dimensions" do
        dimensions = 1000
        inputs = Array.new(dimensions - 1) { L[0] }

        expect(L[0].product(*inputs).to_a).to eq([Array.new(dimensions, 0)])
      end

      it "advances every dimension in a small prefix" do
        numbers = Hamster.iterate(0, &:next)
        expect(numbers.product(numbers).take(6).to_a).to eq([
          [0, 0], [0, 1], [1, 0],
          [0, 2], [1, 1], [2, 0]
        ])
      end

      it "does not traverse a finite input while taking a small prefix" do
        accessed = 0
        input = Hamster.enumerate(Enumerator.new do |yielder|
          100.times do
            accessed += 1
            yielder << accessed
          end
        end)

        product = input.product(input)
        4.times do
          product.head
          product = product.tail
        end

        expect(accessed).to eq(3)
      end

      it "does not retrigger source side effects for already realized elements" do
        first_accesses = 0
        second_accesses = 0
        first = Hamster.stream { first_accesses += 1 }
        second = Hamster.stream { second_accesses += 1 }
        product = first.product(second)

        6.times do
          product.head
          product = product.tail
        end

        expect(first_accesses).to eq(3)
        expect(second_accesses).to eq(3)
      end

      it "does not retrigger side effects when one source occupies multiple dimensions" do
        accesses = 0
        source = Hamster.stream { accesses += 1 }
        product = source.product(source)

        6.times do
          product.head
          product = product.tail
        end

        expect(accesses).to eq(3)
      end

      it "continues when one input is finite and another is infinite" do
        infinite = Hamster.iterate(0, &:next)

        expect(infinite.product(L[:a, :b]).take(10).to_a).to eq([
          [0, :a],
          [0, :b], [1, :a],
          [1, :b], [2, :a],
          [2, :b], [3, :a],
          [3, :b], [4, :a],
          [4, :b]
        ])
        expect(L[:a, :b].product(infinite).take(6).to_a).to eq([
          [:a, 0],
          [:a, 1], [:b, 0],
          [:a, 2], [:b, 1],
          [:a, 3]
        ])
      end

      it "returns an empty list when an input is empty" do
        infinite = Hamster.iterate(0, &:next)
        expect(L.empty.product(infinite)).to be_empty
        expect(infinite.product(L.empty)).to be_empty
        expect(L[1].product(L[2], L.empty, infinite)).to be_empty
      end

      it "yields combinations and returns self when passed a block" do
        yielded = []
        receiver = L[1, 2]
        result = receiver.product(L[:a, :b]) { |combination| yielded << combination }

        expect(result).to be(receiver)
        expect(yielded).to eq([[1, :a], [1, :b], [2, :a], [2, :b]])
      end

      it "requires every Cartesian-product argument to be a List" do
        expect { L[1].product([2]) }.to raise_error(TypeError)
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
