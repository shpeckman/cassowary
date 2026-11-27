# src/cassowary/constraint.cr

module Cassowary
  # A linear relation between an expression and zero, with a strength.
  #
  # Build constraints with the comparison operators of `Operand`:
  #
  # ```
  # (x + 10 <= y).strength(:medium)
  # ```
  #
  # A constraint is immutable; the solver identifies it by object identity.
  class Constraint
    # The relation between the expression and zero.
    enum Operator
      LessEqual
      GreaterEqual
      Equal
    end

    getter expression : Expression
    getter operator : Operator
    getter strength : Strength

    # Creates a constraint stating that *expression* relates to zero by *operator*.
    def initialize(expression : Expression, @operator : Operator, strength : Strength | Strength::Preset = Strength::REQUIRED)
      @expression = expression.reduce
      @strength = strength.is_a?(Strength::Preset) ? strength.strength : strength
    end

    # Returns a copy of this constraint with *strength*.
    def strength(strength : Strength | Strength::Preset) : Constraint
      Constraint.new(@expression, @operator, strength)
    end

    def to_s(io : IO) : Nil
      @expression.to_s(io)
      io << case @operator
      in .less_equal?    then " <= 0"
      in .greater_equal? then " >= 0"
      in .equal?         then " == 0"
      end
      io << " | " << @strength
    end
  end
end
