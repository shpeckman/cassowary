# bench/expressions.cr
require "./bench_helper"

x = Cassowary::Variable.new("x")
y = Cassowary::Variable.new("y")
z = Cassowary::Variable.new("z")
w = Cassowary::Variable.new("w")

Bench.group("building expressions and constraints") do |job|
  job.report("x + y") { Bench.keep(x + y) }
  job.report("x - y") { Bench.keep(x - y) }
  job.report("2 * x + y / 2 - 10") { Bench.keep(2 * x + y / 2 - 10) }
  job.report("x + y + z + w") { Bench.keep(x + y + z + w) }
  job.report("x + 10 <= y") { Bench.keep(x + 10 <= y) }
  job.report("x + y + x - z == w (merges x)") { Bench.keep(x + y + x - z == w) }
end
