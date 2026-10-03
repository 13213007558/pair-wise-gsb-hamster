require "spec_helper"
require "hamster/prefix_map"

describe Hamster::PrefixMap do
  let(:map) do
    PM.new([
      ["/api/users", 1],
      ["/api/users/123/posts", 2],
      ["/api/users/456", 3],
      ["/api/groups", 4],
      ["", nil]
    ])
  end

  describe ".new and .[]" do
    it "builds a map from key/value pairs" do
      expect(PM.new([["a", 1], ["b", 2]])).to eql(PM["a" => 1, "b" => 2])
    end

    it "returns the canonical empty map" do
      expect(PM[]).to be(Hamster::PrefixMap.empty)
    end

    it "rejects an invalid key while building" do
      expect { PM.new([["a\xff".dup.force_encoding("UTF-8"), 1]]) }
        .to raise_error(ArgumentError)
    end
  end

  describe "#put" do
    it "inserts and replaces values without changing the old version" do
      updated = map.put("/api/users", 10)

      expect(updated.get("/api/users")).to eq(10)
      expect(map.get("/api/users")).to eq(1)
      expect(map).to be_frozen
      expect(updated).to be_frozen
    end

    it "stores nil distinctly from an absent key" do
      updated = map.put("missing", nil)

      expect(updated.get("missing")).to be_nil
      expect(updated.key?("missing")).to be(true)
      expect(updated.fetch("missing", :default)).to be_nil
      expect(updated.key?("absent")).to be(false)
      expect(updated.fetch("absent", :default)).to eq(:default)
    end

    it "returns self when replacing a value with an equal value" do
      expect(map.put("/api/groups", 4)).to be(map)
    end

    it "supports transforming a value with a block" do
      updated = map.put("/api/users/456") { |value| value + 10 }
      expect(updated.get("/api/users/456")).to eq(13)
    end

    it "passes nil to a block for a missing key, even when nil is stored elsewhere" do
      updated = map.put("missing") { |value| value.inspect }
      expect(updated.get("missing")).to eq("nil")
    end

    it "forks a compressed edge at a Unicode code point" do
      updated = map.put("/api/users/123/comments", 5)

      expect(updated.get("/api/users/123/posts")).to eq(2)
      expect(updated.get("/api/users/123/comments")).to eq(5)
      expect(updated.get("/api/users/456")).to eq(3)
      expect(map.key?("/api/users/123/comments")).to be(false)
    end

    it "inserts a prefix into the middle of an edge" do
      simple = PM.empty.put("foobar", 1)
      updated = simple.put("foo", 2)

      expect(updated.to_h).to eq("foo" => 2, "foobar" => 1)
      expect(simple.to_h).to eq("foobar" => 1)
    end

    it "does not perform case folding or Unicode normalization" do
      updated = map.put("straße", 1).put("Strasse", 2).put("é", 3).put("e\u0301", 4)

      expect(updated.get("straße")).to eq(1)
      expect(updated.get("Strasse")).to eq(2)
      expect(updated.get("é")).to eq(3)
      expect(updated.get("e\u0301")).to eq(4)
    end

    it "rejects non-string and malformed Unicode keys" do
      expect { map.put(:symbol, 1) }.to raise_error(TypeError)
      expect { map.put("a\xff".dup.force_encoding("UTF-8"), 1) }
        .to raise_error(ArgumentError)
    end

    it "does not retain mutations to an inserted string key" do
      key = "dynamic"
      updated = map.put(key, 1)
      key << "changed"

      expect(updated.get("dynamic")).to eq(1)
      expect(updated.key?("dynamicchanged")).to be(false)
    end
  end

  describe "#delete" do
    it "removes a key and merges the remaining edge" do
      updated = map.delete("/api/users/123/posts")

      expect(updated.key?("/api/users/123/posts")).to be(false)
      expect(updated.get("/api/users/456")).to eq(3)
      expect(map.key?("/api/users/123/posts")).to be(true)
    end

    it "removes the empty-string key while retaining other keys" do
      updated = map.delete("")

      expect(updated.key?("")).to be(false)
      expect(updated.get("/api/users")).to eq(1)
      expect(map.key?("")).to be(true)
    end

    it "returns self for an absent key" do
      expect(map.delete("/nope")).to be(map)
    end

    it "returns the canonical empty map after deleting the final key" do
      one = PM["x" => nil]
      expect(one.delete("x")).to be(PM.empty)
    end

    it "keeps nil-valued keys" do
      expect(map.delete("").key?("")).to be(false)
      expect(map.key?("")).to be(true)
    end
  end

  describe "exact lookup" do
    it "finds exact keys but not merely prefixed paths" do
      expect(map.get("/api/users")).to eq(1)
      expect(map.get("/api/users/123")).to be_nil
      expect(map.key?("/api/users/123")).to be(false)
    end

    it "supports fetch defaults, blocks, and KeyError" do
      expect(map.fetch("missing", 9)).to eq(9)
      expect(map.fetch("missing") { |key| key }).to eq("missing")
      expect { map.fetch("missing") }.to raise_error(KeyError)
    end
  end

  describe "#longest_prefix" do
    it "returns the longest stored key/value pair" do
      expect(map.longest_prefix("/api/users/123/posts/extra")).to eq(["/api/users/123/posts", 2])
      expect(map.longest_prefix("/api/users/999")).to eq(["/api/users", 1])
      expect(map.longest_prefix("/elsewhere")).to eq(["", nil])
    end

    it "returns nil when no prefix exists" do
      expect(PM["a" => 1].longest_prefix("b")).to be_nil
    end

    it "offers key and value accessors" do
      expect(map.longest_prefix_key("/api/groups/7")).to eq("/api/groups")
      expect(map.longest_prefix_value("/anything")).to be_nil
    end
  end

  describe "prefix enumeration" do
    let(:reference) { map.to_hash }

    it "matches plain Hash filtering for all tested prefixes" do
      prefixes = ["", "/", "/api", "/api/users", "/api/users/123", "/api/groups", "missing"]

      prefixes.each do |prefix|
        expected = reference.select { |key, _| key.start_with?(prefix) }.sort
        expect(map.each(prefix).to_a).to eq(expected)
      end
    end

    it "enumerates in Unicode code point order" do
      unicode = PM[[["😀/a", 1], ["😀/😀", 2], ["a/😀", 3], ["é", 4]]]
      expect(unicode.each("").map { |key, _| key }).to eq(["a/😀", "é", "😀/a", "😀/😀"])
    end

    it "supports each_key and each_value with a prefix" do
      expect(map.each_key("/api/groups").to_a).to eq(["/api/groups"])
      expect(map.each_value("/api/users").to_a.sort).to eq([1, 2, 3])
    end

    it "returns self with a block" do
      collected = []
      expect(map.each("/api") { |pair| collected << pair }).to be(map)
    end

    it "is lazy for the first item" do
      count = 0
      trace = TracePoint.new(:call) do |event|
        count += 1 if event.method_id == :traverse && event.defined_class == described_class::RadixNode
      end

      enum = map.each("")
      trace.enable { enum.next }
      trace.disable

      expect(count).to be <= 4
    end
  end

  describe "node compression and persistence" do
    it "compresses the common edge for many keys with a long shared prefix" do
     base = "shared/prefix/which/is/very/long/"
      keys = 100.times.map { |index| format("#{base}%03d", 900 + index) }
      compressed = PM[keys.map { |key| [key, key] }]
      root = compressed.instance_variable_get(:@root)
      reference = keys.each_with_object({}) { |key, hash| hash[key] = key }

      expect(root.children.size).to eq(1)
      common_node = root.children.values.first
      expect(common_node.prefix).to eq(base + "9")
      expect(common_node.children.keys.sort).to eq(("0".."9").to_a)
      expect(root.size).to eq(100)
      expect(compressed.each(base).to_a).to eq(reference.sort)
    end

    it "rebuilds only the path when inserting a branch" do
      base = "shared/prefix/which/is/very/long/"
      original = PM[[[base + "first", 1], [base + "second", 2]]]
      original_root = original.instance_variable_get(:@root)
      updated = original.put(base + "first-extra", 3)
      updated_root = updated.instance_variable_get(:@root)

      expect(updated_root).not_to equal(original_root)
      expect(updated.size).to eq(3)
      expect(original.size).to eq(2)
      expect(updated.get(base + "first")).to eq(1)
      expect(updated.get(base + "second")).to eq(2)
      expect(updated.get(base + "first-extra")).to eq(3)
    end

    it "merges a non-terminal branch into its sole remaining edge" do
      branched = PM[[["abc", 1], ["abd", 2]]]
      merged = branched.delete("abd")
      root = merged.instance_variable_get(:@root)

      expect(root.children.size).to eq(1)
      expect(root.children.values.first.prefix).to eq("abc")
      expect(merged.to_h).to eq("abc" => 1)
      expect(branched.to_h).to eq("abc" => 1, "abd" => 2)
    end

    it "removes a side edge while retaining a merged terminal branch" do
      base = "shared/prefix/which/is/very/long/"
      branched = PM[[[base + "first", 1], [base + "first-extra", 2], [base + "second", 3]]]
      merged = branched.delete(base + "first-extra")

      expect(merged.to_h).to eq(base + "first" => 1, base + "second" => 3)
      expect(branched.get(base + "first-extra")).to eq(2)
    end
  end

  describe "collection behavior" do
    it "is enumerable and comparable" do
      expect(map.to_a).to eq(map.to_hash.to_a.sort)
      expect(map).to eql(PM.new(map.to_a))
      expect(map).to eq(map.to_hash)
      expect(map.hash).to eq(PM.new(map.to_a).hash)
    end

    it "selects into another PrefixMap" do
      selected = map.select { |_, value| value.is_a?(Integer) && value > 2 }
      expected = PM[[["/api/users/456", 3], ["/api/groups", 4]]]
      expect(selected).to eql(expected)
    end

    it "marshals values including nil" do
      restored = Marshal.load(Marshal.dump(map))
      expect(restored).to eql(map)
    end

    it "has a readable representation" do
      expect(PM[[["", nil]]].inspect).to eq('Hamster::PrefixMap["" => nil]')
    end
  end
end
