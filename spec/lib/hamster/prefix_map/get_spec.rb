require "spec_helper"
require "hamster/prefix_map"

describe Hamster::PrefixMap do
  let(:map) { Hamster::PrefixMap["abc" => 1, "abd" => 2, "nothing" => nil] }

  describe "#get" do
    it "returns the value for a present key" do
      expect(map.get("abc")).to eq(1)
    end

    it "returns nil for a missing key" do
      expect(map.get("ab")).to be_nil
      expect(map.get("abcd")).to be_nil
      expect(map.get("")).to be_nil
    end

    it "returns nil for a key which diverges mid-edge" do
      expect(map.get("abx")).to be_nil
    end

    it "returns nil for a stored nil value" do
      expect(map.get("nothing")).to be_nil
    end

    it "raises ArgumentError for invalidly encoded keys" do
      key = "\xFF".dup.force_encoding("UTF-8")
      expect { map.get(key) }.to raise_error(ArgumentError)
    end

    it "raises TypeError for non-string keys" do
      expect { map.get(1) }.to raise_error(TypeError)
    end
  end

  describe "#[]" do
    it "behaves like #get" do
      expect(map["abd"]).to eq(2)
      expect(map["nope"]).to be_nil
    end
  end

  describe "#fetch" do
    it "returns the value for a present key" do
      expect(map.fetch("abc")).to eq(1)
    end

    it "returns nil for a stored nil value, not the default" do
      expect(map.fetch("nothing", :default)).to be_nil
    end

    it "returns the default for a missing key" do
      expect(map.fetch("nope", :default)).to eq(:default)
    end

    it "yields the key to the block for a missing key" do
      expect(map.fetch("nope") { |key| key.upcase }).to eq("NOPE")
    end

    it "raises KeyError for a missing key without default or block" do
      expect { map.fetch("nope") }.to raise_error(KeyError)
    end
  end

  describe "#key?" do
    it "is true for present keys" do
      expect(map.key?("abc")).to be(true)
      expect(map.key?("abd")).to be(true)
    end

    it "is true for keys with nil values" do
      expect(map.key?("nothing")).to be(true)
    end

    it "is false for missing keys" do
      expect(map.key?("ab")).to be(false)
      expect(map.key?("abcd")).to be(false)
      expect(map.key?("")).to be(false)
    end
  end

  describe "#empty? and #size" do
    it "reports an empty map" do
      expect(Hamster::PrefixMap.empty).to be_empty
      expect(Hamster::PrefixMap.empty.size).to eq(0)
    end

    it "reports a non-empty map" do
      expect(map).not_to be_empty
      expect(map.size).to eq(3)
    end
  end

  describe "#clear" do
    it "returns an empty map" do
      expect(map.clear).to be_empty
    end
  end

  describe "#eql?" do
    it "is true for maps with the same content" do
      other = Hamster::PrefixMap["abd" => 2, "nothing" => nil, "abc" => 1]
      expect(map).to eql(other)
      expect(map).to eq(other)
    end

    it "is false when a value differs" do
      other = Hamster::PrefixMap["abc" => 1, "abd" => 2, "nothing" => 3]
      expect(map).not_to eql(other)
    end

    it "is false when a key is missing" do
      other = Hamster::PrefixMap["abc" => 1, "abd" => 2]
      expect(map).not_to eql(other)
      expect(other).not_to eql(map)
    end

    it "is false for non-PrefixMap objects" do
      expect(map.eql?("abc")).to be(false)
    end
  end

  describe "#inspect" do
    it "renders like a Hamster collection" do
      expect(Hamster::PrefixMap["a" => 1].inspect).to eq('Hamster::PrefixMap["a" => 1]')
    end
  end
end
