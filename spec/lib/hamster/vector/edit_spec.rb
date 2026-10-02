require "spec_helper"

describe Hamster::Vector do
  describe "#edit" do
    let(:vector) { described_class[*(1..100).to_a] }

    it "applies many writes and returns an ordinary immutable vector" do
      result = vector.edit do |editor|
        10_000.times { |index| editor.push(101 + index) }
        editor[0] = 0
        editor.delete_at(1)
      end

      expected = [0] + (3..100).to_a + (101..10_100).to_a
      expect(result).to be_a(described_class)
      expect(result).to be_frozen
      expect(result.size).to eq(10_099)
      expect(result.to_a).to eq(expected)
    end

    it "does not modify the original vector" do
      result = vector.edit do |editor|
        editor[0] = 0
        editor.push(101)
      end

      expect(vector.to_a).to eq((1..100).to_a)
      expect(result.to_a.first(3)).to eq([0, 2, 3])
      expect(result.last).to eq(101)
    end

    it "supports structural operations after a transient update" do
      result = vector.edit do |editor|
        editor[0] = 0
        editor.push(101)
        editor.unshift(-1)
        editor.insert(2, :x)
        editor.delete_at(5)
        editor.pop
      end

      expect(result.to_a.first(6)).to eq([-1, 0, :x, 2, 3, 5])
      expect(result.last).to eq(100)
    end

    it "supports clearing and concat during a session" do
      result = vector.edit do |editor|
        editor.clear
        editor.concat([1, 2])
        editor.fill(0, 0, 1)
      end

      expect(result.to_a).to eq([0, 2])
    end

    it "rejects writes after closing" do
      editor = vector.edit
      editor.freeze

      expect { editor.push(101) }.to raise_error(Hamster::Editor::ClosedError)
      expect { editor[0] = 0 }.to raise_error(Hamster::Editor::ClosedError)
      expect { editor.delete_at(0) }.to raise_error(Hamster::Editor::ClosedError)
      expect { editor.clear }.to raise_error(Hamster::Editor::ClosedError)
    end

    it "makes freeze idempotent and returns the same immutable result" do
      editor = vector.edit
      editor.push(101)

      expect(editor.freeze).to equal(editor.freeze)
    end

    it "rejects use from another thread" do
      editor = vector.edit
      error = Thread.new { begin; editor.push(101); rescue => e; e; end }.value

      expect(error).to be_a(ThreadError)
      expect(vector.size).to eq(100)
    end

    it "leaves the old root unchanged when the block raises" do
      expect do
        vector.edit do |editor|
          editor.push(101)
          raise "abort"
        end
      end.to raise_error("abort")

      expect(vector.to_a).to eq((1..100).to_a)
    end

    it "keeps two editors and their frozen results independent" do
      left = vector.edit
      right = vector.edit

      left.push(101)
      first = left.freeze
      right[0] = 0
      second = right.freeze
      third = vector.edit.freeze

      expect(first.last).to eq(101)
      expect(second[0]).to eq(0)
      expect(second.size).to eq(100)
      expect(third.to_a).to eq((1..100).to_a)
      expect(vector.to_a).to eq((1..100).to_a)
    end

    it "freezes all internal arrays after closing" do
      result = vector.edit { |editor| 2_000.times { |index| editor.push(index) } }
      root = result.instance_variable_get(:@root)
      levels = result.instance_variable_get(:@levels)

      freeze_nodes = lambda do |node, level|
        expect(node).to be_frozen
        next if level == 0
        node.each { |child| freeze_nodes.call(child, level - 1) }
      end
      freeze_nodes.call(root, levels)
    end
  end
end
