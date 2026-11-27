# src/cassowary/row.cr

module Cassowary
  private NEAR_ZERO = 1.0e-8

  # A tableau row: `basic = constant + Σ coefficient * symbol`.
  private class Row
    getter cells : Hash(Sym, Float64)
    getter constant : Float64

    def initialize(@constant : Float64 = 0.0, @cells : Hash(Sym, Float64) = Hash(Sym, Float64).new)
    end

    def self.near_zero?(value : Float64) : Bool
      value.abs < NEAR_ZERO
    end

    def copy : Row
      Row.new(@constant, @cells.dup)
    end

    # Adds *value* to the constant and returns the new constant.
    def add(value : Float64) : Float64
      @constant += value
    end

    def insert(symbol : Sym, coefficient : Float64 = 1.0) : Nil
      sum = (@cells[symbol]? || 0.0) + coefficient
      if Row.near_zero?(sum)
        @cells.delete(symbol)
      else
        @cells[symbol] = sum
      end
    end

    def insert(row : Row, coefficient : Float64 = 1.0) : Nil
      @constant += row.constant * coefficient
      row.cells.each { |symbol, c| insert(symbol, c * coefficient) }
    end

    def remove(symbol : Sym) : Nil
      @cells.delete(symbol)
    end

    def reverse_sign : Nil
      @constant = -@constant
      @cells.transform_values! { |c| -c }
    end

    # Solves the row for *symbol*, which must be in the row.
    def solve_for(symbol : Sym) : Nil
      coefficient = -1.0 / @cells.delete(symbol).not_nil!
      @constant *= coefficient
      @cells.transform_values! { |c| c * coefficient }
    end

    # Solves `lhs = row` for *rhs*.
    def solve_for(lhs : Sym, rhs : Sym) : Nil
      insert(lhs, -1.0)
      solve_for(rhs)
    end

    def coefficient_for(symbol : Sym) : Float64
      @cells[symbol]? || 0.0
    end

    # Replaces *symbol* with *row*.
    def substitute(symbol : Sym, row : Row) : Nil
      if coefficient = @cells.delete(symbol)
        insert(row, coefficient)
      end
    end
  end
end
