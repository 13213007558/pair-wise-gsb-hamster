require "spec_helper"
require "hamster/measured_deque"

describe Hamster::MeasuredDeque do
  def md(items)
    Hamster::MeasuredDeque.new("", items) { |a, b| a + b }
  end

  describe "#concat" do
    it "joins elements in order" do
      joined = md(%w[a b]).concat(md(%w[c d]))
      expect(joined.to_a).to eq(%w[a b c d])
    end

    it "combines measures with a non-commutative operation in order" do
      joined = md(%w[a b]).concat(md(%w[c d]))
      expect(joined.measure).to eq("abcd")
    end

    it "does not reverse either operand" do
      left  = md(%w[l1 l2 l3])
      right = md(%w[r1 r2 r3])
      joined = left.concat(right)
      expect(joined.to_a).to eq(%w[l1 l2 l3 r1 r2 r3])
      # The total string must read left-to-right; commutativity would not
      # detect a rebalancing that swapped the two halves, but ordering does.
      expect(joined.measure).to eq("l1l2l3r1r2r3")
    end

    it "leaves both operands unchanged" do
      left, right = md(%w[a]), md(%w[b])
      left.concat(right)
      expect(left.to_a).to eq(%w[a])
      expect(right.to_a).to eq(%w[b])
    end

    it "returns an empty operand's partner and handles empty operands" do
      non_empty = md(%w[a])
      empty     = Hamster::MeasuredDeque.empty("") { |a, b| a + b }
      expect(empty.concat(non_empty).to_a).to eq(%w[a])
      expect(non_empty.concat(empty).to_a).to eq(%w[a])
      expect(empty.concat(empty)).to be_empty
    end

    it "supports + and append aliases" do
      expect((md(%w[a]) + md(%w[b])).to_a).to eq(%w[a b])
      expect(md(%w[a]).append(md(%w[b])).measure).to eq("ab")
    end

    it "raises when concatenating a deque with a different identity" do
      strings = md(%w[a])
      numbers = Hamster::MeasuredDeque.new(0, [1]) { |a, b| a + b }
      expect { strings.concat(numbers) }.to raise_error(ArgumentError)
      expect { strings.concat(["b"]) }.to raise_error(ArgumentError)
    end

    it "works for large deques that span multiple tree levels" do
      left  = Array.new(1200) { |i| "L#{i}" }
      right = Array.new(1800) { |i| "R#{i}" }
      joined = md(left).concat(md(right))
      expect(joined.to_a).to eq(left + right)
      expect(joined.size).to eq(3000)
      expect(joined.measure).to eq((left + right).join)
    end
  end

  describe "#reverse_each" do
    it "visits elements from back to front without reversing the deque" do
      seen = []
      md(%w[a b c d]).reverse_each { |x| seen << x }
      expect(seen).to eq(%w[d c b a])
    end
  end
end
