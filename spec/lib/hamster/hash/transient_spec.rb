require "spec_helper"
require "hamster/hash"

describe Hamster::Hash do
  describe "#transient" do
    let(:pairs) { (1..100).map { |i| ["key#{i}", i] } }
    let(:hash) { H[pairs] }

    describe "snapshot isolation" do
      it "does not modify the original hash when entries are added" do
        hash.transient { |t| (101..200).each { |i| t.put("key#{i}", i) } }
        expect(hash.size).to eq(100)
        expect(hash).to eql(H[pairs])
      end

      it "does not modify the original hash when entries are replaced" do
        hash.transient { |t| (1..100).each { |i| t.put("key#{i}", -i) } }
        expect(hash).to eql(H[pairs])
      end

      it "does not modify the original hash when entries are deleted" do
        hash.transient { |t| (1..100).each { |i| t.delete("key#{i}") } }
        expect(hash.size).to eq(100)
        expect(hash).to eql(H[pairs])
      end

      it "leaves previously derived versions untouched" do
        derived = hash.put("extra", 0)
        hash.transient { |t| t.put("extra", 999).delete("key1") }
        expect(derived["extra"]).to eq(0)
        expect(derived["key1"]).to eq(1)
      end
    end

    describe "branch isolation" do
      it "seals accumulated updates into an immutable Hash" do
        result = hash.transient do |t|
          (1..100).each { |i| t.put("key#{i}", -i) }
          (101..200).each { |i| t.put("key#{i}", i) }
          t.delete("key1")
        end
        expect(result).to be_a(Hamster::Hash)
        expect(result.size).to eq(199)
        expect(result["key2"]).to eq(-2)
        expect(result["key200"]).to eq(200)
        expect(result.key?("key1")).to be(false)
      end

      it "produces a hash equal to one built with persistent updates" do
        persistent = (101..200).reduce(hash) { |h, i| h.put("key#{i}", i) }
        transient = hash.transient { |t| (101..200).each { |i| t.put("key#{i}", i) } }
        expect(transient).to eql(persistent)
        expect(transient.hash).to eq(persistent.hash)
      end

      it "keeps the sealed hash independent of later persistent updates" do
        sealed = hash.transient { |t| t.put("a", 1) }
        branched = sealed.put("a", 2).delete("key1")
        expect(sealed["a"]).to eq(1)
        expect(sealed["key1"]).to eq(1)
        expect(branched["a"]).to eq(2)
      end

      it "keeps the original independent of updates derived from the sealed hash" do
        sealed = hash.transient { |t| t.put("a", 1) }
        sealed.put("key1", 1000)
        expect(hash["key1"]).to eq(1)
        expect(hash.key?("a")).to be(false)
      end

      it "supports independent sequential editing sessions from one source" do
        first  = hash.transient { |t| t.put("session", "first") }
        second = hash.transient { |t| t.put("session", "second") }
        expect(first["session"]).to eq("first")
        expect(second["session"]).to eq("second")
        expect(hash.key?("session")).to be(false)
      end

      it "supports deleting every entry" do
        result = hash.transient { |t| (1..100).each { |i| t.delete("key#{i}") } }
        expect(result).to be_empty
        expect(result.size).to eq(0)
      end
    end

    describe "the editor" do
      it "is returned when no block is given" do
        editor = hash.transient
        expect(editor).to be_a(Hamster::TransientHash)
        editor.put("a", 1)
        expect(editor.persistent!["a"]).to eq(1)
      end

      it "raises TransientError on any access after sealing" do
        editor = hash.transient
        editor.put("a", 1)
        editor.persistent!
        expect { editor.put("b", 2) }.to raise_error(Hamster::TransientError)
        expect { editor.delete("a") }.to raise_error(Hamster::TransientError)
        expect { editor.get("a") }.to raise_error(Hamster::TransientError)
        expect { editor.size }.to raise_error(Hamster::TransientError)
        expect { editor.each { |pair| } }.to raise_error(Hamster::TransientError)
        expect { editor.persistent! }.to raise_error(Hamster::TransientError)
      end

      it "invalidates the editor when the block exits normally" do
        editor = nil
        hash.transient { |t| editor = t }
        expect { editor.put("b", 2) }.to raise_error(Hamster::TransientError)
      end

      it "invalidates the editor when the block raises, so a saved reference cannot keep writing" do
        editor = nil
        expect {
          hash.transient { |t| editor = t; t.put("b", 2); raise "boom" }
        }.to raise_error("boom")
        expect { editor.put("c", 3) }.to raise_error(Hamster::TransientError)
        expect { editor.get("b") }.to raise_error(Hamster::TransientError)
        expect(hash.key?("b")).to be(false)
      end

      it "is confined to the thread which created it" do
        editor = hash.transient
        expect { Thread.new { editor.put("a", 1) }.value }
          .to raise_error(Hamster::TransientError)
        expect { Thread.new { editor.size }.value }
          .to raise_error(Hamster::TransientError)
        editor.put("a", 1)
        expect(editor.persistent!["a"]).to eq(1)
      end
    end

    describe "key and hash contract" do
      it "duplicates and freezes string keys" do
        key = "mutable"
        result = H[].transient { |t| t.put(key, 1) }
        key << "!"
        expect(result["mutable"]).to eq(1)
        expect(result.keys.first).to be_frozen
      end

      it "treats eql? keys with equal hashes as identical" do
        result = H[].transient { |t| t.put(1, "integer").put(1.0, "float") }
        expect(result.size).to eq(2)
        expect(result[1]).to eq("integer")
        expect(result[1.0]).to eq("float")
      end

      it "preserves the default block" do
        source = H.new { |key| key * 2 }
        editor = source.transient
        editor.put(1, 1)
        expect(editor.get(100)).to eq(200)
        result = editor.persistent!
        expect(result[100]).to eq(200)
        expect(result.default_proc).not_to be_nil
      end

      it "supports put with a block, receiving the current value" do
        result = hash.transient { |t| t.put("key1") { |v| v + 100 } }
        expect(result["key1"]).to eq(101)
      end

      it "returns the stored value from #store and #[]=" do
        hash.transient do |t|
          expect(t.store("a", 1)).to eq(1)
          expect(t["b"] = 2).to eq(2)
        end
      end

      it "returns the removed value from #delete and nil for missing keys" do
        hash.transient do |t|
          expect(t.delete("key1")).to eq(1)
          expect(t.delete("key1")).to be_nil
          expect(t.delete("missing")).to be_nil
        end
      end

      it "raises KeyError from #fetch for missing keys" do
        hash.transient do |t|
          expect(t.fetch("key1")).to eq(1)
          expect { t.fetch("missing") }.to raise_error(KeyError)
          expect(t.fetch("missing", 42)).to eq(42)
          expect(t.fetch("missing") { |k| k }).to eq("missing")
        end
      end

      it "preserves the class of subclasses" do
        subclass = Class.new(Hamster::Hash)
        result = subclass[a: 1].transient { |t| t.put(:b, 2) }
        expect(result).to be_a(subclass)
        expect(result[:b]).to eq(2)
      end
    end

    describe "node allocation" do
      it "allocates fewer trie nodes than the same batch of persistent updates" do
        counts = { trie: 0 }
        counter = Module.new do
          define_method(:new) do |*args, &block|
            counts[:trie] += 1
            super(*args, &block)
          end
        end
        Hamster::Trie.singleton_class.prepend(counter)

        base = H[(1..5_000).map { |i| ["key#{i}", i] }]
        keys = (1..10_000).map { |i| "key#{i}" }

        counts[:trie] = 0
        persistent = keys.reduce(base) { |h, k| h.put(k, 1) }
        persistent_nodes = counts[:trie]

        counts[:trie] = 0
        transient = base.transient { |t| keys.each { |k| t.put(k, 1) } }
        transient_nodes = counts[:trie]

        expect(transient).to eql(persistent)
        expect(transient_nodes).to be > 0
        expect(transient_nodes).to be < persistent_nodes
        expect(transient_nodes).to be < persistent_nodes / 2
      end
    end
  end
end

