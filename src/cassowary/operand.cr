# src/cassowary/operand.cr

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
# NOTE: `==` builds a constraint, so it does not test equality, and `!=` does not compile.
# Use `same?` to compare variables.
module Cassowary::Operand
  # Returns this operand as an expression.
  abstract def to_expression : Expression

  # Returns the number of terms this operand contributes to an expression.
  protected abstract def term_count : Int32

  # Appends the terms of this operand times *factor* to *terms* and returns its
  # constant times *factor*.
  protected abstract def append_terms(terms : Array(Term), factor : Float64) : Float64

  # Returns the sum of this operand and *other*.
  def +(other : Operand) : Expression
    combine(other, 1.0)
  end

  # :ditto:
  def +(other : Number) : Expression
    to_expression.offset(other.to_f64)
  end

  # Returns the difference of this operand and *other*.
  def -(other : Operand) : Expression
    combine(other, -1.0)
  end

  # :ditto:
  def -(other : Number) : Expression
    to_expression.offset(-other.to_f64)
  end

  # Returns the negation of this operand.
  def - : Expression
    scaled(-1.0)
  end

  # Returns this operand multiplied by *other*.
  def *(other : Number) : Expression
    scaled(other.to_f64)
  end

  # Returns this operand divided by *other*.
  def /(other : Number) : Expression
    scaled(1.0 / other.to_f64)
  end

  # Returns a required constraint that this operand equals *other*.
  def ==(other : Operand | Number) : Constraint
    Constraint.new(self - other, :equal)
  end

  # Fails to compile: an inequation is not a linear constraint, and `!=` would otherwise
  # negate a `Constraint` into `false`. Use `same?` to compare variables.
  def !=(other : Operand | Number) : NoReturn
    {% raise "Cassowary::Operand#!= cannot build a constraint; use `same?` to compare variables" %}
  end

  # Returns a required constraint that this operand is at most *other*.
  def <=(other : Operand | Number) : Constraint
    Constraint.new(self - other, :less_equal)
  end

  # Returns a required constraint that this operand is at least *other*.
  def >=(other : Operand | Number) : Constraint
    Constraint.new(self - other, :greater_equal)
  end

  private def combine(other : Operand, factor : Float64) : Expression
    terms = Array(Term).new(term_count + other.term_count)
    constant = append_terms(terms, 1.0)
    constant += other.append_terms(terms, factor)
    Expression.new(terms, constant)
  end

  private def scaled(factor : Float64) : Expression
    terms = Array(Term).new(term_count)
    constant = append_terms(terms, factor)
    Expression.new(terms, constant)
  end
end
