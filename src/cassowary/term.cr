# src/cassowary/term.cr

module Cassowary
  # A variable multiplied by a coefficient.
  struct Term
    include Operand

    getter variable : Variable
    getter coefficient : Float64

    def initialize(@variable : Variable, coefficient : Number = 1.0)
      @coefficient = coefficient.to_f64
    end

    # Returns the coefficient times the variable's current value.
    def value : Float64
      @coefficient * @variable.value
    end

    # Returns an expression holding only this term.
    def to_expression : Expression
      Expression.new([self])
    end

    def to_s(io : IO) : Nil
      io << @coefficient << " * " << @variable.name
    end
  end
end
