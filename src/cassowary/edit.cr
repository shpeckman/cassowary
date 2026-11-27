# src/cassowary/edit.cr

# An edit variable inside `Solver#edit`, which steers it with `#suggest`.
struct Cassowary::Edit
  getter variable : Variable

  # :nodoc:
  def initialize(@solver : Solver, @variable : Variable)
  end

  # Suggests *value* for `#variable`; see `Solver#suggest`.
  def suggest(value : Number) : Nil
    @solver.suggest(@variable, value)
  end
end
