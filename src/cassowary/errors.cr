# src/cassowary/errors.cr

# Base class of every error the solver raises.
class Cassowary::Error < Exception
end

# Raised by `Solver#add` when the constraint is already in the solver.
class Cassowary::DuplicateConstraint < Cassowary::Error
  getter constraint : Constraint

  def initialize(@constraint : Constraint)
    super("Constraint is already in the solver")
  end
end

# Raised by `Solver#add` when a required constraint conflicts with the required constraints already in the solver.
#
# The solver is left unchanged.
class Cassowary::UnsatisfiableConstraint < Cassowary::Error
  getter constraint : Constraint

  # Returns required constraints already in the solver that `#constraint` conflicts
  # with. The set may hold more than needed; `Solver#explain` returns a minimal one.
  getter conflicts : Array(Constraint)

  def initialize(@constraint : Constraint, @conflicts : Array(Constraint) = [] of Constraint)
    super("Required constraint cannot be satisfied")
  end
end

# Raised by `Solver#remove` when the constraint is not in the solver.
class Cassowary::UnknownConstraint < Cassowary::Error
  getter constraint : Constraint

  def initialize(@constraint : Constraint)
    super("Constraint is not in the solver")
  end
end

# Raised by `Solver#add_edit` when the variable is already an edit variable.
class Cassowary::DuplicateEdit < Cassowary::Error
  getter variable : Variable

  def initialize(@variable : Variable)
    super("Variable '#{variable.name}' is already an edit variable")
  end
end

# Raised by `Solver#remove_edit` and `Solver#suggest` when the variable is not an edit variable.
class Cassowary::UnknownEdit < Cassowary::Error
  getter variable : Variable

  def initialize(@variable : Variable)
    super("Variable '#{variable.name}' is not an edit variable")
  end
end

# Raised by `Solver#add_edit` when the strength is `Strength::REQUIRED`.
class Cassowary::BadRequiredStrength < Cassowary::Error
  getter variable : Variable

  def initialize(@variable : Variable)
    super("Edit variable '#{variable.name}' cannot have required strength")
  end
end

# Raised when the solver reaches a state that violates its invariants, which indicates a bug in the solver.
class Cassowary::InternalError < Cassowary::Error
end
