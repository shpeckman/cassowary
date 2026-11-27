# bench/bench_helper.cr
require "benchmark"
require "../src/cassowary"

module Bench
  WARMUP      = 500.milliseconds
  CALCULATION = 2.seconds
  BOXES       = 200

  class_property sink = 0.0

  def self.group(title : String, & : Benchmark::IPS::Job ->) : Nil
    puts
    puts title
    Benchmark.ips(warmup: WARMUP, calculation: CALCULATION) { |job| yield job }
  end

  def self.keep(value : Float64) : Nil
    @@sink += value
  end

  def self.keep(expression : Cassowary::Expression) : Nil
    @@sink += expression.constant + expression.terms.size
  end

  def self.keep(constraint : Cassowary::Constraint) : Nil
    keep(constraint.expression)
  end

  # Returns the left and width variables of *count* boxes laid out in a row with
  # 10 points of spacing, and the solver holding them.
  def self.row_layout(count : Int32) : {Cassowary::Solver, Array(Cassowary::Variable), Array(Cassowary::Variable)}
    solver = Cassowary::Solver.new
    lefts = Array.new(count) { |i| Cassowary::Variable.new("left#{i}") }
    widths = Array.new(count) { |i| Cassowary::Variable.new("width#{i}") }
    solver.add(lefts[0] == 0)
    count.times do |i|
      solver.add(widths[i] >= 10)
      solver.add((widths[i] == 50).strength(:weak))
      solver.add(lefts[i] + widths[i] + 10 <= lefts[i + 1]) if i + 1 < count
    end
    solver.add(lefts[-1] + widths[-1] <= count * 40)
    {solver, lefts, widths}
  end
end
