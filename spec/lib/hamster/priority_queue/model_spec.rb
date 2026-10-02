require "spec_helper"
require "hamster/priority_queue"

describe Hamster::PriorityQueue do
  # A tiny, obviously-correct persistent model. Entries live in a plain
  # frozen Hash of {id => [priority, value]}; ordering is a plain sort by
  # [priority, id]. Used to cross-check the real implementation on random
  # sequences of mixed operations, including branching and melding.
  class ModelPriorityQueue
    attr_reader :entries

    def initialize(entries = {})
      @entries = entries.freeze
    end

    def insert(id, value, priority)
      self.class.new(@entries.merge(id => [priority, value]))
    end

    def min_id
      entry = @entries.min_by { |id, (priority, _value)| [priority, id] }
      entry && entry[0]
    end

    def min
      id = min_id
      id && @entries[id][1]
    end

    def pop
      id = min_id
      id ? delete(id) : self
    end

    def decrease(id, new_priority)
      self.class.new(@entries.merge(id => [new_priority, @entries[id][1]]))
    end

    def delete(id)
      self.class.new(@entries.reject { |key, _| key == id })
    end

    def meld(other, &resolver)
      merged = @entries.dup
      other.entries.each do |id, (priority, value)|
        if merged.key?(id)
          own = merged[id][0]
          merged[id] = [own == priority ? own : resolver.call(own, priority), value]
        else
          merged[id] = [priority, value]
        end
      end
      self.class.new(merged)
    end

    def order
      @entries.sort_by { |id, (priority, _value)| [priority, id] }
              .map { |_id, (_priority, value)| value }
    end

    def size
      @entries.size
    end
  end

  describe "mixed operations against a reference model" do
    [20261001, 42].each do |seed|
      context "with seed #{seed}" do
        it "behaves identically to the model" do
          rng = Random.new(seed)
          versions = [[PQ.new, ModelPriorityQueue.new]]
          handles = {} # model id => real Handle
          next_id = 0

          300.times do
            real, model = versions[rng.rand(versions.size)]
            case rng.rand(10)
            when 0..3 # insert
              value = "item-#{next_id}"
              priority = rng.rand(4) # small range to force many ties
              real, handle = real.insert(value, priority)
              handles[next_id] = handle
              model = model.insert(next_id, value, priority)
              next_id += 1
            when 4..5 # pop
              real = real.pop
              model = model.pop
            when 6 # decrease_priority
              live = model.entries.keys
              unless live.empty?
                id = live[rng.rand(live.size)]
                new_priority = model.entries[id][0] - 1 - rng.rand(3)
                real = real.decrease_priority(handles[id], new_priority)
                model = model.decrease(id, new_priority)
              end
            when 7 # delete
              live = model.entries.keys
              unless live.empty?
                id = live[rng.rand(live.size)]
                real = real.delete(handles[id])
                model = model.delete(id)
              end
            when 8 # meld two (possibly related) versions
              other_real, other_model = versions[rng.rand(versions.size)]
              real = real.meld(other_real) { |_handle, a, b| [a, b].min }
              model = model.meld(other_model) { |a, b| [a, b].min }
            else # branch again from an existing version (persistence)
              # deriving below already leaves every old version untouched
            end

            expect(real.size).to eq(model.size)
            expect(real.min).to eq(model.min)
            expect(real.to_a).to eq(model.order)
            versions << [real, model]
          end

          # every version ever created must still drain in the right order:
          # old queues keep working on their own branch
          versions.each do |real, model|
            drained = []
            until real.empty?
              drained << real.min
              real = real.pop
            end
            expect(drained).to eq(model.order)
          end
        end
      end
    end
  end
end
