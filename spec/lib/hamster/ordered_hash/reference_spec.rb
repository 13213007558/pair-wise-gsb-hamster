require "spec_helper"
require "hamster/ordered_hash"

# These specs use Ruby's built-in Hash as the behavioral reference: every
# sequence of edits is applied to a Hamster::OrderedHash and a Ruby Hash in
# parallel, and the insertion order (forward, reverse, and positional) of
# the two is compared afterwards.
describe Hamster::OrderedHash do
  # Apply one edit to both an OrderedHash and a Ruby Hash.
  def apply_edit(ordered, ruby, edit)
    op, key, value = edit
    case op
    when :put
      [ordered.put(key, value), ruby.tap { ruby[key] = value }]
    when :delete
      [ordered.delete(key), ruby.tap { ruby.delete(key) }]
    when :merge
      pairs = value
      [ordered.merge(pairs), ruby.tap { ruby.merge!(pairs.to_h) }]
    end
  end

  # Assert that every public projection of `ordered` which involves order
  # agrees with the Ruby Hash reference `ruby`.
  def expect_order_to_match(ordered, ruby)
    expect(ordered.size).to eq(ruby.size)
    expect(ordered.keys.to_a).to eq(ruby.keys)
    expect(ordered.values.to_a).to eq(ruby.values)
    expect(ordered.to_a).to eq(ruby.to_a)
    expect(ordered.reverse_each.to_a).to eq(ruby.reverse_each.to_a)
    expect(ordered.to_hash).to eq(ruby)
    ruby.keys.each_with_index do |key, i|
      expect(ordered.key_at(i)).to eq(key)
      expect(ordered.key_at(i - ruby.size)).to eq(key)
    end
    expect(ordered.key_at(ruby.size)).to be_nil
    expect(ordered.key_at(-ruby.size - 1)).to be_nil
  end

  def random_edits(rng, key_pool, count)
    Array.new(count) do
      case rng.rand(10)
      when 0..5
        [:put, key_pool.sample(random: rng), rng.rand(1000)]
      when 6..8
        [:delete, key_pool.sample(random: rng)]
      else
        pairs = Array.new(rng.rand(1..4)) { [key_pool.sample(random: rng), rng.rand(1000)] }
        [:merge, nil, pairs]
      end
    end
  end

  describe "with Ruby Hash as the behavioral reference" do
    it "follows Ruby Hash ordering through a long random edit sequence" do
      rng = Random.new(620)
      key_pool = (1..30).map { |i| "key-#{i}" }
      ordered = OH.new
      ruby = {}
      random_edits(rng, key_pool, 1500).each do |edit|
        ordered, ruby = apply_edit(ordered, ruby, edit)
      end
      expect_order_to_match(ordered, ruby)
    end

    it "follows Ruby Hash ordering through long delete/re-insert churn" do
      ordered = OH.new
      ruby = {}
      200.times { |i| ordered = ordered.put(i, i); ruby[i] = i }
      5_000.times do |i|
        key = (i * 37) % 200
        ordered = ordered.delete(key).put(key, i)
        ruby.delete(key)
        ruby[key] = i
      end
      expect_order_to_match(ordered, ruby)
    end
  end

  describe "forking two versions from a shared base" do
    it "lets each fork diverge independently while the base stays unchanged" do
      base_keys = ("a".."t").to_a
      base = OH.new(base_keys.each_with_index.map { |k, i| [k, i] })
      base_ruby = base_keys.each_with_index.map { |k, i| [k, i] }.to_h

      edits_a = [
        [:delete, "c"], [:put, "x", 100], [:put, "a", 999],
        [:delete, "m"], [:put, "c", 200], [:merge, nil, [["q", 17], ["b", 222]]],
      ]
      edits_b = [
        [:put, "j", 999], [:delete, "a"], [:delete, "b"],
        [:put, "y", 101], [:merge, nil, [["c", 333], ["z", 102]]], [:delete, "t"],
      ]

      fork_a, ruby_a = base, base_ruby.dup
      edits_a.each { |edit| fork_a, ruby_a = apply_edit(fork_a, ruby_a, edit) }
      fork_b, ruby_b = base, base_ruby.dup
      edits_b.each { |edit| fork_b, ruby_b = apply_edit(fork_b, ruby_b, edit) }

      # the base is untouched by either fork
      expect_order_to_match(base, base_ruby)

      # each fork matches its own Ruby Hash reference
      expect_order_to_match(fork_a, ruby_a)
      expect_order_to_match(fork_b, ruby_b)

      # the forks really did diverge
      expect(fork_a.keys.to_a).not_to eq(fork_b.keys.to_a)
      expect(fork_a.keys.to_a).to eq(ruby_a.keys)
      expect(fork_b.keys.to_a).to eq(ruby_b.keys)
    end
  end

  describe "internal slot indices" do
    it "never leak through the public API, even after heavy churn" do
      ordered = OH.new
      100.times { |i| ordered = ordered.put("key-#{i}", i) }
      90.times { |i| ordered = ordered.delete("key-#{i}") }
      10.times { |i| ordered = ordered.put("fresh-#{i}", i) }

      expected_keys = (90..99).map { |i| "key-#{i}" } + (0..9).map { |i| "fresh-#{i}" }

      # enumeration yields exactly [key, value] pairs, nothing else
      ordered.each do |pair|
        expect(pair).to be_a(Array)
        expect(pair.size).to eq(2)
        expect(pair[0]).to be_a(String)
        expect(pair[1]).to be_a(Integer)
      end

      expect(ordered.keys.to_a).to eq(expected_keys)
      expect(ordered.values.to_a).to eq((90..99).to_a + (0..9).to_a)
      expect(ordered.to_a).to eq(expected_keys.zip((90..99).to_a + (0..9).to_a))
      expect(ordered.inspect).to eq(
        "Hamster::OrderedHash[" +
        expected_keys.zip((90..99).to_a + (0..9).to_a).map { |k, v| "#{k.inspect} => #{v.inspect}" }.join(", ") +
        "]"
      )
      expect(ordered.marshal_dump).to eq(ordered.to_hash)

      # a marshalled copy exposes the same clean view
      loaded = Marshal.load(Marshal.dump(ordered))
      expect(loaded.keys.to_a).to eq(expected_keys)

      # and an equal hash can be rebuilt from scratch with no shared history
      rebuilt = OH.new(expected_keys.zip((90..99).to_a + (0..9).to_a))
      expect(rebuilt).to eql(ordered)
      expect(rebuilt.hash).to eq(ordered.hash)
    end
  end
end
