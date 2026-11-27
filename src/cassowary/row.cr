# src/cassowary/row.cr

# A tableau row: `basic = constant + Σ coefficient * symbol`. `T` is `Float64` for the
# tableau and `Cost` for the objective, which weighs every strength level separately.
#
# Cells live in two parallel buffers sorted by symbol. Adding a row merges it in place
# from the back, so cells before the first changed symbol never move and the merge needs
# no second buffer.
#
# The block overloads of `#insert` and `#substitute` yield every symbol that enters
# (`true`) or leaves (`false`) the row; the solver uses them to keep its column index.
private class Cassowary::Row(T)
  private NEAR_ZERO = 1.0e-8

  # When the cells a merge may move outnumber the incoming cells by more than this
  # ratio, the merge moves runs of cells through `memmove` instead of cell by cell.
  private RUN_RATIO = 8

  getter constant : T
  getter size = 0
  protected getter symbols = Pointer(Sym).null
  protected getter coefficients = Pointer(T).null
  @capacity = 0

  def initialize(@constant : T)
  end

  def self.near_zero?(value : Float64) : Bool
    value.abs < NEAR_ZERO
  end

  def self.near_zero?(value : Cost) : Bool
    value.near_zero?
  end

  def self.magnitude(value : Float64) : Float64
    value.abs
  end

  def self.magnitude(value : Cost) : Float64
    value.magnitude
  end

  def self.negative?(value : Float64) : Bool
    value < 0.0
  end

  def self.negative?(value : Cost) : Bool
    value.negative?
  end

  def copy : Row(T)
    Row(T).new(@constant).copy_from(self)
  end

  # Makes this row equal to *other*, reusing its buffers, and returns it.
  def copy_from(other : Row(T)) : self
    @constant = other.constant
    reserve(other.size)
    @symbols.copy_from(other.symbols, other.size)
    @coefficients.copy_from(other.coefficients, other.size)
    @size = other.size
    self
  end

  # Removes every cell and sets the constant to *constant*.
  def clear(@constant : T) : Nil
    @size = 0
  end

  def empty? : Bool
    @size == 0
  end

  def each(& : Sym, T ->) : Nil
    @size.times { |i| yield @symbols[i], @coefficients[i] }
  end

  def each_symbol(& : Sym ->) : Nil
    @size.times { |i| yield @symbols[i] }
  end

  def find_symbol(& : Sym -> Bool) : Sym?
    @size.times do |i|
      symbol = @symbols[i]
      return symbol if yield symbol
    end
    nil
  end

  def all_symbols?(& : Sym -> Bool) : Bool
    @size.times { |i| return false unless yield @symbols[i] }
    true
  end

  # Returns the largest absolute coefficient component, or zero for an empty row.
  def max_magnitude : Float64
    max = 0.0
    @size.times { |i| max = Math.max(max, Row.magnitude(@coefficients[i])) }
    max
  end

  def coefficient_for(symbol : Sym) : T
    i = search(symbol)
    i >= 0 ? @coefficients[i] : @constant * 0.0
  end

  # Returns the first symbol that is not a dummy and whose increase lowers this row.
  def entering_symbol : Sym?
    @size.times do |i|
      symbol = @symbols[i]
      return symbol if !symbol.dummy? && Row.negative?(@coefficients[i])
    end
    nil
  end

  # Adds *value* to the constant and returns the new constant.
  def add(value : T) : T
    @constant += value
  end

  def insert(symbol : Sym, coefficient : T) : Nil
    insert(symbol, coefficient) { }
  end

  def insert(symbol : Sym, coefficient : T, & : Sym, Bool ->) : Nil
    i = search(symbol)
    if i >= 0
      sum = @coefficients[i] + coefficient
      if Row.near_zero?(sum)
        delete_at(i)
        yield symbol, false
      else
        @coefficients[i] = sum
      end
    elsif !Row.near_zero?(coefficient)
      insert_at(~i, symbol, coefficient)
      yield symbol, true
    end
  end

  def insert(row : Row(Float64), coefficient : T) : Nil
    insert(row, coefficient) { }
  end

  # Adds *row* times *coefficient*.
  def insert(row : Row(Float64), coefficient : T, & : Sym, Bool ->) : Nil
    @constant += coefficient * row.constant
    merge(row, coefficient, -1) { |symbol, entered| yield symbol, entered }
  end

  def remove(symbol : Sym) : Nil
    i = search(symbol)
    delete_at(i) if i >= 0
  end

  def reverse_sign : Nil
    @constant = -@constant
    @size.times { |i| @coefficients[i] = -@coefficients[i] }
  end

  # Solves the row for *symbol*, which must be in the row.
  def solve_for(symbol : Sym) : Nil
    i = search(symbol)
    raise Cassowary::InternalError.new("Symbol #{symbol} is not in the row") if i < 0
    coefficient = -1.0 / @coefficients[i]
    delete_at(i)
    @constant *= coefficient
    @size.times { |k| @coefficients[k] *= coefficient }
  end

  # Solves `lhs = row` for *rhs*.
  def solve_for(lhs : Sym, rhs : Sym) : Nil
    insert(lhs, -1.0)
    solve_for(rhs)
  end

  def substitute(symbol : Sym, row : Row(Float64)) : Nil
    substitute(symbol, row) { }
  end

  # Replaces *symbol* with *row*.
  def substitute(symbol : Sym, row : Row(Float64), & : Sym, Bool ->) : Nil
    i = search(symbol)
    return if i < 0
    coefficient = @coefficients[i]
    yield symbol, false
    @constant += coefficient * row.constant
    merge(row, coefficient, i) { |cell, entered| yield cell, entered }
  end

  # Yields every symbol in exactly one of this row and *other*, with `true` when it is in
  # this row.
  def each_difference(other : Row(T), & : Sym, Bool ->) : Nil
    other_symbols = other.symbols
    other_size = other.size
    i = j = 0
    while i < @size || j < other_size
      if j == other_size || (i < @size && @symbols[i].bits < other_symbols[j].bits)
        yield @symbols[i], true
        i += 1
      elsif i == @size || other_symbols[j].bits < @symbols[i].bits
        yield other_symbols[j], false
        j += 1
      else
        i += 1
        j += 1
      end
    end
  end

  def to_s(io : IO) : Nil
    io << @constant
    each { |symbol, coefficient| io << " + " << coefficient << " * " << symbol }
  end

  # Adds the cells of *row* times *coefficient* and drops the cell at index *skip*
  # (none if negative).
  #
  # Merges from the back into room reserved past the end until *row* runs out; cells
  # before that keep their place, and the merged tail moves down to follow them.
  #
  # Kept as one loop: it is the hottest path of every pivot.
  # ameba:disable Metrics/CyclomaticComplexity
  private def merge(row : Row(Float64), coefficient : T, skip : Int32, & : Sym, Bool ->) : Nil
    other_symbols = row.symbols
    other_coefficients = row.coefficients
    other_size = row.size
    if other_size == 0
      delete_at(skip) if skip >= 0
      return
    end

    first = search(other_symbols[0])
    first = ~first if first < 0
    first = skip if skip >= 0 && skip < first
    runs = @size - first > RUN_RATIO * other_size
    reserve(@size + other_size)
    symbols = @symbols
    coefficients = @coefficients
    i = @size - 1
    j = other_size - 1
    w = @size + other_size - 1

    while j >= 0
      bits = other_symbols[j].bits
      if runs
        # Moves the run of cells above this symbol in one go, leaving out *skip*.
        at_most = last_at_most(bits, first, i)
        if i > at_most
          if at_most < skip <= i
            w = move_run(skip + 1, i, w)
            w = move_run(at_most + 1, skip - 1, w)
          else
            w = move_run(at_most + 1, i, w)
          end
          i = at_most
        end
      else
        while i >= first && symbols[i].bits > bits
          unless i == skip
            symbols[w] = symbols[i]
            coefficients[w] = coefficients[i]
            w -= 1
          end
          i -= 1
        end
      end

      if i >= first && symbols[i].bits == bits
        symbol = symbols[i]
        value = coefficients[i] + coefficient * other_coefficients[j]
        if Row.near_zero?(value)
          yield symbol, false
        else
          symbols[w] = symbol
          coefficients[w] = value
          w -= 1
        end
        i -= 1
      else
        symbol = other_symbols[j]
        value = coefficient * other_coefficients[j]
        unless Row.near_zero?(value)
          symbols[w] = symbol
          coefficients[w] = value
          w -= 1
          yield symbol, true
        end
      end
      j -= 1
    end
    # Cells up to *i* keep their place; close the gap behind them.
    kept = i + 1
    if first <= skip <= i
      tail = i - skip
      (symbols + skip + 1).move_to(symbols + skip, tail)
      (coefficients + skip + 1).move_to(coefficients + skip, tail)
      kept = i
    end
    merged = @size + other_size - 1 - w
    if w + 1 > kept
      (symbols + w + 1).move_to(symbols + kept, merged)
      (coefficients + w + 1).move_to(coefficients + kept, merged)
    end
    @size = kept + merged
  end

  # Returns the last index in `low..high` whose symbol bits are at most *bits*, or
  # `low - 1`. Gallops down from *high*, so a short run above *bits* costs a few probes.
  private def last_at_most(bits : UInt32, low : Int32, high : Int32) : Int32
    step = 1
    top = high
    while top >= low && @symbols[top].bits > bits
      high = top - 1
      top -= step
      step <<= 1
    end
    return high if top >= low && top == high
    low = Math.max(low, top + 1)
    result = low - 1
    while low <= high
      mid = (low + high) >> 1
      if @symbols[mid].bits <= bits
        result = mid
        low = mid + 1
      else
        high = mid - 1
      end
    end
    result
  end

  # Moves the cells `from..to` so the last one lands at *w*, and returns the index below
  # the moved block.
  private def move_run(from : Int32, to : Int32, w : Int32) : Int32
    count = to - from + 1
    return w if count <= 0
    w -= count
    (@symbols + from).move_to(@symbols + w + 1, count)
    (@coefficients + from).move_to(@coefficients + w + 1, count)
    w
  end

  # Returns the index of *symbol*, or the bitwise complement of its insertion point.
  private def search(symbol : Sym) : Int32
    bits = symbol.bits
    low = 0
    high = @size - 1
    while low <= high
      mid = (low + high) >> 1
      mid_bits = @symbols[mid].bits
      if mid_bits < bits
        low = mid + 1
      elsif mid_bits > bits
        high = mid - 1
      else
        return mid
      end
    end
    ~low
  end

  private def reserve(needed : Int32) : Nil
    return if @capacity >= needed
    @capacity = Math.max(needed, Math.max(4, @capacity * 2))
    @symbols = Row.grow(@symbols, @capacity)
    @coefficients = Row.grow(@coefficients, @capacity)
  end

  # Resizes *buffer* to *capacity*. A fresh buffer comes from `Pointer.malloc`, which
  # allocates memory the GC does not scan, and `realloc` keeps that kind.
  protected def self.grow(buffer : Pointer(T), capacity : Int32) : Pointer(T) forall T
    buffer.null? ? Pointer(T).malloc(capacity) : buffer.realloc(capacity)
  end

  private def insert_at(i : Int32, symbol : Sym, coefficient : T) : Nil
    reserve(@size + 1)
    tail = @size - i
    if tail > 0
      (@symbols + i).move_to(@symbols + i + 1, tail)
      (@coefficients + i).move_to(@coefficients + i + 1, tail)
    end
    @symbols[i] = symbol
    @coefficients[i] = coefficient
    @size += 1
  end

  private def delete_at(i : Int32) : Nil
    tail = @size - i - 1
    if tail > 0
      (@symbols + i + 1).move_to(@symbols + i, tail)
      (@coefficients + i + 1).move_to(@coefficients + i, tail)
    end
    @size -= 1
  end
end
