# src/cassowary/symbol.cr

# A column of the simplex tableau. Named `Sym` to keep `::Symbol` unshadowed.
#
# Packed into one `UInt32` as `id << KIND_BITS | kind`, so symbols order by id.
private struct Cassowary::Sym
  include Comparable(Sym)

  enum Kind : UInt8
    Invalid
    External
    Slack
    Error
    Dummy
  end

  private KIND_BITS = 3
  private KIND_MASK = (1_u32 << KIND_BITS) - 1
  private PREFIXES  = {'i', 'v', 's', 'e', 'd'}

  MAX_ID  = UInt32::MAX >> KIND_BITS
  INVALID = new(0_u32, :invalid)

  getter bits : UInt32

  def initialize(id : UInt32, kind : Kind)
    @bits = (id << KIND_BITS) | kind.value
  end

  def id : UInt32
    @bits >> KIND_BITS
  end

  def kind : Kind
    Kind.new((@bits & KIND_MASK).to_u8)
  end

  def <=>(other : Sym) : Int32
    @bits <=> other.bits
  end

  def ==(other : Sym) : Bool
    @bits == other.bits
  end

  def hash(hasher)
    @bits.hash(hasher)
  end

  # Returns the id: ids are unique and dense, so they spread evenly over `Hash` buckets
  # and skip the cost of a general-purpose hasher.
  def hash : UInt64
    (@bits >> KIND_BITS).to_u64
  end

  def invalid? : Bool
    kind.invalid?
  end

  def external? : Bool
    kind.external?
  end

  def slack? : Bool
    kind.slack?
  end

  def error? : Bool
    kind.error?
  end

  def dummy? : Bool
    kind.dummy?
  end

  # Slack and error symbols are restricted to non-negative values.
  def restricted? : Bool
    kind.slack? || kind.error?
  end

  def to_s(io : IO) : Nil
    io << PREFIXES[kind.value] << id
  end
end
