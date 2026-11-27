# src/cassowary/term.cr

# A variable multiplied by a coefficient.
struct Cassowary::Term
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

  protected def term_count : Int32
    1
  end

  protected def append_terms(terms : Array(Term), factor : Float64) : Float64
    terms << (factor == 1.0 ? self : Term.new(@variable, @coefficient * factor))
    0.0
  end

  def to_s(io : IO) : Nil
    io << @coefficient << " * " << @variable.name
  end
end
