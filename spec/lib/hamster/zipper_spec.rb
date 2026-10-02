require "spec_helper"
require "hamster/nested"
require "hamster/zipper"

describe Hamster::Zipper do
  def from_model(value)
    Hamster.from(value)
  end

  def model_node(root, path)
    path.reduce(root) do |node, locator|
      node.fetch(locator)
    end
  end

  def model_parent(root, path)
    model_node(root, path[0...-1])
  end

  def model_entries(parent)
    if parent.is_a?(::Array)
      parent.each_with_index.map { |value, index| [index, value] }
    else
      from_model(parent).each.to_a
    end
  end

  def set_model(root, path, value)
    return value if path.empty?
    parent = model_node(root, path[0...-1])
    parent[path.last] = value
    root
  end

  def random_value(random)
    case random.rand(5)
    when 0 then nil
    when 1 then random.rand(1000)
    when 2 then "value-#{random.rand(1000)}"
    when 3 then [nil, random.rand(1000)]
    else { "key" => random.rand(1000) }
    end
  end

  it "matches a naive model through short random navigation and edit sequences" do
    initial_model = {
      "a" => [1, nil, { "x" => 7, "y" => [nil, 8] }],
      "b" => { "m" => 2, "n" => 3 },
      "c" => [4],
      "d" => nil
    }

    100.times do |iteration|
      random = Random.new(9000 + iteration)
      model_root = Marshal.load(Marshal.dump(initial_model))
      model_path = []
      zipper = Hamster::Zipper.new(from_model(model_root))

      25.times do
        current = model_node(model_root, model_path)
        possible_actions = [4]
        possible_actions << 0 unless model_path.empty?
        if current.is_a?(::Hash) || current.is_a?(::Array)
          possible_actions << 1 unless current.empty?
        end
        if !model_path.empty?
          parent = model_parent(model_root, model_path)
          position = model_entries(parent).index { |key, _| key == model_path.last }
          possible_actions << 2 if position > 0
          possible_actions << 3 if position < model_entries(parent).size - 1
          possible_actions << 5
        end

        case possible_actions.sample(random: random)
        when 0
          zipper = zipper.up
          model_path.pop
        when 1
          locator = if current.is_a?(::Array)
            random.rand(current.size)
          else
            current.keys.sample(random: random)
          end
          zipper = zipper.down(locator)
          model_path << locator
        when 2
          parent = model_parent(model_root, model_path)
          position = model_entries(parent).index { |key, _| key == model_path.last }
          zipper = zipper.left
          model_path[-1] = model_entries(parent)[position - 1].first
        when 3
          parent = model_parent(model_root, model_path)
          entries = model_entries(parent)
          position = entries.index { |key, _| key == model_path.last }
          zipper = zipper.right
          model_path[-1] = entries[position + 1].first
        when 4
          value = random_value(random)
          zipper = zipper.replace(from_model(value))
          model_root = set_model(model_root, model_path, value)
        when 5
          parent = model_parent(model_root, model_path)
          old_position = model_entries(parent).index { |key, _| key == model_path.last }
          locator = model_path.last

          zipper = zipper.delete
          if parent.is_a?(::Array)
            parent.delete_at(locator)
          else
            parent.delete(locator)
          end

          if parent.empty?
            model_path.pop
          else
            new_position = old_position >= parent.size ? old_position - 1 : old_position
            model_path[-1] = model_entries(parent)[new_position].first
          end
        end

        expected_current = model_node(model_root, model_path)
        expect(zipper.node).to eql(from_model(expected_current))
        expect(zipper.locator).to eql(model_path.last)
        expect(zipper.root?).to eql(model_path.empty?)
        expect(zipper.root).to eql(from_model(model_root))
      end
    end
  end

  it "navigates nil nodes and nil hash keys as existing nodes" do
    root = Hamster::Hash[
      nil => nil,
      "items" => Hamster::Vector[nil, Hamster::Hash["nil" => nil]]
    ]

    zipper = Hamster.zipper(root).down(nil)
    expect(zipper.node).to be_nil
    expect(zipper.locator).to be_nil

    new_root = zipper.up.down("items").down(1).down("nil").replace(5).root
    expect(new_root[nil]).to be_nil
    expect(new_root["items"][0]).to be_nil
    expect(new_root["items"][1]["nil"]).to eq(5)
    expect(Hamster.zipper(new_root["items"]).down(-1).node).to eql(Hamster::Hash["nil" => 5])

    expect { Hamster.zipper(root).down(:missing) }.to raise_error(Hamster::Zipper::ZipperError)
    expect { Hamster.zipper(root).down("items").down(9) }.to raise_error(Hamster::Zipper::ZipperError)
  end

  it "places the cursor explicitly after deleting a child" do
    vector = Hamster::Vector[1, 2, 3]

    first = Hamster.zipper(vector).down(0).delete
    expect(first.node).to eq(2)
    expect(first.locator).to eq(0)
    expect(first.root).to eql(Hamster::Vector[2, 3])

    last = Hamster.zipper(vector).down(2).delete
    expect(last.node).to eq(2)
    expect(last.locator).to eq(1)
    expect(last.root).to eql(Hamster::Vector[1, 2])

    only = Hamster.zipper(Hamster::Vector[Hamster::Vector[1]]).down(0).down(0).delete
    expect(only.node).to eql(Hamster::Vector[])
    expect(only.locator).to eq(0)
    expect(only.root).to eql(Hamster::Vector[Hamster::Vector[]])

    only_hash_child = Hamster.zipper(Hamster::Hash["parent" => Hamster::Hash["child" => 1]])
    only_hash_child = only_hash_child.down("parent").down("child").delete
    expect(only_hash_child.node).to eql(Hamster::Hash[])
    expect(only_hash_child.locator).to eq("parent")
    expect(only_hash_child.root).to eql(Hamster::Hash["parent" => Hamster::Hash[]])

    expect { Hamster.zipper(vector).delete }.to raise_error(Hamster::Zipper::ZipperError)
  end

  it "places the cursor after deleting a hash child in iteration order" do
    hash = Hamster::Hash["a" => 1, "b" => 2, "c" => 3]
    keys = hash.keys.to_a

    first = Hamster.zipper(hash).down(keys.first).delete
    expect(first.locator).to eq(keys[1])
    expect(first.node).to eq(hash.get(keys[1]))

    last = Hamster.zipper(hash).down(keys.last).delete
    expect(last.locator).to eq(keys[-2])
    expect(last.node).to eq(hash.get(keys[-2]))

    only = Hamster.zipper(Hamster::Hash["parent" => hash]).down("parent").down(keys.first).delete.up.down(keys[1]).delete.up.down(keys.last).delete
    expect(only.node).to eql(Hamster::Hash[])
    expect(only.locator).to eq("parent")
  end

  it "keeps the old root, independent cursor branches, and unedited siblings unchanged" do
    shared = Hamster::Hash["leaf" => 1]
    untouched_sibling = Hamster::Hash["keep" => 2]
    other_branch = Hamster::Hash["keep" => 3]
    root = Hamster::Hash[
      "a" => Hamster::Vector[shared, untouched_sibling],
      "b" => other_branch
    ]

    branch_a = Hamster.zipper(root).down("a")
    branch_b = Hamster.zipper(root).down("b")
    edited = branch_a.down(0).down("leaf").replace(4).root

    expect(root).to eql(Hamster::Hash[
      "a" => Hamster::Vector[
        Hamster::Hash["leaf" => 1],
        untouched_sibling
      ],
      "b" => other_branch
    ])
    expect(branch_b.root).to eql(root)
    expect(branch_b.root).to equal(root)
    expect(edited["a"][1]).to equal(untouched_sibling)
    expect(edited["b"]).to equal(other_branch)
    expect(edited["a"][0]).not_to equal(shared)
    expect(edited["a"][0]["leaf"]).to eq(4)
  end
end
