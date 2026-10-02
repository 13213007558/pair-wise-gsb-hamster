require "spec_helper"
require "hamster/vector"

describe Hamster::Vector do
  describe "#transient" do
    let(:vector) { Hamster::Vector[1, 2, 3] }

    it "returns a TransientVector seeded with the same contents" do
      editor = vector.transient
      expect(editor).to be_a(Hamster::TransientVector)
      expect(editor.size).to eq(3)
      expect(editor[0]).to eq(1)
      expect(editor[-1]).to eq(3)
    end

    it "applies a batch of edits and persists them into an immutable Vector" do
      editor = vector.transient
      1000.times { |i| editor.push(i) }
      editor.put(0, :zero)
      result = editor.persistent!
      expect(result).to be_a(Hamster::Vector)
      expect(result.size).to eq(1003)
      expect(result[0]).to eq(:zero)
      expect(result[3]).to eq(0)
      expect(result[-1]).to eq(999)
    end

    it "produces the same result as equivalent persistent updates" do
      editor = vector.transient
      expected = vector
      500.times do |i|
        editor.push(i)
        expected = expected.add(i)
      end
      100.times do |i|
        editor.put(i * 2, :x)
        expected = expected.put(i * 2, :x)
      end
      expect(editor.persistent!).to eql(expected)
    end

    it "never modifies the original vector" do
      editor = vector.transient
      editor.put(0, :changed)
      100.times { |i| editor.push(i) }
      editor.pop
      expect(vector).to eql(Hamster::Vector[1, 2, 3])
    end

    it "supports put with negative indexes and nil padding" do
      editor = vector.transient
      editor.put(-1, :last)
      editor.put(5, :five)
      result = editor.persistent!
      expect(result).to eql(Hamster::Vector[1, 2, :last, nil, nil, :five])
    end

    it "raises IndexError for negative indexes out of bounds" do
      editor = vector.transient
      expect { editor.put(-4, :x) }.to raise_error(IndexError)
    end

    it "supports put with a block" do
      editor = vector.transient
      editor.put(0) { |current| current * 10 }
      expect(editor.persistent![0]).to eq(10)
    end

    it "supports []= and returns the stored item" do
      editor = vector.transient
      expect(editor[1] = :two).to eq(:two)
      expect(editor.persistent![1]).to eq(:two)
    end

    it "pops items, shrinking the tree across level boundaries" do
      editor = Hamster::Vector.new((0...100).to_a).transient
      expect(editor.pop).to eq(99)
      68.times { editor.pop }
      result = editor.persistent!
      expect(result).to eql(Hamster::Vector.new((0...31).to_a))
    end

    it "returns nil when popping an empty transient" do
      editor = Hamster::Vector.empty.transient
      expect(editor.pop).to be_nil
      expect(editor.persistent!).to eql(Hamster::Vector.empty)
    end

    it "empties and refills correctly" do
      editor = vector.transient
      3.times { editor.pop }
      expect(editor.size).to eq(0)
      editor.push(:a).push(:b)
      expect(editor.persistent!).to eql(Hamster::Vector[:a, :b])
    end

    context "with a block" do
      it "yields the editor and returns the persisted vector" do
        result = vector.transient do |editor|
          editor.push(4)
          editor.put(0, :zero)
        end
        expect(result).to eql(Hamster::Vector[:zero, 2, 3, 4])
      end

      it "kills the editor when the block raises, leaving the original unchanged" do
        captured = nil
        expect {
          vector.transient do |editor|
            captured = editor
            editor.push(4)
            raise "boom"
          end
        }.to raise_error("boom")
        expect(vector).to eql(Hamster::Vector[1, 2, 3])
        expect { captured.push(5) }.to raise_error(FrozenError)
      end
    end

    context "after #persistent!" do
      let(:editor) { vector.transient }

      before { editor.persistent! }

      it "raises on any further write" do
        expect { editor.push(4) }.to raise_error(FrozenError)
        expect { editor.put(0, :x) }.to raise_error(FrozenError)
        expect { editor[0] = :x }.to raise_error(FrozenError)
        expect { editor.pop }.to raise_error(FrozenError)
      end

      it "raises on any further read" do
        expect { editor.get(0) }.to raise_error(FrozenError)
        expect { editor.size }.to raise_error(FrozenError)
      end
    end

    context "thread confinement" do
      it "raises ThreadError when used from another thread" do
        editor = vector.transient
        error = Thread.new {
          begin
            editor.push(4)
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
        first = vector.transient
        second = vector.transient
        first.push(:one)
        frozen_first = first.persistent!
        second.push(:two)
        100.times { |i| second.push(i) }
        frozen_second = second.persistent!

        expect(vector).to eql(Hamster::Vector[1, 2, 3])
        expect(frozen_first).to eql(Hamster::Vector[1, 2, 3, :one])
        expect(frozen_second.size).to eq(104)
        expect(frozen_second[3]).to eq(:two)
        expect(frozen_second[-1]).to eq(99)
        expect(frozen_first.size).to eq(4)
      end
    end
  end
end
