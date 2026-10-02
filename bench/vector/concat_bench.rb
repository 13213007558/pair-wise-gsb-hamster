require "benchmark/ips"
require "hamster/vector"

Benchmark.ips do |b|
  sml_vector = Hamster::Vector.new(1..32)
  med_vector = Hamster::Vector.new(1..1024)
  lrg_vector = Hamster::Vector.new(1..32768)

  b.report "concat small" do |n|
    a = 0
    while a < n
      sml_vector + med_vector
      a += 1
    end
  end

  b.report "concat medium" do |n|
    a = 0
    while a < n
      med_vector + lrg_vector
      a += 1
    end
  end

  b.report "concat large" do |n|
    a = 0
    while a < n
      lrg_vector + lrg_vector
      a += 1
    end
  end

  b.report "concat batch" do |n|
    a = 0
    while a < n
      acc = Hamster::Vector.empty
      10.times { |i| acc = acc + med_vector }
      a += 1
    end
  end
end
