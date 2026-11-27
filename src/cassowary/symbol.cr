# src/cassowary/symbol.cr

# A column of the simplex tableau. Named `Sym` to keep `::Symbol` unshadowed.
private struct Cassowary::Sym
  enum Kind : UInt8
    Invalid
    External
    Slack
    Error
    Dummy
  end

  INVALID = new(0_u32, :invalid)

  getter id : UInt32
  getter kind : Kind

  def initialize(@id : UInt32, @kind : Kind)
  end

  def invalid? : Bool
    @kind.invalid?
  end

  def external? : Bool
    @kind.external?
  end

  def slack? : Bool
    @kind.slack?
  end

  def error? : Bool
    @kind.error?
  end

  def dummy? : Bool
    @kind.dummy?
  end

  # Slack and error symbols are restricted to non-negative values.
  def restricted? : Bool
    @kind.slack? || @kind.error?
  end
end
