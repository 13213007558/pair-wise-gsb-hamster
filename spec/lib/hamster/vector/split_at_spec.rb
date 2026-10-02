require "spec_helper"
require "hamster/vector"

describe Hamster::Vector do
  describe "#split_at" do
    let(:vector) { V.new(1..100) }

    it "splits into two vectors at the given index" do
      left, right = vector.split_at(40)
      expect(left).to eql(V.new(1..40))
      expect(right).to eql(V.new(41..100))
    end

    it "counts negative indices back from the end" do
      left, right = vector.split_at(-10)
      expect(left).to eql(V.new(1..90))
      expect(right).to eql(V.new(91..100))
    end

    it "returns empty vectors when splitting at the boundaries" do
      left, right = vector.split_at(0)
      expect(left).to eql(V.empty)
      expect(right).to eql(vector)

      left, right = vector.split_at(100)
      expect(left).to eql(vector)
      expect(right).to eql(V.empty)

      left, right = vector.split_at(-100)
      expect(left).to eql(V.empty)
      expect(right).to eql(vector)
    end

    it "splits an empty vector into two empty vectors" do
      expect(V.empty.split_at(0)).to eq([V.empty, V.empty])
    end

    it "raises IndexError when the index is out of range" do
      expect { vector.split_at(101) }.to raise_error(IndexError)
      expect { vector.split_at(-101) }.to raise_error(IndexError)
      expect { V.empty.split_at(1) }.to raise_error(IndexError)
      expect { V.empty.split_at(-1) }.to raise_error(IndexError)
    end

    it "preserves the original" do
      vector.split_at(50)
      expect(vector).to eql(V.new(1..100))
    end

    it "matches Array slicing for many sizes and split points" do
      [0, 1, 31, 32, 33, 100, 1023, 1024, 1025, 5000].each do |size|
        array = (1..size).to_a
        vector = V.new(array)
        [0, 1, size / 3, size / 2, size - 1, size].uniq.select { |index| index >= 0 && index <= size }.each do |index|
          left, right = vector.split_at(index)
          expect(left.to_a).to eq(array[0...index])
          expect(right.to_a).to eq(array[index..-1] || [])
          expect(left.size).to eq(index)
          expect(right.size).to eq(size - index)
        end
      end
    end

    it "shares complete internal blocks with the original" do
      vector = V.new(1..1000)
      left, right = vector.split_at(500)
      expect(left.instance_variable_get(:@root)[0]).to equal(vector.instance_variable_get(:@root)[0])
    end

    it "does not copy the whole trie when cutting a single boundary" do
      vector = V.new(1..2048)
      left, right = vector.split_at(1024)
      expect(left.instance_variable_get(:@root)).to equal(vector.instance_variable_get(:@root)[0])
      expect(right.instance_variable_get(:@root)[0]).to equal(vector.instance_variable_get(:@root)[1][0])
      expect(right.instance_variable_get(:@root)[31]).to equal(vector.instance_variable_get(:@root)[1][31])
    end

    it "does not modify the other half when one half is updated" do
      left, right = V.new(1..500).split_at(250)
      updated_left = left.put(0, :x)
      updated_right = right.put(-1, :y)
      expect(left).to eql(V.new(1..250))
      expect(right).to eql(V.new(251..500))
      expect(updated_left.get(0)).to eq(:x)
      expect(updated_right.get(-1)).to eq(:y)
    end

    it "produces halves which can be concatenated back into the original" do
      vector = V.new(1..3000)
      left, right = vector.split_at(1234)
      expect(left.concat_many(right)).to eql(vector)
    end

    it "supports the existing read, slice and update conventions on the halves" do
      left, right = V.new(1..200).split_at(150)
      expect(left[-1]).to eq(150)
      expect(right[0]).to eq(151)
      expect(right[-1]).to eq(200)
      expect(right[0, 5]).to eql(V.new(151..155))
      expect(left[100..-1]).to eql(V.new(101..150))
      expect(right.put(-1, 999).get(49)).to eq(999)
    end
  end
end
