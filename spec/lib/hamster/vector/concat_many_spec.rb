require "spec_helper"
require "hamster/vector"

describe Hamster::Vector do
  describe "#concat_many" do
    let(:vector) { V.new(1..100) }

    it "preserves the original" do
      vector.concat_many(V.new(101..200), V.new(201..300))
      expect(vector).to eql(V.new(1..100))
    end

    it "appends the elements of each argument in order" do
      result = vector.concat_many(V.new(101..200), [201, 202], 203..210)
      expect(result).to eql(V.new(1..210))
    end

    it "accepts a single array of vectors" do
      result = vector.concat_many([V.new(101..150), V.new(151..200)])
      expect(result).to eql(V.new(1..200))
    end

    it "returns self when there is nothing to append" do
      expect(vector.concat_many).to equal(vector)
      expect(vector.concat_many(V.empty)).to equal(vector)
    end

    it "concatenates empty vectors" do
      expect(V.empty.concat_many(V.empty)).to eql(V.empty)
      expect(V.empty.concat_many(vector)).to eql(vector)
      expect(vector.concat_many(V.empty, V.empty)).to eql(vector)
    end

    it "matches Array#concat for many combinations of sizes" do
      sizes = [0, 1, 31, 32, 33, 100, 1023, 1024, 1025]
      sizes.each do |left_size|
        sizes.each do |right_size|
          left  = V.new(1..left_size)
          right = V.new((left_size + 1)..(left_size + right_size))
          result = left.concat_many(right)
          expect(result.to_a).to eq((1..(left_size + right_size)).to_a)
          expect(result.size).to eq(left_size + right_size)
        end
      end
    end

    it "concatenates many batches of different heights" do
      batches = [V.new(1..5), V.new(6..2000), V.new(2001..2048), V.new(2049..3000), V[3001]]
      result = V.empty.concat_many(*batches)
      expect(result).to eql(V.new(1..3001))
      expect(result.to_a).to eq((1..3001).to_a)
    end

    it "reuses complete internal blocks of the source vectors" do
      left  = V.new(1..1024)
      right = V.new(1025..2048)
      result = left.concat_many(right)
      expect(result.instance_variable_get(:@root)[0]).to equal(left.instance_variable_get(:@root))
      expect(result.instance_variable_get(:@root)[1]).to equal(right.instance_variable_get(:@root))
    end

    it "shares whole leaves across batch boundaries" do
      left  = V.new(1..96)   # 3 full leaves
      right = V.new(97..160) # 2 full leaves
      result = left.concat_many(right)
      root = result.instance_variable_get(:@root)
      expect(root[0]).to equal(left.instance_variable_get(:@root)[0])
      expect(root[2]).to equal(left.instance_variable_get(:@root)[2])
      expect(root[3]).to equal(right.instance_variable_get(:@root)[0])
      expect(root[4]).to equal(right.instance_variable_get(:@root)[1])
    end

    it "does not modify the inputs when the result is updated" do
      left  = V.new(1..100)
      right = V.new(101..200)
      result = left.concat_many(right)
      updated = result.put(0, :x).put(-1, :y)
      expect(left).to eql(V.new(1..100))
      expect(right).to eql(V.new(101..200))
      expect(result).to eql(V.new(1..200))
      expect(updated.get(0)).to eq(:x)
      expect(updated.get(-1)).to eq(:y)
    end

    it "keeps trie depth logarithmic when concatenating many small batches" do
      result = V.empty
      1000.times { |i| result = result.concat_many([i]) }
      expect(result.to_a).to eq((0...1000).to_a)
      expect(result.instance_variable_get(:@levels)).to eq(V.new(0...1000).instance_variable_get(:@levels))
    end

    it "supports the existing read, slice and update conventions on the result" do
      result = V.new(1..100).concat_many(V.new(101..200))
      expect(result[150]).to eq(151)
      expect(result[-1]).to eq(200)
      expect(result[10, 5]).to eql(V.new(11..15))
      expect(result[95..105]).to eql(V.new(96..106))
      expect(result.put(-1, 999).get(199)).to eq(999)
    end
  end

  describe ".concat_many" do
    it "concatenates all the given collections into a new vector" do
      expect(V.concat_many(V.new(1..50), V.new(51..100))).to eql(V.new(1..100))
      expect(V.concat_many([1, 2], V[3, 4])).to eql(V[1, 2, 3, 4])
      expect(V.concat_many).to eql(V.empty)
    end
  end
end
