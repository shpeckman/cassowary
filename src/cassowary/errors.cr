# src/cassowary/errors.cr

module Cassowary
  # Base class of every error the solver raises.
  class Error < Exception
  end

  # Raised by `Solver#add` when the constraint is already in the solver.
  class DuplicateConstraint < Error
    getter constraint : Constraint

    def initialize(@constraint : Constraint)
      super("Constraint is already in the solver")
    end
  end

  # Raised by `Solver#add` when a required constraint conflicts with the required constraints already in the solver.
  #
  # The solver is left unchanged.
  class UnsatisfiableConstraint < Error
    getter constraint : Constraint

    def initialize(@constraint : Constraint)
      super("Required constraint cannot be satisfied")
    end
  end

  # Raised by `Solver#remove` when the constraint is not in the solver.
  class UnknownConstraint < Error
    getter constraint : Constraint

    def initialize(@constraint : Constraint)
      super("Constraint is not in the solver")
    end
  end

  # Raised by `Solver#add_edit` when the variable is already an edit variable.
  class DuplicateEdit < Error
    getter variable : Variable

    def initialize(@variable : Variable)
      super("Variable '#{variable.name}' is already an edit variable")
    end
  end

  # Raised by `Solver#remove_edit` and `Solver#suggest` when the variable is not an edit variable.
  class UnknownEdit < Error
    getter variable : Variable

    def initialize(@variable : Variable)
      super("Variable '#{variable.name}' is not an edit variable")
    end
  end

  # Raised by `Solver#add_edit` when the strength is `Strength::REQUIRED`.
  class BadRequiredStrength < Error
    getter variable : Variable

    def initialize(@variable : Variable)
      super("Edit variable '#{variable.name}' cannot have required strength")
    end
  end

  # Raised when the solver reaches a state that violates its invariants, which indicates a bug in the solver.
  class InternalError < Error
  end
end
