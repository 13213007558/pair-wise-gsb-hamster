require "spec_helper"
require "hamster/measured_deque"

describe Hamster::MeasuredDeque do
  describe "structural invariants under random operations" do
    it "matches a plain Array for ends, concat, measure, and split" do
      srand(2024)
      array = %w[seed1 seed2]
      deque = Hamster::MeasuredDeque.new("", array) { |a, b| a + b }

      800.times do
        case rand(7)
        when 0..1
          value = rand(1_000_000).to_s(36)
          array.push(value)
          deque = deque.push(value)
        when 2..3
          value = rand(1_000_000).to_s(36)
          array.unshift(value)
          deque = deque.unshift(value)
        when 4
          array.pop
          deque = deque.pop
        when 5
          array.shift
          deque = deque.shift
        when 6
          other = Array.new(rand(0..12)) { rand(1_000_000).to_s(36) }
          array.concat(other)
          deque = deque.concat(
            Hamster::MeasuredDeque.new("", other) { |a, b| a + b })
        end

        expect(deque.to_a).to eq(array)
        expect(deque.size).to eq(array.size)
        expect(deque.first).to eq(array.first)
        expect(deque.last).to eq(array.last)
        expect(deque.measure).to eq(array.join)
      end
    end

    it "splits identically to a reference accumulation (string measure)" do
      srand(99)
      300.times do
        n = rand(0..600)
        items = Array.new(n) { "x" * rand(0..6) }
        deque = Hamster::MeasuredDeque.new("", items) { |a, b| a + b }
        total = items.map(&:bytesize).sum
        offset = rand(0..[total + 2, 1].max)

        before, item, after = deque.split { |measure| measure.bytesize > offset }

        reference_index = nil
        running = 0
        items.each_with_index do |chunk, index|
          if running + chunk.bytesize > offset && reference_index.nil?
            reference_index = index
          end
          running += chunk.bytesize
        end

        if reference_index.nil?
          expect(item).to be_nil
          expect(before.to_a).to eq(items)
          expect(after).to be_empty
        else
          expect(item).to eq(items[reference_index])
          expect(before.to_a).to eq(items[0...reference_index])
          expect(after.to_a).to eq(items[(reference_index + 1)..-1] || [])
          expect(before.measure).to eq(items[0...reference_index].join)
          expect(after.measure).to eq((items[(reference_index + 1)..-1] || []).join)
        end
      end
    end

    it "splits identically to a reference accumulation (integer measure)" do
      srand(7)
      200.times do
        n = rand(0..400)
        items = Array.new(n) { rand(0..9) }
        deque = Hamster::MeasuredDeque.new(0, items) { |a, b| a + b }
        total = items.sum
        threshold = rand(-1..total + 1)

        before, item, after = deque.split { |measure| measure > threshold }

        reference_index = nil
        running = 0
        items.each_with_index do |value, index|
          if running + value > threshold && reference_index.nil?
            reference_index = index
          end
          running += value
        end

        if reference_index.nil?
          expect(item).to be_nil
          expect(before.to_a).to eq(items)
          expect(after).to be_empty
        else
          expect(item).to eq(items[reference_index])
          expect(before.to_a).to eq(items[0...reference_index])
          expect(after.to_a).to eq(items[(reference_index + 1)..-1] || [])
        end
      end
    end
  end
end
