require "benchmark/ips"
require "hamster/vector"

Benchmark.ips do |b|
  lrg_vector = Hamster::Vector.new(1..1_000_000)

  b.report "take small" do |n|
    a = 0
    while a < n
      lrg_vector.take(10)
      a += 1
    end
  end

  b.report "drop aligned" do |n|
    a = 0
    while a < n
      lrg_vector.drop(999_968)
      a += 1
    end
  end

  b.report "slice small" do |n|
    a = 0
    while a < n
      lrg_vector[500_000, 10]
      a += 1
    end
  end

  b.report "slice aligned large" do |n|
    a = 0
    while a < n
      lrg_vector[32768, 500_000]
      a += 1
    end
  end
end
