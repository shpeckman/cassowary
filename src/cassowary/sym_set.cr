# src/cassowary/sym_set.cr

# A set of symbols stored inline in one buffer. Up to `LINEAR_LIMIT` members are kept
# packed and scanned; above that the buffer is an open-addressing table with linear
# probing and backward-shift deletion.
#
# `Sym::INVALID` marks an empty table cell, so it is never a member.
private class Cassowary::SymSet
  private LINEAR_LIMIT = 16

  getter size = 0
  @cells = Pointer(Sym).null
  @capacity = 0
  @shift = 32

  def empty? : Bool
    @size == 0
  end

  def includes?(symbol : Sym) : Bool
    if linear?
      @size.times { |i| return true if @cells[i] == symbol }
      return false
    end
    mask = @capacity - 1
    i = index(symbol)
    while (cell = @cells[i]) != Sym::INVALID
      return true if cell == symbol
      i = (i + 1) & mask
    end
    false
  end

  def <<(symbol : Sym) : self
    if linear?
      @size.times { |i| return self if @cells[i] == symbol }
      if @size < LINEAR_LIMIT
        @cells = Pointer(Sym).malloc(LINEAR_LIMIT) if @cells.null?
        @cells[@size] = symbol
        @size += 1
        return self
      end
      rehash(LINEAR_LIMIT * 4)
    elsif (@size + 1) * 4 > @capacity * 3
      rehash(@capacity * 2)
    end
    @size += 1 if place(symbol)
    self
  end

  def delete(symbol : Sym) : Nil
    if linear?
      @size.times do |i|
        next unless @cells[i] == symbol
        @size -= 1
        @cells[i] = @cells[@size]
        return
      end
      return
    end
    mask = @capacity - 1
    i = index(symbol)
    while (cell = @cells[i]) != symbol
      return if cell == Sym::INVALID
      i = (i + 1) & mask
    end
    # Moves later cells of the probe run into the hole when their home allows it.
    j = i
    loop do
      j = (j + 1) & mask
      cell = @cells[j]
      break if cell == Sym::INVALID
      home = index(cell)
      if ((j - home) & mask) >= ((j - i) & mask)
        @cells[i] = cell
        i = j
      end
    end
    @cells[i] = Sym::INVALID
    @size -= 1
  end

  def each(& : Sym ->) : Nil
    if linear?
      @size.times { |i| yield @cells[i] }
    else
      @capacity.times do |i|
        cell = @cells[i]
        yield cell unless cell == Sym::INVALID
      end
    end
  end

  def clear : Nil
    @cells.clear(@capacity) unless linear?
    @size = 0
  end

  private def linear? : Bool
    @capacity == 0
  end

  private def index(symbol : Sym) : Int32
    ((symbol.id &* 0x9E3779B1_u32) >> @shift).to_i32
  end

  # Stores *symbol* in the table; returns `false` when it was already there.
  private def place(symbol : Sym) : Bool
    mask = @capacity - 1
    i = index(symbol)
    while (cell = @cells[i]) != Sym::INVALID
      return false if cell == symbol
      i = (i + 1) & mask
    end
    @cells[i] = symbol
    true
  end

  private def rehash(capacity : Int32) : Nil
    old_cells = @cells
    old_capacity = linear? ? @size : @capacity
    @capacity = capacity
    @shift = 32 - capacity.trailing_zeros_count
    @cells = Pointer(Sym).malloc(capacity)
    old_capacity.times do |k|
      symbol = old_cells[k]
      place(symbol) unless symbol == Sym::INVALID
    end
  end
end
