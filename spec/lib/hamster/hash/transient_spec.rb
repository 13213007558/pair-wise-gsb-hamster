require "spec_helper"
require "hamster/hash"

describe Hamster::Hash do
  describe "#transient" do
    let(:hash) { H["A" => "aye", "B" => "bee", "C" => "see"] }

    it "returns a TransientHash seeded with the same contents" do
      editor = hash.transient
      expect(editor).to be_a(Hamster::TransientHash)
      expect(editor.size).to eq(3)
      expect(editor.get("A")).to eq("aye")
    end

    it "applies a batch of edits and persists them into an immutable Hash" do
      editor = hash.transient
      1000.times { |i| editor.put(i, i * 2) }
      editor.delete("A")
      result = editor.persistent!
      expect(result).to be_a(Hamster::Hash)
      expect(result.size).to eq(1002)
      expect(result[500]).to eq(1000)
      expect(result.key?("A")).to be(false)
      expect(result["B"]).to eq("bee")
    end

    it "produces the same result as equivalent persistent updates" do
      editor = hash.transient
      expected = hash
      500.times do |i|
        editor.put(i, i)
        expected = expected.put(i, i)
      end
      100.times do |i|
        editor.delete(i * 3)
        expected = expected.delete(i * 3)
      end
      expect(editor.persistent!).to eql(expected)
    end

    it "never modifies the original hash" do
      editor = hash.transient
      editor.put("A", "changed")
      editor.delete("B")
      100.times { |i| editor.put(i, i) }
      expect(hash).to eql(H["A" => "aye", "B" => "bee", "C" => "see"])
    end

    it "supports put with a block" do
      editor = hash.transient
      editor.put("A") { |current| current.upcase }
      expect(editor.persistent!["A"]).to eq("AYE")
    end

    it "supports store and []=, returning the stored value" do
      editor = hash.transient
      expect(editor.store("D", "dee")).to eq("dee")
      expect(editor["E"] = "ee").to eq("ee")
      result = editor.persistent!
      expect(result["D"]).to eq("dee")
      expect(result["E"]).to eq("ee")
    end

    it "returns the deleted value from delete, or nil when missing" do
      editor = hash.transient
      expect(editor.delete("A")).to eq("aye")
      expect(editor.delete("missing")).to be_nil
      expect(editor.size).to eq(2)
    end

    context "with a block" do
      it "yields the editor and returns the persisted hash" do
        result = hash.transient do |editor|
          editor.put("D", "dee")
          editor.delete("A")
        end
        expect(result).to eql(H["B" => "bee", "C" => "see", "D" => "dee"])
      end

      it "kills the editor when the block raises, leaving the original unchanged" do
        captured = nil
        expect {
          hash.transient do |editor|
            captured = editor
            editor.put("D", "dee")
            raise "boom"
          end
        }.to raise_error("boom")
        expect(hash).to eql(H["A" => "aye", "B" => "bee", "C" => "see"])
        expect { captured.put("E", "ee") }.to raise_error(FrozenError)
      end
    end

    context "after #persistent!" do
      let(:editor) { hash.transient }

      before { editor.persistent! }

      it "raises on any further write" do
        expect { editor.put("D", "dee") }.to raise_error(FrozenError)
        expect { editor.store("D", "dee") }.to raise_error(FrozenError)
        expect { editor["D"] = "dee" }.to raise_error(FrozenError)
        expect { editor.delete("A") }.to raise_error(FrozenError)
      end

      it "raises on any further read" do
        expect { editor.get("A") }.to raise_error(FrozenError)
        expect { editor.size }.to raise_error(FrozenError)
      end

      it "raises on a second persistent!" do
        expect { editor.persistent! }.to raise_error(FrozenError)
      end
    end

    context "thread confinement" do
      it "raises ThreadError when used from another thread" do
        editor = hash.transient
        error = Thread.new {
          begin
            editor.put("D", "dee")
            nil
          rescue ThreadError => e
            e
          end
        }.value
        expect(error).to be_a(ThreadError)
      end

      it "raises ThreadError when persisted from another thread" do
        editor = hash.transient
        error = Thread.new {
          begin
            editor.persistent!
            nil
          rescue ThreadError => e
            e
          end
        }.value
        expect(error).to be_a(ThreadError)
      end
    end

    context "with two editors on the same input" do
      it "lets the surviving editor keep working after the other is persisted" do
        first = hash.transient
        second = hash.transient
        first.put("one", 1)
        frozen_first = first.persistent!
        second.put("two", 2)
        100.times { |i| second.put(i, i) }
        frozen_second = second.persistent!

        expect(hash).to eql(H["A" => "aye", "B" => "bee", "C" => "see"])
        expect(frozen_first).to eql(hash.put("one", 1))
        expect(frozen_second["two"]).to eq(2)
        expect(frozen_second[42]).to eq(42)
        expect(frozen_second.key?("one")).to be(false)
        expect(frozen_first.key?("two")).to be(false)
      end
    end

    context "with a default block" do
      it "preserves the default block in the persisted hash" do
        with_default = Hamster::Hash.new(a: 1) { |key| key.to_s * 2 }
        result = with_default.transient { |e| e.put(:b, 2) }
        expect(result[:missing]).to eq("missingmissing")
        expect(result.default_proc).not_to be_nil
      end
    end
  end
end
