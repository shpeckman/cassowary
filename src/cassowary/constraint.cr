# src/cassowary/constraint.cr

# A linear relation between an expression and zero, with a strength.
#
# Build constraints with the comparison operators of `Operand`:
#
# ```
# (x + 10 <= y).strength(:medium)
# ```
#
# A constraint is immutable; the solver identifies it by object identity.
class Cassowary::Constraint
  # The relation between the expression and zero.
  enum Operator
    LessEqual
    GreaterEqual
    Equal
  end

  # Relative tolerance of `#violated?`, against the largest term or constant.
  private VIOLATION_EPSILON = 1.0e-8

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

  # Returns whether the variables' current values break this constraint, regardless of
  # its strength.
  def violated? : Bool
    value = @expression.value
    magnitude = @expression.terms.reduce(Math.max(1.0, @expression.constant.abs)) do |largest, term|
      Math.max(largest, term.value.abs)
    end
    return false if value.abs < VIOLATION_EPSILON * magnitude
    case @operator
    in .less_equal?    then value > 0.0
    in .greater_equal? then value < 0.0
    in .equal?         then true
    end
  end

  # Writes the constraint in readable form, such as `x + 10 <= y | strong`: positive
  # terms on the left, negative ones on the right, and the strength unless required.
  def to_s(io : IO) : Nil
    write_side(io, 1.0)
    io << case @operator
    in .less_equal?    then " <= "
    in .greater_equal? then " >= "
    in .equal?         then " == "
    end
    write_side(io, -1.0)
    io << " | " << @strength unless @strength.required?
  end

  def inspect(io : IO) : Nil
    io << "Constraint(" << self << ')'
  end

  # Writes the terms and constant whose sign times *sign* is positive, or `0`.
  private def write_side(io : IO, sign : Float64) : Nil
    first = true
    @expression.terms.each do |term|
      coefficient = term.coefficient * sign
      next unless coefficient > 0.0
      Expression.write_term(io, coefficient, term.variable, first)
      first = false
    end
    constant = @expression.constant * sign
    if constant > 0.0
      io << " + " unless first
      Expression.write_number(io, constant)
    elsif first
      io << '0'
    end
  end
end
