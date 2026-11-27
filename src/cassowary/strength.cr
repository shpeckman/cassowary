# src/cassowary/strength.cr

# The priority of a constraint.
#
# The solver satisfies every required constraint, then minimizes the violation of the
# others. One unit of a level outweighs up to 999 units of the levels below it.
#
# ```
# Strength::STRONG > Strength.new(0, 999, 999) # => true
# Strength.new(0, 2, 0) > Strength::MEDIUM     # => true
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

  getter value : Float64

  # Creates a strength from its *strong*, *medium* and *weak* components, each multiplied by *weight*.
  #
  # Each weighted component is clamped to `0..1000`.
  def initialize(strong : Number, medium : Number, weak : Number, weight : Number = 1.0)
    w = weight.to_f64
    @value = (strong.to_f64 * w).clamp(0.0, LEVEL_MAX) * 1_000_000.0 +
             (medium.to_f64 * w).clamp(0.0, LEVEL_MAX) * 1_000.0 +
             (weak.to_f64 * w).clamp(0.0, LEVEL_MAX)
  end

  # A constraint the solver must satisfy.
  REQUIRED = new(1000, 1000, 1000)
  STRONG   = new(1, 0, 0)
  MEDIUM   = new(0, 1, 0)
  WEAK     = new(0, 0, 1)

  def required? : Bool
    @value >= REQUIRED.value
  end

  def <=>(other : Strength) : Int32
    @value <=> other.value || 0
  end

  def to_s(io : IO) : Nil
    io << @value
  end
end
