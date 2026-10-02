require "spec_helper"

describe Hamster::Hash do
  describe "#edit" do
    let(:hash) { Hamster::Hash["a" => 1, "b" => 2] }

    it "applies many writes and returns an ordinary immutable hash" do
      result = hash.edit do |editor|
        10_000.times { |index| editor.put(index, index) }
        editor["a"] = 10
        editor.delete("b")
      end

      expect(result).to be_a(described_class)
      expect(result).to be_frozen
      expect(result.size).to eq(10_001)
      expect(result["a"]).to eq(10)
      expect(result.key?("b")).to eq(false)
      expect(result[9_999]).to eq(9_999)
    end

    it "does not modify the original hash" do
      result = hash.edit { |editor| editor.put("c", 3) }

      expect(hash.to_h).to eq("a" => 1, "b" => 2)
      expect(result.to_h).to eq("a" => 1, "b" => 2, "c" => 3)
    end

    it "preserves the default block" do
      original = described_class.new { |key| key.to_s * 2 }
      result = original.edit { |editor| editor.put(:a, 1) }

      expect(result[:b]).to eq("bb")
    end

    it "supports a manually closed editor" do
      editor = hash.edit
      editor.put("c", 3)
      result = editor.close

      expect(result["c"]).to eq(3)
      expect(result).to be_frozen
    end

    it "rejects writes after closing, including aliases" do
      editor = hash.edit
      editor.freeze

      expect { editor.put("c", 3) }.to raise_error(Hamster::Editor::ClosedError)
      expect { editor["c"] = 3 }.to raise_error(Hamster::Editor::ClosedError)
      expect { editor.store("c", 3) }.to raise_error(Hamster::Editor::ClosedError)
      expect { editor.delete("a") }.to raise_error(Hamster::Editor::ClosedError)
    end

    it "makes freeze idempotent and returns the same immutable result" do
      editor = hash.edit
      editor.put("c", 3)

      expect(editor.freeze).to equal(editor.freeze)
    end

    it "rejects use from another thread" do
      editor = hash.edit
      error = Thread.new { begin; editor.put(:c, 3); rescue => e; e; end }.value

      expect(error).to be_a(ThreadError)
      expect(hash.key?(:c)).to eq(false)
    end

    it "leaves the old root unchanged when the block raises" do
      expect do
        hash.edit do |editor|
          editor.put("c", 3)
          raise "abort"
        end
      end.to raise_error("abort")

      expect(hash.to_h).to eq("a" => 1, "b" => 2)
    end

    it "keeps two editors and their frozen results independent" do
      left = hash.edit
      right = hash.edit

      left.put("c", 3)
      first = left.freeze
      right.put("c", 4)
      second = right.freeze
      third = hash.edit.freeze

      expect(first["c"]).to eq(3)
      expect(second["c"]).to eq(4)
      expect(third.key?("c")).to eq(false)
      expect(hash.key?("c")).to eq(false)
    end

    it "copies a shared collision child before either editor writes to it" do
      keys = [
        DeterministicHash.new("local", 1),
        DeterministicHash.new("first", 33),
        DeterministicHash.new("second", 65)
      ]
      original = described_class[keys.first(2).map { |key| [key, key.value] }]
      left = original.edit
      right = original.edit

      left.put(keys.last, "left")
      first = left.freeze
      right.delete(keys[1])
      second = right.freeze

      expect(original.map { |key, value| [key.value, value] }.sort).to eq(
        [["first", "first"], ["local", "local"]]
      )
      expect(first.get(keys.last)).to eq("left")
      expect(second.get(keys.last)).to eq(nil)
      expect(second.key?(keys[1])).to eq(false)
    end

    it "cannot mutate nested nodes retained from before closing" do
      original = described_class[(1..40).map { |index| ["key#{index}", index] }]
      editor = original.edit
      retained_child = editor.instance_variable_get(:@trie)
        .instance_variable_get(:@children).compact.first
      editor.put("new", 41)
      editor.freeze

      expect { retained_child.put!(:bad, true) }.to raise_error(FrozenError)
      expect(original.key?("new")).to eq(false)
    end

    it "does not mutate a shared child when promoting an entry during deletion" do
      keys = [
        DeterministicHash.new("local", 1),
        DeterministicHash.new("child-a", 33),
        DeterministicHash.new("child-b", 65),
        DeterministicHash.new("child-c", 97)
      ]
      original = described_class[keys.map { |key| [key, key.value] }]
      result = original.edit { |editor| editor.delete(keys.last) }

      expect(original.size).to eq(4)
      keys.each { |key| expect(original.get(key)).to eq(key.value) }
      expect(result.size).to eq(3)
      expect(result.key?(keys.last)).to eq(false)
    end
  end
end
