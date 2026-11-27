# src/cassowary/expression.cr

# A linear combination of terms plus a constant.
struct Cassowary::Expression
  include Operand

  # Above this many terms, `#reduce` detects repeated variables with a set.
  private LINEAR_SCAN_LIMIT = 16

  getter terms : Array(Term)
  getter constant : Float64

  def initialize(@terms : Array(Term) = [] of Term, constant : Number = 0.0)
    @constant = constant.to_f64
  end

  # Creates an expression holding only *constant*.
  def self.new(constant : Number) : Expression
    new([] of Term, constant)
  end

  # Returns the expression evaluated with the variables' current values.
  def value : Float64
    @terms.sum(@constant, &.value)
  end

  # Returns `self`.
  def to_expression : Expression
    self
  end

  # Writes the expression in readable form, such as `x + 2 * y - 10`.
  def to_s(io : IO) : Nil
    @terms.each_with_index do |term, i|
      Expression.write_term(io, term.coefficient, term.variable, i == 0)
    end
    if @terms.empty?
      Expression.write_number(io, @constant)
    elsif @constant != 0.0
      io << (@constant < 0.0 ? " - " : " + ")
      Expression.write_number(io, @constant.abs)
    end
  end

  # Writes *number* without a fractional part when it is integral.
  protected def self.write_number(io : IO, number : Float64) : Nil
    if number == number.trunc && number.abs < 1.0e15
      io << number.to_i64
    else
      io << number
    end
  end

  # Writes *coefficient* times *variable* as `x`, `-x` or `2 * x`, joined to a
  # preceding term by ` + ` or ` - ` unless it is the *first*.
  protected def self.write_term(io : IO, coefficient : Float64, variable : Variable, first : Bool) : Nil
    if first
      io << '-' if coefficient < 0.0
    else
      io << (coefficient < 0.0 ? " - " : " + ")
    end
    magnitude = coefficient.abs
    unless magnitude == 1.0
      write_number(io, magnitude)
      io << " * "
    end
    io << variable.name
  end

  protected def term_count : Int32
    @terms.size
  end

  protected def append_terms(terms : Array(Term), factor : Float64) : Float64
    if factor == 1.0
      terms.concat(@terms)
    else
      @terms.each { |term| terms << Term.new(term.variable, term.coefficient * factor) }
    end
    @constant * factor
  end

  # Returns this expression with *amount* added to the constant, sharing the terms.
  protected def offset(amount : Float64) : Expression
    Expression.new(@terms, @constant + amount)
  end

  # Merges terms that share a variable, keeping the order of first appearance.
  # Returns `self` when no variable repeats.
  protected def reduce : Expression
    return self unless repeats_variable?
    merged = Array(Term).new(@terms.size)
    positions = Hash(UInt64, Int32).new if @terms.size > LINEAR_SCAN_LIMIT
    @terms.each do |term|
      variable = term.variable
      i = positions ? positions[variable.object_id]? : merged.index(&.variable.same?(variable))
      if i
        merged[i] = Term.new(variable, merged.unsafe_fetch(i).coefficient + term.coefficient)
      else
        positions.try &.[]=(variable.object_id, merged.size)
        merged << term
      end
    end
    Expression.new(merged, @constant)
  end

  private def repeats_variable? : Bool
    size = @terms.size
    return false if size < 2
    if size <= LINEAR_SCAN_LIMIT
      (1...size).any? do |i|
        variable = @terms.unsafe_fetch(i).variable
        (0...i).any? { |j| @terms.unsafe_fetch(j).variable.same?(variable) }
      end
    else
      seen = Set(UInt64).new(size)
      @terms.any? { |term| !seen.add?(term.variable.object_id) }
    end
  end
end
