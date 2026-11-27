# src/cassowary/variable.cr

# An unknown the solver assigns a value to.
#
# `#value` holds the result of the last `Solver#update`.
#
# NOTE: `==` builds a `Constraint` and `!=` does not compile, so a variable must not be
# used as a `Hash` key or compared with `==`. Use `same?` for identity.
class Cassowary::Variable
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

  protected def term_count : Int32
    1
  end

  protected def append_terms(terms : Array(Term), factor : Float64) : Float64
    terms << Term.new(self, factor)
    0.0
  end

  def to_s(io : IO) : Nil
    io << @name
  end

  def inspect(io : IO) : Nil
    io << "Variable(" << @name << " = " << @value << ')'
  end
end
