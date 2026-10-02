require "spec_helper"
require "hamster/measured_deque"

describe Hamster::MeasuredDeque do
  let(:add) { ->(left, right) { left + right } }

  def byte_deque(values)
    Hamster::MeasuredDeque.new(values,
                               identity: 0,
                               measure: :bytesize,
                               combine: add)
  end

  def string_deque(values = [])
    Hamster::MeasuredDeque.new(values,
                               identity: "",
                               combine: :+.to_proc)
  end

  describe "construction and measurement" do
    it "measures items through the supplied measure function" do
      deque = byte_deque(%w[ab cdef g])

      expect(deque.to_a).to eq(%w[ab cdef g])
      expect(deque.size).to eq(3)
      expect(deque.measurement).to eq(7)
      expect(deque.measure).to eq(7)
      expect(deque.first).to eq("ab")
      expect(deque.last).to eq("g")
    end

    it "uses items themselves as measurements when no measure is supplied" do
      deque = Hamster::MeasuredDeque["ab", "cd",
                                     identity: "",
                                     combine: :+.to_proc]

      expect(deque.measurement).to eq("abcd")
    end

    it "accepts the combining operation as a block" do
      deque = Hamster::MeasuredDeque.new([1, 2, 3], identity: 0) { |left, right| left + right }

      expect(deque.measurement).to eq(6)
    end

    it "accepts an explicit options hash for compatibility with older call styles" do
      deque = Hamster::MeasuredDeque.new([1, 2, 3],
                                         { identity: 0, combine: ->(left, right) { left + right } })

      expect(deque.measurement).to eq(6)
    end

    it "returns the identity for an empty deque" do
      deque = Hamster::MeasuredDeque.empty(identity: 0, combine: add)

      expect(deque).to be_empty
      expect(deque.size).to eq(0)
      expect(deque.first).to be_nil
      expect(deque.last).to be_nil
      expect(deque.measurement).to eq(0)
    end

    it "requires an identity and combining operation" do
      expect { Hamster::MeasuredDeque.new([]) }
        .to raise_error(ArgumentError, /identity/)
      expect { Hamster::MeasuredDeque.new([], identity: 0) }
        .to raise_error(ArgumentError, /combine/)
    end
  end

  describe "immutable end operations" do
    let(:deque) { string_deque(%w[a b c]) }

    it "adds and removes at both ends without changing the original" do
      expect(deque.push("d").to_a).to eq(%w[a b c d])
      expect(deque.unshift("z").to_a).to eq(%w[z a b c])
      expect(deque.pop.to_a).to eq(%w[a b])
      expect(deque.shift.to_a).to eq(%w[b c])
      expect(deque.to_a).to eq(%w[a b c])
    end

    it "maintains noncommutative measurements after rebalancing" do
      values = ("a".."z").to_a
      built_from_front = values.reduce(empty_string_deque) { |current, value| current.push(value) }
      built_from_back = values.reverse.reduce(empty_string_deque) { |current, value| current.unshift(value) }

      expect(built_from_front.measurement).to eq("abcdefghijklmnopqrstuvwxyz")
      expect(built_from_back.measurement).to eq("abcdefghijklmnopqrstuvwxyz")
    end

    it "returns frozen derived deques" do
      expect(deque.push("d")).to be_frozen
      expect(deque.pop).to be_frozen
      expect(deque.unshift("z")).to be_frozen
      expect(deque.shift).to be_frozen
    end

    def empty_string_deque
      Hamster::MeasuredDeque.empty(identity: "", combine: :+.to_proc)
    end
  end

  describe "#concat" do
    it "joins sequences and preserves order" do
      left = string_deque(%w[a b])
      right = string_deque(%w[c d])

      expect(left.concat(right).to_a).to eq(%w[a b c d])
      expect(left.concat(right).measurement).to eq("abcd")
      expect(left.to_a).to eq(%w[a b])
    end

    it "accepts a plain enumerable and measures it with the receiver's rules" do
      deque = byte_deque(%w[ab cd])

      expect(deque.concat(%w[ef gh]).measurement).to eq(8)
    end

    it "refuses to combine deques with different monoids" do
      numeric = Hamster::MeasuredDeque.new([1], identity: 0, combine: add)
      textual = string_deque(["a"])

      expect { numeric.concat(textual) }.to raise_error(ArgumentError, /different measurements/)
    end
  end

  describe "#span_measure" do
    let(:deque) { byte_deque(["ab", "cdef", "g"]) }

    it "splits before the first item that makes the predicate truthy" do
      prefix, remainder = deque.span_measure { |bytes| bytes > 4 }

      expect(prefix.to_a).to eq(["ab"])
      expect(remainder.to_a).to eq(["cdef", "g"])
      expect(prefix.measurement).to eq(2)
      expect(remainder.measurement).to eq(5)
    end

    it "places an exact cumulative boundary before the next item" do
      prefix, remainder = deque.span_measure { |bytes| bytes >= 2 }

      expect(prefix).to be_empty
      expect(remainder.to_a).to eq(["ab", "cdef", "g"])
    end

    it "splits before every item when the identity satisfies the predicate" do
      prefix, remainder = deque.span_measure { |bytes| bytes >= 0 }

      expect(prefix).to be_empty
      expect(remainder.to_a).to eq(["ab", "cdef", "g"])
    end

    it "returns the whole deque as prefix when the predicate never matches" do
      prefix, remainder = deque.span_measure { |bytes| bytes > 100 }

      expect(prefix.to_a).to eq(["ab", "cdef", "g"])
      expect(remainder).to be_empty
    end

    it "returns two empty deques for an empty receiver" do
      prefix, remainder = Hamster::MeasuredDeque
        .empty(identity: 0, combine: add)
        .span_measure { |bytes| bytes >= 0 }

      expect(prefix).to be_empty
      expect(remainder).to be_empty
    end

    it "requires a predicate" do
      expect { deque.span_measure }.to raise_error(ArgumentError, /predicate/)
    end

    it "accepts a callable predicate" do
      prefix, remainder = deque.span_measure(->(bytes) { bytes > 4 })

      expect(prefix.to_a).to eq(["ab"])
      expect(remainder.to_a).to eq(["cdef", "g"])
    end

    it "splits directly at a strict cumulative measurement" do
      prefix, remainder = deque.split_at_measure(4)

      expect(prefix.to_a).to eq(["ab"])
      expect(remainder.to_a).to eq(["cdef", "g"])
    end

    it "finds the item containing the matching boundary" do
      expect(deque.find_measure { |bytes| bytes > 4 }).to eq("cdef")
      expect(deque.find_measure { |bytes| bytes > 100 }).to be_nil
      expect(Hamster::MeasuredDeque.empty(identity: 0, combine: add)
        .find_measure { |bytes| bytes > 0 }).to be_nil
    end

    it "does not scan every item on a large balanced deque" do
      values = Array.new(10_000) { "x" }
      large_deque = byte_deque(values)
      predicate_calls = 0

      large_deque.span_measure do |bytes|
        predicate_calls += 1
        bytes > 5_000
      end

      expect(predicate_calls).to be <= (Math.log2(10_000).ceil + 2)
    end

    it "preserves noncommutative string measurements on both sides" do
      deque = string_deque(%w[ab cd ef])
      prefix, remainder = deque.span_measure { |value| value.length > 2 }

      expect(prefix.measurement).to eq("ab")
      expect(remainder.measurement).to eq("cdef")
      expect(prefix.concat(remainder).measurement).to eq("abcdef")
    end
  end

  describe "standard Deque compatibility" do
    it "still constructs without measurement configuration" do
      expect(D["a", "b", "c"].to_a).to eq(%w[a b c])
      expect(D.empty).to be_empty
    end

    it "does not expose measurement methods on an ordinary deque" do
      expect(D["a"]).not_to respond_to(:span_measure)
    end
  end
end
