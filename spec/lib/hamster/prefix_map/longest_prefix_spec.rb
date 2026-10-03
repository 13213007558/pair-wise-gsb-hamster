require "spec_helper"
require "hamster/prefix_map"

describe Hamster::PrefixMap do
  describe "#longest_prefix" do
    let(:map) do
      Hamster::PrefixMap[
        "services" => 1,
        "services/api" => 2,
        "services/api/v2" => 3,
        "static" => 4,
      ]
    end

    it "returns the longest stored key which prefixes the query" do
      expect(map.longest_prefix("services/api/v2/users")).to eq("services/api/v2")
      expect(map.longest_prefix("services/api/v3")).to eq("services/api")
      expect(map.longest_prefix("services/web")).to eq("services")
      expect(map.longest_prefix("static/img")).to eq("static")
    end

    it "returns the key itself for an exact match" do
      expect(map.longest_prefix("services/api")).to eq("services/api")
    end

    it "returns nil when no key prefixes the query" do
      expect(map.longest_prefix("other")).to be_nil
      expect(Hamster::PrefixMap.empty.longest_prefix("anything")).to be_nil
    end

    it "does not match a key when the query ends in the middle of an edge" do
      expect(map.longest_prefix("serv")).to be_nil
      expect(map.longest_prefix("services/ap")).to eq("services")
    end

    it "uses the empty string key as a default matching everything" do
      with_default = Hamster::PrefixMap["" => 0, "services" => 1]
      expect(with_default.longest_prefix("unmatched")).to eq("")
      expect(with_default.longest_prefix("")).to eq("")
      expect(with_default.longest_prefix("services/x")).to eq("services")
    end

    it "matches by codepoints, not bytes" do
      map = Hamster::PrefixMap["日本語" => 1]
      expect(map.longest_prefix("日本語の文章")).to eq("日本語")
      expect(map.longest_prefix("日本")).to be_nil
    end

    it "does not fold case or normalize" do
      map = Hamster::PrefixMap["ABC" => 1]
      expect(map.longest_prefix("abcdef")).to be_nil
    end

    it "raises ArgumentError for invalidly encoded queries" do
      query = "\xFF".dup.force_encoding("UTF-8")
      expect { map.longest_prefix(query) }.to raise_error(ArgumentError)
    end

    it "raises TypeError for non-string queries" do
      expect { map.longest_prefix(nil) }.to raise_error(TypeError)
    end
  end

  describe "#longest_prefix_entry" do
    it "returns the key and value of the longest prefix match" do
      map = Hamster::PrefixMap["a" => 1, "abc" => 2]
      expect(map.longest_prefix_entry("abcdef")).to eq(["abc", 2])
    end

    it "returns nil when nothing matches" do
      expect(Hamster::PrefixMap.empty.longest_prefix_entry("x")).to be_nil
    end

    it "returns entries with nil values" do
      map = Hamster::PrefixMap["a" => nil]
      expect(map.longest_prefix_entry("abc")).to eq(["a", nil])
    end
  end
end
