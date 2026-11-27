# src/cassowary/cost.cr

# A cost with one component per strength level, compared lexicographically: any amount
# of a higher level outweighs every amount of the levels below it.
private struct Cassowary::Cost
  getter strong : Float64
  getter medium : Float64
  getter weak : Float64

  ZERO = new(0.0, 0.0, 0.0)

  def initialize(@strong : Float64, @medium : Float64, @weak : Float64)
  end

  def +(other : Cost) : Cost
    Cost.new(@strong + other.strong, @medium + other.medium, @weak + other.weak)
  end

  def *(other : Float64) : Cost
    Cost.new(@strong * other, @medium * other, @weak * other)
  end

  def - : Cost
    Cost.new(-@strong, -@medium, -@weak)
  end

  def near_zero? : Bool
    Row.near_zero?(@strong) && Row.near_zero?(@medium) && Row.near_zero?(@weak)
  end

  # Returns whether the first component that is not near zero is negative.
  def negative? : Bool
    sign < 0
  end

  # Returns -1, 0 or 1 by the first component that is not near zero.
  def sign : Int32
    {@strong, @medium, @weak}.each do |level|
      next if Row.near_zero?(level)
      return level < 0.0 ? -1 : 1
    end
    0
  end

  # Returns whether this cost is lexicographically below *other*, ignoring differences
  # near zero.
  def <(other : Cost) : Bool
    (self + -other).negative?
  end

  # Returns the largest absolute component.
  def magnitude : Float64
    Math.max(@strong.abs, Math.max(@medium.abs, @weak.abs))
  end

  def to_s(io : IO) : Nil
    io << '(' << @strong << ", " << @medium << ", " << @weak << ')'
  end
end
