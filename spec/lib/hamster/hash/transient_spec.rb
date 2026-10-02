require "spec_helper"
require "hamster/hash"
require "hamster/transient"

describe Hamster::Hash do
  describe "#transient" do
    let(:hash) { H["A" => "aye", "B" => "bee", "C" => "see"] }

    context "snapshot and branch isolation" do
      it "leaves the original hash unchanged after the session is sealed" do
        result = hash.transient do |t|
          t.put("A", "altered")
          t.put("D", "dee")
          t.delete("B")
        end
        expect(hash).to eql(H["A" => "aye", "B" => "bee", "C" => "see"])
        expect(result).to eql(H["A" => "altered", "C" => "see", "D" => "dee"])
      end

      it "leaves the original unchanged even while the session is still open" do
        t = hash.transient
        100.times { |i| t.put(i, i) }
        t.delete("A")
        expect(hash).to eql(H["A" => "aye", "B" => "bee", "C" => "see"])
        t.persistent!
      end

      it "does not disturb branches derived from the original before the session" do
        branch = hash.put("B", "BRANCHED").delete("C")
        result = hash.transient do |t|
          t.put("B", "transient")
          t.delete("A")
          200.times { |i| t.put(i, i) }
        end
        expect(branch).to eql(H["A" => "aye", "B" => "BRANCHED"])
        expect(hash).to eql(H["A" => "aye", "B" => "bee", "C" => "see"])
        expect(result.get("B")).to eq("transient")
        expect(result.key?("A")).to be(false)
      end

      it "isolates shared subtries when keys collide in the same hash bucket" do
        keys = (0...100).map { |i| DeterministicHash.new(i, i % 4) }
        original = H.new(keys.map { |k| [k, k.value] })
        branch = original.put(keys[0], :branch)
        result = original.transient do |t|
          keys.each { |k| t.put(k, k.value * 10) }
          t.delete(keys[1])
          t.put(DeterministicHash.new(1000, 0), :new)
        end
        expect(original.get(keys[1])).to eq(1)
        expect(original.size).to eq(100)
        expect(branch.get(keys[0])).to eq(:branch)
        expect(branch.get(keys[2])).to eq(2)
        expect(result.get(keys[2])).to eq(20)
        expect(result.key?(keys[1])).to be(false)
        expect(result.get(DeterministicHash.new(1000, 0))).to eq(:new)
      end

      it "keeps earlier sealed results unchanged when the same original is edited again" do
        first = hash.transient { |t| t.put("A", "first") }
        second = hash.transient { |t| t.put("A", "second") }
        expect(first.get("A")).to eq("first")
        expect(second.get("A")).to eq("second")
        expect(hash.get("A")).to eq("aye")
      end
    end

    context "node allocation" do
      def count_trie_allocations
        count = 0
        allow(Hamster::Trie).to receive(:new).and_wrap_original do |original, *args|
          count += 1
          original.call(*args)
        end
        yield
        count
      end

      let(:pairs) { (0...1000).map { |i| ["key#{i}", i] } }
      let(:big_hash) { H.new(pairs) }

      it "allocates far fewer trie nodes than repeated persistent puts for the same batch" do
        updates = (0...1000).map { |i| ["key#{i}", i * 2] } + (0...500).map { |i| ["new#{i}", i] }

        persistent_count = count_trie_allocations do
          h = big_hash
          updates.each { |k, v| h = h.put(k, v) }
          expect(h.size).to eq(1500)
        end

        transient_count = count_trie_allocations do
          result = big_hash.transient do |t|
            updates.each { |k, v| t.put(k, v) }
          end
          expect(result.size).to eq(1500)
        end

        expect(transient_count).to be < persistent_count / 2
      end
    end

    context "key and hash contract" do
      it "duplicates and freezes unfrozen string keys" do
        key = "mutable"
        result = H[].transient { |t| t.put(key, 1) }
        key << "-altered"
        expect(result.get("mutable")).to eq(1)
        expect(result.keys.first).to be_frozen
        expect(result.keys.first).to_not equal(key)
      end

      it "uses #hash and #eql? to identify keys, like the persistent hash" do
        result = H[].transient do |t|
          t.put(DeterministicHash.new(:a, 1), 1)
          t.put(DeterministicHash.new(:a, 1), 2)
          t.put(DeterministicHash.new(:b, 1), 3)
        end
        expect(result.size).to eq(2)
        expect(result.get(DeterministicHash.new(:a, 1))).to eq(2)
      end

      it "preserves the default proc in the sealed hash" do
        with_default = H.new { |key| key * 2 }
        result = with_default.transient { |t| t.put(1, 1) }
        expect(result.default_proc).to eq(with_default.default_proc)
        expect(result.get(5)).to eq(10)
        expect(result.get(1)).to eq(1)
      end

      it "supports the block form of #put with the previously stored value" do
        result = hash.transient { |t| t.put("A") { |v| v.upcase } }
        expect(result.get("A")).to eq("AYE")
      end

      it "returns the stored value from #store and #[]=" do
        t = H[].transient
        expect(t.store(:a, 1)).to eq(1)
        expect(t[:b] = 2).to eq(2)
        result = t.persistent!
        expect(result).to eql(H[a: 1, b: 2])
      end

      it "returns the old value from #delete" do
        t = hash.transient
        expect(t.delete("A")).to eq("aye")
        expect(t.delete("missing")).to be_nil
        expect(t.persistent!).to eql(H["B" => "bee", "C" => "see"])
      end

      it "can delete every key, sealing to the canonical empty hash" do
        result = hash.transient do |t|
          %w[A B C].each { |k| t.delete(k) }
        end
        expect(result.size).to eq(0)
        expect(result).to equal(H.empty)
      end

      it "matches a RubyHash oracle across a long mixed session" do
        oracle = {}
        keys = (0...200).map { |i| "k#{i}" }
        editor = H[].transient
        srand(42)
        3000.times do
          key = keys.sample
          if rand < 0.6
            value = rand(1000)
            oracle[key] = value
            editor.put(key, value)
          else
            oracle.delete(key)
            editor.delete(key)
          end
        end
        result = editor.persistent!
        expect(result.size).to eq(oracle.size)
        oracle.each { |k, v| expect(result.get(k)).to eq(v) }
      end
    end

    context "session safety" do
      it "raises on any use after #persistent!" do
        t = hash.transient
        t.put("X", "ex")
        t.persistent!
        expect { t.put("Y", "why") }.to raise_error(RuntimeError, /editing session ended/)
        expect { t.get("A") }.to raise_error(RuntimeError, /editing session ended/)
        expect { t.delete("A") }.to raise_error(RuntimeError, /editing session ended/)
        expect { t.size }.to raise_error(RuntimeError, /editing session ended/)
        expect { t.persistent! }.to raise_error(RuntimeError, /editing session ended/)
      end

      it "raises when used from a thread other than the creating one" do
        t = hash.transient
        error = Thread.new {
          begin
            t.put("X", "ex")
            nil
          rescue RuntimeError => e
            e
          end
        }.value
        expect(error).to be_a(RuntimeError)
        expect(error.message).to match(/thread/)
        t.put("X", "still fine on the creating thread")
        expect(t.persistent!.get("X")).to eq("still fine on the creating thread")
      end

      it "invalidates the editor when the block raises, so a retained alias cannot keep writing" do
        retained = nil
        expect {
          hash.transient do |t|
            retained = t
            t.put("X", "ex")
            raise "boom"
          end
        }.to raise_error("boom")
        expect { retained.put("Y", "why") }.to raise_error(RuntimeError, /editing session ended/)
        expect { retained.persistent! }.to raise_error(RuntimeError, /editing session ended/)
        expect(hash).to eql(H["A" => "aye", "B" => "bee", "C" => "see"])
      end

      it "returns the sealed hash from the block form" do
        result = hash.transient { |t| t.put("D", "dee") }
        expect(result).to be_a(Hamster::Hash)
        expect(result).to eql(hash.put("D", "dee"))
      end
    end
  end
end
