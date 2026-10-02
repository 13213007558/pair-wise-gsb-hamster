require "spec_helper"
require "hamster/vector"
require "hamster/transient"

describe Hamster::Vector do
  describe "#transient" do
    let(:vector) { V[1, 2, 3, 4, 5] }

    context "snapshot and branch isolation" do
      it "leaves the original vector unchanged after the session is sealed" do
        result = vector.transient do |t|
          t.put(0, 99)
          t.add(6)
        end
        expect(vector).to eql(V[1, 2, 3, 4, 5])
        expect(result).to eql(V[99, 2, 3, 4, 5, 6])
      end

      it "leaves the original unchanged even while the session is still open" do
        t = vector.transient
        100.times { |i| t.add(i) }
        t.put(0, 99)
        expect(vector).to eql(V[1, 2, 3, 4, 5])
        t.persistent!
      end

      it "does not disturb branches derived from the original before the session" do
        branch = vector.put(0, :branch).add(:extra)
        result = vector.transient do |t|
          t.put(0, :transient)
          200.times { |i| t.add(i) }
        end
        expect(branch).to eql(V[:branch, 2, 3, 4, 5, :extra])
        expect(vector).to eql(V[1, 2, 3, 4, 5])
        expect(result[0]).to eq(:transient)
        expect(result.size).to eq(205)
      end

      it "isolates shared nodes deep in a large vector" do
        big = V.new((0...2000).to_a)
        branch = big.put(1000, :branch)
        result = big.transient do |t|
          2000.times { |i| t.put(i, i * 2) }
          500.times { |i| t.add(i) }
        end
        expect(big.size).to eq(2000)
        expect(big[1000]).to eq(1000)
        expect(big[1999]).to eq(1999)
        expect(branch[1000]).to eq(:branch)
        expect(branch[0]).to eq(0)
        expect(result.size).to eq(2500)
        expect(result[1000]).to eq(2000)
        expect(result[2499]).to eq(499)
      end

      it "keeps earlier sealed results unchanged when the same original is edited again" do
        first = vector.transient { |t| t.put(0, :first) }
        second = vector.transient { |t| t.put(0, :second) }
        expect(first[0]).to eq(:first)
        expect(second[0]).to eq(:second)
        expect(vector[0]).to eq(1)
      end
    end

    context "node allocation" do
      def count_allocated_objects
        GC.start
        before = GC.stat[:total_allocated_objects]
        yield
        GC.stat[:total_allocated_objects] - before
      end

      it "allocates far fewer objects than repeated persistent puts for the same batch" do
        big = V.new((0...2000).to_a)

        persistent_count = count_allocated_objects do
          v = big
          2000.times { |i| v = v.put(i, i * 2) }
          expect(v[1000]).to eq(2000)
        end

        transient_count = count_allocated_objects do
          result = big.transient do |t|
            2000.times { |i| t.put(i, i * 2) }
          end
          expect(result[1000]).to eq(2000)
        end

        expect(transient_count).to be < persistent_count / 2
      end

      it "allocates far fewer objects than repeated persistent adds for the same batch" do
        persistent_count = count_allocated_objects do
          v = V.empty
          1000.times { |i| v = v.add(i) }
          expect(v.size).to eq(1000)
        end

        transient_count = count_allocated_objects do
          result = V.empty.transient do |t|
            1000.times { |i| t.add(i) }
          end
          expect(result.size).to eq(1000)
        end

        expect(transient_count).to be < persistent_count / 2
      end
    end

    context "boundary behavior" do
      it "supports negative indices like the persistent vector" do
        expect(vector.transient { |t| t.put(-1, 99) }).to eql(V[1, 2, 3, 4, 99])
        expect(vector.transient { |t| t.put(-5, 99) }).to eql(V[99, 2, 3, 4, 5])
      end

      it "raises IndexError when the index is below -size" do
        expect { vector.transient { |t| t.put(-6, 99) } }
          .to raise_error(IndexError, /index -6 outside of vector bounds/)
        expect { V.empty.transient { |t| t.put(-1, 99) } }.to raise_error(IndexError)
      end

      it "appends when the index equals the size" do
        expect(vector.transient { |t| t.put(5, 6) }).to eql(V[1, 2, 3, 4, 5, 6])
      end

      it "pads with nils when the index is beyond the end" do
        expect(vector.transient { |t| t.put(7, 99) })
          .to eql(V[1, 2, 3, 4, 5, nil, nil, 99])
        expect(V.empty.transient { |t| t.put(2, 99) }).to eql(V[nil, nil, 99])
      end

      it "pads across tree boundaries for far-future indices" do
        result = V[1].transient { |t| t.put(100, :end) }
        expect(result.size).to eq(101)
        expect(result[0]).to eq(1)
        expect(result[1]).to be_nil
        expect(result[99]).to be_nil
        expect(result[100]).to eq(:end)
      end

      it "supports the block form of #put with the existing value" do
        expect(vector.transient { |t| t.put(2) { |v| v * 10 } }).to eql(V[1, 2, 30, 4, 5])
      end

      it "reads back with #get, #[] and #fetch during the session" do
        t = vector.transient
        t.put(0, 99)
        expect(t.get(0)).to eq(99)
        expect(t[-1]).to eq(5)
        expect(t.get(100)).to be_nil
        expect(t.fetch(0)).to eq(99)
        expect(t.fetch(100, :default)).to eq(:default)
        expect(t.fetch(100) { |i| i * 2 }).to eq(200)
        expect { t.fetch(100) }.to raise_error(IndexError)
        expect(t.size).to eq(5)
        t.persistent!
      end

      it "grows the tree correctly across level boundaries" do
        result = V.empty.transient do |t|
          10_000.times { |i| t.add(i) }
        end
        expect(result.size).to eq(10_000)
        expect(result).to eql(V.new((0...10_000).to_a))
      end

      it "matches an Array oracle across a long mixed session" do
        oracle = (0...500).to_a
        editor = V.new(oracle).transient
        srand(7)
        2000.times do
          case rand(3)
          when 0
            value = rand(1000)
            oracle << value
            editor.add(value)
          when 1
            index = rand(oracle.size + 3)
            value = rand(1000)
            if index >= oracle.size
              (oracle.size...index).each { oracle << nil }
              oracle << value
            else
              oracle[index] = value
            end
            editor.put(index, value)
          when 2
            index = -rand(oracle.size) - 1
            value = rand(1000)
            oracle[index] = value
            editor.put(index, value)
          end
        end
        expect(editor.persistent!.to_a).to eq(oracle)
      end
    end

    context "session safety" do
      it "raises on any use after #persistent!" do
        t = vector.transient
        t.add(6)
        t.persistent!
        expect { t.add(7) }.to raise_error(RuntimeError, /editing session ended/)
        expect { t.put(0, 1) }.to raise_error(RuntimeError, /editing session ended/)
        expect { t.get(0) }.to raise_error(RuntimeError, /editing session ended/)
        expect { t.size }.to raise_error(RuntimeError, /editing session ended/)
        expect { t.persistent! }.to raise_error(RuntimeError, /editing session ended/)
      end

      it "raises when used from a thread other than the creating one" do
        t = vector.transient
        error = Thread.new {
          begin
            t.add(6)
            nil
          rescue RuntimeError => e
            e
          end
        }.value
        expect(error).to be_a(RuntimeError)
        expect(error.message).to match(/thread/)
        t.add(6)
        expect(t.persistent!).to eql(V[1, 2, 3, 4, 5, 6])
      end

      it "invalidates the editor when the block raises, so a retained alias cannot keep writing" do
        retained = nil
        expect {
          vector.transient do |t|
            retained = t
            t.add(6)
            raise "boom"
          end
        }.to raise_error("boom")
        expect { retained.add(7) }.to raise_error(RuntimeError, /editing session ended/)
        expect { retained.persistent! }.to raise_error(RuntimeError, /editing session ended/)
        expect(vector).to eql(V[1, 2, 3, 4, 5])
      end

      it "returns the sealed vector from the block form" do
        result = vector.transient { |t| t.add(6) }
        expect(result).to be_a(Hamster::Vector)
        expect(result).to eql(vector.add(6))
      end

      it "seals nodes so the result keeps the frozen-node invariant" do
        result = vector.transient do |t|
          100.times { |i| t.add(i) }
          t.put(0, 99)
        end
        root = result.instance_variable_get(:@root)
        expect(root).to be_frozen
        expect(result.put(0, 1)).to eql(vector.put(0, 1).concat((0...100).to_a))
      end
    end
  end
end
