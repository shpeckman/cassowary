# src/cassowary/number.cr

abstract struct Number
  # Returns the sum of this number and *other*.
  def +(other : Cassowary::Operand) : Cassowary::Expression
    other + self
  end

  # Returns the difference of this number and *other*.
  def -(other : Cassowary::Operand) : Cassowary::Expression
    -other + self
  end

  # Returns *other* multiplied by this number.
  def *(other : Cassowary::Operand) : Cassowary::Expression
    other * self
  end

  # Returns a required constraint that this number equals *other*.
  def ==(other : Cassowary::Operand) : Cassowary::Constraint
    other == self
  end

  # Fails to compile: an inequation is not a linear constraint. See `Cassowary::Operand#!=`.
  def !=(other : Cassowary::Operand) : NoReturn
    {% raise "Number#!= cannot build a constraint with a Cassowary::Operand" %}
  end

  # Returns a required constraint that this number is at most *other*.
  def <=(other : Cassowary::Operand) : Cassowary::Constraint
    other >= self
  end

  # Returns a required constraint that this number is at least *other*.
  def >=(other : Cassowary::Operand) : Cassowary::Constraint
    other <= self
  end
end
