require "spec_helper"
require "hamster/vector"

describe Hamster::Vector do
  describe "#transient" do
    let(:vector) { V[* (1..1_000).to_a] }

    describe "snapshot isolation" do
      it "does not modify the original vector when items are appended" do
        vector.transient { |t| (1_001..2_000).each { |i| t.push(i) } }
        expect(vector.size).to eq(1_000)
        expect(vector.last).to eq(1_000)
      end

      it "does not modify the original vector when items are replaced" do
        vector.transient { |t| (0...1_000).each { |i| t.set(i, -i) } }
        expect(vector.first).to eq(1)
        expect(vector[500]).to eq(501)
        expect(vector.last).to eq(1_000)
      end

      it "does not modify the original vector when items are popped" do
        vector.transient { |t| 1_000.times { t.pop } }
        expect(vector.size).to eq(1_000)
        expect(vector.last).to eq(1_000)
      end

      it "leaves previously derived versions untouched" do
        derived = vector.add(2_000)
        vector.transient { |t| t.push(2_000).set(0, :changed) }
        expect(derived.size).to eq(1_001)
        expect(derived.last).to eq(2_000)
        expect(derived.first).to eq(1)
      end
    end

    describe "branch isolation" do
      it "seals accumulated updates into an immutable Vector" do
        result = vector.transient do |t|
          t.push(1_001).push(1_002)
          t.set(0, :first)
          t.pop
        end
        expect(result).to be_a(Hamster::Vector)
        expect(result.size).to eq(1_001)
        expect(result.first).to eq(:first)
        expect(result.last).to eq(1_001)
      end

      it "produces a vector equal to one built with persistent updates" do
        persistent = (1_001..2_000).reduce(vector) { |v, i| v.add(i) }
        transient = vector.transient { |t| (1_001..2_000).each { |i| t.push(i) } }
        expect(transient).to eql(persistent)
        expect(transient.to_a).to eq(persistent.to_a)
      end

      it "keeps the sealed vector independent of later persistent updates" do
        sealed = vector.transient { |t| t.push(:extra) }
        branched = sealed.put(0, :changed).pop
        expect(sealed.first).to eq(1)
        expect(sealed.last).to eq(:extra)
        expect(branched.first).to eq(:changed)
      end

      it "keeps the original independent of updates derived from the sealed vector" do
        sealed = vector.transient { |t| t.set(0, :changed) }
        sealed.add(:extra)
        expect(vector.first).to eq(1)
        expect(vector.size).to eq(1_000)
      end

      it "supports independent sequential editing sessions from one source" do
        first  = vector.transient { |t| t.push(:first) }
        second = vector.transient { |t| t.push(:second) }
        expect(first.last).to eq(:first)
        expect(second.last).to eq(:second)
        expect(vector.size).to eq(1_000)
      end

      it "collapses and regrows the tree correctly across level boundaries" do
        result = vector.transient do |t|
          1_000.times { t.pop }
          expect(t).to be_empty
          40.times { |i| t.push(i) }
        end
        expect(result.to_a).to eq((0..39).to_a)
        expect(vector.size).to eq(1_000)
      end
    end

    describe "boundary behaviour" do
      it "returns nil for out-of-range reads, like Vector#get" do
        V[1, 2, 3].transient do |t|
          expect(t.get(3)).to be_nil
          expect(t.get(-4)).to be_nil
          expect(t.get(-1)).to eq(3)
          expect(t[1]).to eq(2)
        end
        V[].transient do |t|
          expect(t.get(0)).to be_nil
          expect(t.first).to be_nil
          expect(t.last).to be_nil
        end
      end

      it "follows Vector#fetch rules" do
        V["A", "B"].transient do |t|
          expect(t.fetch(1)).to eq("B")
          expect(t.fetch(-1)).to eq("B")
          expect { t.fetch(2) }.to raise_error(IndexError)
          expect(t.fetch(2, "Z")).to eq("Z")
          expect(t.fetch(2) { |i| i * 10 }).to eq(20)
        end
      end

      it "raises IndexError when setting below -size" do
        V[1, 2, 3].transient do |t|
          expect { t.set(-4, :x) }.to raise_error(IndexError)
        end
      end

      it "appends when setting at exactly size" do
        result = V[1, 2].transient { |t| t.set(2, 3) }
        expect(result).to eql(V[1, 2, 3])
      end

      it "pads with nils when setting beyond size" do
        result = V[].transient { |t| t.set(2, 99) }
        expect(result).to eql(V[nil, nil, 99])
      end

      it "supports negative indices when setting" do
        result = V[1, 2, 3].transient { |t| t.set(-1, 99) }
        expect(result).to eql(V[1, 2, 99])
      end

      it "supports set with a block, receiving the current value" do
        result = V[1, 2, 3].transient { |t| t.set(1) { |v| v * 10 } }
        expect(result).to eql(V[1, 20, 3])
      end

      it "treats pop on an empty vector as a no-op" do
        result = V[].transient { |t| t.pop }
        expect(result).to eql(V[])
      end

      it "returns the stored item from #store and #[]=" do
        V[1].transient do |t|
          expect(t.store(0, :a)).to eq(:a)
          expect(t[0] = :b).to eq(:b)
        end
      end

      it "iterates from first to last with #each" do
        V[* (1..100).to_a].transient do |t|
          collected = []
          t.each { |i| collected << i }
          expect(collected).to eq((1..100).to_a)
        end
      end
    end

    describe "the editor" do
      it "is returned when no block is given" do
        editor = vector.transient
        expect(editor).to be_a(Hamster::TransientVector)
        editor.push(:a)
        expect(editor.persistent!.last).to eq(:a)
      end

      it "raises TransientError on any access after sealing" do
        editor = vector.transient
        editor.push(:a)
        editor.persistent!
        expect { editor.push(:b) }.to raise_error(Hamster::TransientError)
        expect { editor.set(0, :b) }.to raise_error(Hamster::TransientError)
        expect { editor.pop }.to raise_error(Hamster::TransientError)
        expect { editor.get(0) }.to raise_error(Hamster::TransientError)
        expect { editor.size }.to raise_error(Hamster::TransientError)
        expect { editor.each { |i| } }.to raise_error(Hamster::TransientError)
        expect { editor.persistent! }.to raise_error(Hamster::TransientError)
      end

      it "invalidates the editor when the block exits normally" do
        editor = nil
        vector.transient { |t| editor = t }
        expect { editor.push(:b) }.to raise_error(Hamster::TransientError)
      end

      it "invalidates the editor when the block raises, so a saved reference cannot keep writing" do
        editor = nil
        expect {
          vector.transient { |t| editor = t; t.push(:b); raise "boom" }
        }.to raise_error("boom")
        expect { editor.push(:c) }.to raise_error(Hamster::TransientError)
        expect { editor.get(0) }.to raise_error(Hamster::TransientError)
        expect(vector.size).to eq(1_000)
      end

      it "is confined to the thread which created it" do
        editor = vector.transient
        expect { Thread.new { editor.push(:a) }.value }
          .to raise_error(Hamster::TransientError)
        expect { Thread.new { editor.size }.value }
          .to raise_error(Hamster::TransientError)
        editor.push(:a)
        expect(editor.persistent!.last).to eq(:a)
      end
    end

    describe "node allocation" do
      def allocated_objects
        GC.start
        before = GC.stat[:total_allocated_objects]
        yield
        GC.stat[:total_allocated_objects] - before
      end

      it "allocates fewer objects than the same batch of persistent updates" do
        base = V[* (1..1_000).to_a]

        persistent = nil
        persistent_allocs = allocated_objects do
          persistent = 10_000.times.reduce(base) { |v, i| v.add(i) }
        end

        transient = nil
        transient_allocs = allocated_objects do
          transient = base.transient { |t| 10_000.times { |i| t.push(i) } }
        end

        expect(transient).to eql(persistent)
        expect(transient_allocs).to be < persistent_allocs
        expect(transient_allocs).to be < persistent_allocs / 4
      end
    end
  end
end

