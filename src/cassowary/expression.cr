# src/cassowary/expression.cr

module Cassowary
  # A linear combination of terms plus a constant.
  struct Expression
    include Operand

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

    def to_s(io : IO) : Nil
      @terms.each_with_index do |term, i|
        io << " + " if i > 0
        term.to_s(io)
      end
      io << " + " unless @terms.empty?
      io << @constant
    end

    protected def concat(other : Expression) : Expression
      Expression.new(@terms + other.terms, @constant + other.constant)
    end

    protected def offset(amount : Float64) : Expression
      Expression.new(@terms, @constant + amount)
    end

    protected def scale(factor : Float64) : Expression
      Expression.new(@terms.map { |t| Term.new(t.variable, t.coefficient * factor) }, @constant * factor)
    end

    # Merges terms that share a variable, keeping the order of first appearance.
    protected def reduce : Expression
      return self if @terms.size < 2
      index = Hash(UInt64, Int32).new
      merged = Array(Term).new(@terms.size)
      @terms.each do |term|
        key = term.variable.object_id
        if i = index[key]?
          merged[i] = Term.new(term.variable, merged[i].coefficient + term.coefficient)
        else
          index[key] = merged.size
          merged << term
        end
      end
      Expression.new(merged, @constant)
    end
  end
end
