# src/cassowary/operand.cr

module Cassowary
  # Provides the arithmetic operators that build an `Expression` and the comparison
  # operators that build a `Constraint`.
  #
  # Included by `Variable`, `Term` and `Expression`. `Number` accepts operands on its right side too.
  #
  # ```
  # x = Variable.new("x")
  # y = Variable.new("y")
  # 2 * x + y / 2 - 10 # => Expression
  # x + 10 <= y        # => Constraint
  # ```
  #
  # NOTE: `==` builds a constraint, so it does not test equality. Use `same?` to compare variables.
  module Operand
    # Returns this operand as an expression.
    abstract def to_expression : Expression

    # Returns the sum of this operand and *other*.
    def +(other : Operand) : Expression
      to_expression.concat(other.to_expression)
    end

    # :ditto:
    def +(other : Number) : Expression
      to_expression.offset(other.to_f64)
    end

    # Returns the difference of this operand and *other*.
    def -(other : Operand) : Expression
      to_expression.concat(other.to_expression.scale(-1.0))
    end

    # :ditto:
    def -(other : Number) : Expression
      to_expression.offset(-other.to_f64)
    end

    # Returns the negation of this operand.
    def - : Expression
      to_expression.scale(-1.0)
    end

    # Returns this operand multiplied by *factor*.
    def *(factor : Number) : Expression
      to_expression.scale(factor.to_f64)
    end

    # Returns this operand divided by *divisor*.
    def /(divisor : Number) : Expression
      to_expression.scale(1.0 / divisor.to_f64)
    end

    # Returns a required constraint that this operand equals *other*.
    def ==(other : Operand | Number) : Constraint
      Constraint.new(self - other, :equal)
    end

    # Returns a required constraint that this operand is at most *other*.
    def <=(other : Operand | Number) : Constraint
      Constraint.new(self - other, :less_equal)
    end

    # Returns a required constraint that this operand is at least *other*.
    def >=(other : Operand | Number) : Constraint
      Constraint.new(self - other, :greater_equal)
    end
  end
end
