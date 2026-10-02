require "spec_helper"
require "hamster/measured_deque"

describe Hamster::MeasuredDeque do
  describe "immutability" do
    let(:deque) do
      items = (1..120).to_a
      items.inject(Hamster::MeasuredDeque.empty(0) { |a, b| a + b }) do |d, i|
        i.even? ? d.unshift(i) : d.push(i)
      end
    end

    it "is frozen and reports immutable" do
      expect(deque).to be_frozen
      expect(deque).to be_immutable
    end

    it "freezes every derived deque" do
      expect(deque.push(0)).to be_frozen
      expect(deque.unshift(0)).to be_frozen
      expect(deque.pop).to be_frozen
      expect(deque.shift).to be_frozen
      expect(deque.clear).to be_frozen
      expect(deque.select(&:odd?)).to be_frozen
      expect(deque.map(&:succ)).to be_frozen
      other = Hamster::MeasuredDeque.new(0, [1, 2]) { |a, b| a + b }
      expect(deque.concat(other)).to be_frozen
      before, _item, after = deque.split { |measure| measure > 100 }
      expect(before).to be_frozen
      expect(after).to be_frozen
    end

    it "cannot have its internal state mutated" do
      expect { deque.instance_variable_set(:@root, nil) }
        .to raise_error(FrozenError)
    end

    it "returns self from dup and clone" do
      expect(deque.dup).to equal(deque)
      expect(deque.clone).to equal(deque)
    end
  end
end
