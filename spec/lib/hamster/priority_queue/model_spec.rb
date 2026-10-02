require "spec_helper"

# A small, obviously-correct reference model of the documented priority
# queue semantics, built on plain Ruby hashes and linear scans. The
# randomized cross-check below drives the real persistent queue and this
# model through identical mixed operation sequences -- including branching
# off old versions, which exercises persistence -- and requires them to
# agree on size, peek, pop order, and the stable order of equal priorities.
class PriorityQueueReferenceModel
  Entry = Struct.new(:priority, :value, :version, :seq)

  attr_reader :entries, :tombstones

  # Insertion sequence numbers are global (like the real queue's handle
  # ids), so that ties between equal priorities always break the same way.
  @next_seq = 0

  def self.next_seq
    @next_seq += 1
  end

  def initialize(entries = {}, tombstones = {})
    @entries = entries        # handle => Entry
    @tombstones = tombstones  # handle => true
  end

  def size
    @entries.size
  end

  def empty?
    @entries.empty?
  end

  def insert(handle, priority, value)
    entry = Entry.new(priority, value, 0, PriorityQueueReferenceModel.next_seq)
    self.class.new(@entries.merge(handle => entry), @tombstones)
  end

  def decrease_priority(handle, priority)
    old = @entries.fetch(handle)
    return self if old.priority == priority
    entry = Entry.new(priority, old.value, old.version + 1, old.seq)
    self.class.new(@entries.merge(handle => entry), @tombstones)
  end

  def delete(handle)
    entries = @entries.dup
    entries.delete(handle)
    self.class.new(entries, @tombstones.merge(handle => true))
  end

  def peek
    pair = @entries.min_by { |handle, entry| [entry.priority, entry.seq] }
    pair && [pair[1].priority, pair[1].value]
  end

  def pop
    pair = @entries.min_by { |handle, entry| [entry.priority, entry.seq] }
    return nil if pair.nil?
    [pair[1].priority, pair[1].value, delete(pair[0])]
  end

  def meld(other)
    entries = {}
    (@entries.keys | other.entries.keys).each do |handle|
      next if @tombstones[handle] || other.tombstones[handle]
      mine = @entries[handle]
      theirs = other.entries[handle]
      if mine && theirs
        if mine.version > theirs.version
          entries[handle] = mine
        elsif theirs.version > mine.version
          entries[handle] = theirs
        elsif mine.priority == theirs.priority
          entries[handle] = mine
        else
          priority = yield(handle, mine.priority, theirs.priority)
          entries[handle] = Entry.new(priority, mine.value, mine.version + 1, mine.seq)
        end
      else
        entries[handle] = mine || theirs
      end
    end
    self.class.new(entries, @tombstones.merge(other.tombstones))
  end
end

describe Hamster::PriorityQueue do
  describe "reference model cross-check" do
    def drain(queue)
      items = []
      until queue.empty?
        priority, value, queue = queue.pop
        items << [priority, value]
      end
      items
    end

    def drain_model(model)
      items = []
      until model.empty?
        priority, value, model = model.pop
        items << [priority, value]
      end
      items
    end

    it "matches the model across mixed operations on branching versions" do
      [20261003, 7, 424242].each do |seed|
        rng = Random.new(seed)
        branches = [[PQ.new, PriorityQueueReferenceModel.new]]
        value_counter = 0

        300.times do
          queue, model = branches[rng.rand(branches.size)]

          case rng.rand(7)
          when 0, 1, 2 # insert
            priority = rng.rand(5) # small range forces many priority ties
            value = "value-#{value_counter}"
            value_counter += 1
            new_queue, handle = queue.insert(priority, value)
            branches << [new_queue, model.insert(handle, priority, value)]
          when 3 # pop
            got = queue.pop
            expected = model.pop
            if expected.nil?
              expect(got).to be_nil
            else
              expect([got[0], got[1]]).to eq([expected[0], expected[1]])
              branches << [got[2], expected[2]]
            end
          when 4 # decrease_priority
            handles = model.entries.keys
            next if handles.empty?
            handle = handles[rng.rand(handles.size)]
            new_priority = rng.rand(model.entries[handle].priority + 1)
            branches << [queue.decrease_priority(handle, new_priority),
                         model.decrease_priority(handle, new_priority)]
          when 5 # delete
            handles = model.entries.keys
            next if handles.empty?
            handle = handles[rng.rand(handles.size)]
            branches << [queue.delete(handle), model.delete(handle)]
          when 6 # meld two possibly related branches
            other_queue, other_model = branches[rng.rand(branches.size)]
            merged_queue = queue.meld(other_queue, :min)
            merged_model = model.meld(other_model) { |_handle, a, b| [a, b].min }
            branches << [merged_queue, merged_model]
          end

          # spot-check a random (possibly old) branch after every operation
          check_queue, check_model = branches[rng.rand(branches.size)]
          expect(check_queue.size).to eq(check_model.size)
          expect(check_queue.peek).to eq(check_model.peek)
        end

        # fully drain a few surviving branches to compare the complete pop
        # order, including the stable order of equal priorities
        3.times do
          queue, model = branches[rng.rand(branches.size)]
          expect(drain(queue)).to eq(drain_model(model))
        end
      end
    end
  end
end
