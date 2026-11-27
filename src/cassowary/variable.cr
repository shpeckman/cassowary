# src/cassowary/variable.cr

module Cassowary
  # An unknown the solver assigns a value to.
  #
  # `#value` holds the result of the last `Solver#update`.
  #
  # NOTE: `==` builds a `Constraint`, so a variable must not be used as a `Hash` key
  # or compared with `==`. Use `same?` for identity.
  class Variable
    include Operand

    getter name : String
    getter value : Float64 = 0.0

    def initialize(@name : String = "")
    end

    protected def value=(@value : Float64)
    end

    # Returns an expression holding only this variable.
    def to_expression : Expression
      Expression.new([Term.new(self)])
    end

    def to_s(io : IO) : Nil
      io << @name
    end

    def inspect(io : IO) : Nil
      io << "Variable(" << @name << " = " << @value << ')'
    end
  end
end
