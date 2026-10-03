require "spec_helper"
require "hamster/ordered_hash"

describe Hamster::OrderedHash do
  describe "#eql?" do
    it "returns true for identical contents regardless of insertion order" do
      a = OH["A" => 1, "B" => 2]
      b = OH["B" => 2, "A" => 1]
      expect(a).to eql(b)
      expect(a.eql?(b)).to be(true)
    end

    it "returns true for hashes built through different edit histories" do
      a = OH["A" => 1, "B" => 2, "C" => 3]
      b = OH["A" => 1, "B" => 2, "C" => 3, "D" => 4].delete("D")
      expect(a.eql?(b)).to be(true)
    end

    it "returns false when a value differs" do
      expect(OH["A" => 1].eql?(OH["A" => 2])).to be(false)
    end

    it "returns false when a key is missing" do
      expect(OH["A" => 1].eql?(OH["B" => 1])).to be(false)
      expect(OH["A" => 1].eql?(OH["A" => 1, "B" => 2])).to be(false)
    end

    it "returns false for a Hamster::Hash with the same contents" do
      expect(OH["A" => 1].eql?(H["A" => 1])).to be(false)
    end
  end

  describe "#==" do
    it "compares equal to a Ruby hash with the same contents" do
      expect(OH["A" => 1, "B" => 2] == { "B" => 2, "A" => 1 }).to be(true)
      expect(OH["A" => 1] == { "A" => 2 }).to be(false)
    end
  end

  describe "#hash" do
    it "is equal for eql? hashes, regardless of insertion order" do
      expect(OH["A" => 1, "B" => 2].hash).to eq(OH["B" => 2, "A" => 1].hash)
    end
  end

  describe "#inspect" do
    it "renders pairs in insertion order" do
      expect(OH["B" => 2, "A" => 1].inspect).to eq('Hamster::OrderedHash["B" => 2, "A" => 1]')
    end

    it "can be eval'd back to an equal hash" do
      hash = OH["A" => 1, "B" => 2]
      expect(eval(hash.inspect)).to eql(hash)
    end
  end

  describe "#to_hash" do
    it "returns a Ruby hash which iterates in insertion order" do
      ruby_hash = OH["B" => 2, "A" => 1, "C" => 3].to_hash
      expect(ruby_hash).to be_a(::Hash)
      expect(ruby_hash.keys).to eq(%w[B A C])
    end

    it "is aliased as #to_h" do
      expect(OH["A" => 1].to_h).to eq({ "A" => 1 })
    end
  end

  describe "#keys and #values" do
    it "return Vectors in insertion order" do
      hash = OH["B" => 2, "A" => 1, "C" => 3]
      expect(hash.keys).to eql(V["B", "A", "C"])
      expect(hash.values).to eql(V[2, 1, 3])
    end
  end

  describe "#select" do
    let(:hash) { OH["A" => 1, "B" => 2, "C" => 3, "D" => 4] }

    it "keeps matching pairs in their original order" do
      result = hash.select { |key, value| value.even? }
      expect(result).to be_a(Hamster::OrderedHash)
      expect(result.to_a).to eq([["B", 2], ["D", 4]])
    end

    it "returns an enumerator when no block is given" do
      expect(hash.select { true }.size).to eq(4)
      expect(hash.select).to be_a(Enumerator)
    end

    it "supports #reject through the Enumerable mixin" do
      expect(hash.reject { |key, value| value.even? }.to_a).to eq([["A", 1], ["C", 3]])
    end
  end

  describe "#clear" do
    it "returns the canonical empty hash" do
      expect(OH["A" => 1].clear).to be(OH.empty)
    end
  end

  describe "marshalling" do
    it "round-trips contents and insertion order" do
      hash = OH["B" => 2, "A" => 1, "C" => 3].delete("B").put("B", 20)
      loaded = Marshal.load(Marshal.dump(hash))
      expect(loaded).to eql(hash)
      expect(loaded.keys.to_a).to eq(%w[A C B])
    end
  end

  describe "#to_proc" do
    it "acts like #get" do
      hash = OH["A" => 1, "B" => 2]
      expect(%w[A B Z].map(&hash)).to eq([1, 2, nil])
    end
  end
end
