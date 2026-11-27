# src/cassowary/strength.cr

# The priority of a constraint.
#
# The solver satisfies every required constraint, then minimizes the violation of the
# strong components, then the medium ones, then the weak ones: no amount of violation at
# a lower level outweighs any violation at a higher level. Strengths compare the same
# way.
#
# ```
# Strength::STRONG > Strength.new(0, 1000, 1000) # => true
# Strength.new(0, 2, 0) > Strength::MEDIUM       # => true
# ```
struct Cassowary::Strength
  include Comparable(Strength)

  # The named strength levels; methods taking a `Strength` also accept these as symbols (`:strong`).
  enum Preset
    Required
    Strong
    Medium
    Weak

    # Returns the `Strength` this preset names.
    def strength : Strength
      case self
      in .required? then REQUIRED
      in .strong?   then STRONG
      in .medium?   then MEDIUM
      in .weak?     then WEAK
      end
    end
  end

  private LEVEL_MAX = 1000.0

  protected getter cost : Cost

  # Creates a strength from its *strong*, *medium* and *weak* components, each multiplied by *weight*.
  #
  # Each weighted component is clamped to `0..1000`.
  def initialize(strong : Number, medium : Number, weak : Number, weight : Number = 1.0)
    w = weight.to_f64
    @cost = Cost.new(
      (strong.to_f64 * w).clamp(0.0, LEVEL_MAX),
      (medium.to_f64 * w).clamp(0.0, LEVEL_MAX),
      (weak.to_f64 * w).clamp(0.0, LEVEL_MAX))
  end

  # A constraint the solver must satisfy.
  REQUIRED = new(1000, 1000, 1000)
  STRONG   = new(1, 0, 0)
  MEDIUM   = new(0, 1, 0)
  WEAK     = new(0, 0, 1)

  # Returns the weighted, clamped strong component.
  def strong : Float64
    @cost.strong
  end

  # Returns the weighted, clamped medium component.
  def medium : Float64
    @cost.medium
  end

  # Returns the weighted, clamped weak component.
  def weak : Float64
    @cost.weak
  end

  def required? : Bool
    @cost.strong >= LEVEL_MAX && @cost.medium >= LEVEL_MAX && @cost.weak >= LEVEL_MAX
  end

  def <=>(other : Strength) : Int32
    {@cost.strong, @cost.medium, @cost.weak} <=> {other.cost.strong, other.cost.medium, other.cost.weak} || 0
  end

  # Writes the preset name (`strong`) or the components (`Strength(0, 5, 0)`).
  def to_s(io : IO) : Nil
    if required?
      io << "required"
    elsif self == STRONG
      io << "strong"
    elsif self == MEDIUM
      io << "medium"
    elsif self == WEAK
      io << "weak"
    else
      io << "Strength("
      Expression.write_number(io, @cost.strong)
      io << ", "
      Expression.write_number(io, @cost.medium)
      io << ", "
      Expression.write_number(io, @cost.weak)
      io << ')'
    end
  end

  def inspect(io : IO) : Nil
    to_s(io)
  end
end
