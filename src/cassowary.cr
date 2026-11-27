# src/cassowary.cr

# An incremental linear constraint solver based on the Cassowary algorithm.
#
# ```
# require "cassowary"
#
# left = Cassowary::Variable.new("left")
# width = Cassowary::Variable.new("width")
# right = Cassowary::Variable.new("right")
#
# solver = Cassowary::Solver.new
# solver.add(right == left + width)
# solver.add(width >= 100)
# solver.add((left == 0).strength(:strong))
# solver.add_edit(width, :strong)
# solver.suggest(width, 250)
# solver.update
# right.value # => 250.0
# ```
module Cassowary
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end

require "./cassowary/errors"
require "./cassowary/strength"
require "./cassowary/operand"
require "./cassowary/variable"
require "./cassowary/term"
require "./cassowary/expression"
require "./cassowary/constraint"
require "./cassowary/number"
require "./cassowary/symbol"
require "./cassowary/row"
require "./cassowary/solver"
