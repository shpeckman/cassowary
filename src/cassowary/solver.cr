# src/cassowary/solver.cr

# The markers of a constraint in the tableau.
private struct Cassowary::Tag
  getter marker : Sym
  getter other : Sym

  def initialize(@marker : Sym = Sym::INVALID, @other : Sym = Sym::INVALID)
  end
end

# The constraint behind an edit variable and its last suggested value.
private struct Cassowary::EditInfo
  getter tag : Tag
  getter constraint : Constraint
  getter constant : Float64

  def initialize(@tag : Tag, @constraint : Constraint, @constant : Float64 = 0.0)
  end

  def with_constant(constant : Float64) : EditInfo
    EditInfo.new(@tag, @constraint, constant)
  end
end

# An incremental solver for a system of linear constraints.
#
# Add and remove constraints at any time, steer edit variables with `#suggest`, and call
# `#update` to write the solution into the variables.
#
# ```
# x = Variable.new("x")
# solver = Solver.new
# solver.add(x >= 10)
# solver.add((x == 0).strength(:weak))
# solver.update
# x.value # => 10.0
# ```
class Cassowary::Solver
  @cns = Hash(Constraint, Tag).new
  @rows = Hash(Sym, Row).new
  @vars = Hash(UInt64, {Variable, Sym}).new
  @edits = Hash(UInt64, EditInfo).new
  @infeasible = [] of Sym
  @objective = Row.new
  @artificial : Row? = nil
  @id_tick = 1_u32

  # Adds *constraint* to the solver and returns it.
  #
  # Raises `DuplicateConstraint` if the constraint is already in the solver and
  # `UnsatisfiableConstraint` if it is required and conflicts with the required constraints.
  def add(constraint : Constraint) : Constraint
    raise DuplicateConstraint.new(constraint) if @cns.has_key?(constraint)

    tag, row = create_row(constraint)
    subject = choose_subject(row, tag)

    if subject.invalid? && row.cells.each_key.all?(&.dummy?)
      raise UnsatisfiableConstraint.new(constraint) unless Row.near_zero?(row.constant)
      subject = tag.marker
    end

    if subject.invalid?
      raise UnsatisfiableConstraint.new(constraint) unless add_with_artificial_variable(row)
    else
      row.solve_for(subject)
      substitute(subject, row)
      @rows[subject] = row
    end

    @cns[constraint] = tag
    optimize(@objective)
    constraint
  end

  # Removes *constraint* from the solver.
  #
  # Raises `UnknownConstraint` if the constraint is not in the solver.
  def remove(constraint : Constraint) : Nil
    tag = @cns.delete(constraint) || raise UnknownConstraint.new(constraint)

    remove_marker_effects(tag.marker, constraint.strength) if tag.marker.error?
    remove_marker_effects(tag.other, constraint.strength) if tag.other.error?

    unless @rows.delete(tag.marker)
      leaving = marker_leaving_symbol(tag.marker) || raise InternalError.new("Failed to find leaving row")
      row = @rows.delete(leaving).not_nil!
      row.solve_for(leaving, tag.marker)
      substitute(tag.marker, row)
    end

    optimize(@objective)
  end

  # Returns whether *constraint* is in the solver.
  def has?(constraint : Constraint) : Bool
    @cns.has_key?(constraint)
  end

  # Makes *variable* an edit variable with *strength*, so `#suggest` can steer it.
  #
  # Raises `DuplicateEdit` if *variable* is already an edit variable and
  # `BadRequiredStrength` if *strength* is required.
  def add_edit(variable : Variable, strength : Strength | Strength::Preset = Strength::STRONG) : Nil
    strength = strength.strength if strength.is_a?(Strength::Preset)
    raise DuplicateEdit.new(variable) if @edits.has_key?(variable.object_id)
    raise BadRequiredStrength.new(variable) if strength.required?

    constraint = Constraint.new(variable.to_expression, :equal, strength)
    add(constraint)
    @edits[variable.object_id] = EditInfo.new(@cns[constraint], constraint)
  end

  # Stops *variable* from being an edit variable.
  #
  # Raises `UnknownEdit` if *variable* is not an edit variable.
  def remove_edit(variable : Variable) : Nil
    info = @edits[variable.object_id]? || raise UnknownEdit.new(variable)
    remove(info.constraint)
    @edits.delete(variable.object_id)
  end

  # Returns whether *variable* is an edit variable.
  def has_edit?(variable : Variable) : Bool
    @edits.has_key?(variable.object_id)
  end

  # Suggests *value* for the edit variable *variable*.
  #
  # Raises `UnknownEdit` if *variable* is not an edit variable.
  def suggest(variable : Variable, value : Number) : Nil
    info = @edits[variable.object_id]? || raise UnknownEdit.new(variable)
    value = value.to_f64
    delta = value - info.constant
    @edits[variable.object_id] = info.with_constant(value)
    marker = info.tag.marker
    other = info.tag.other

    if row = @rows[marker]?
      @infeasible << marker if row.add(-delta) < 0.0
    elsif row = @rows[other]?
      @infeasible << other if row.add(delta) < 0.0
    else
      @rows.each do |symbol, r|
        coefficient = r.coefficient_for(marker)
        next if coefficient == 0.0
        @infeasible << symbol if r.add(delta * coefficient) < 0.0 && !symbol.external?
      end
    end

    dual_optimize
  end

  # Writes the current solution into the value of every variable in the solver.
  def update : Nil
    @vars.each_value do |variable, symbol|
      variable.value = (@rows[symbol]?.try(&.constant) || 0.0) + 0.0 # normalizes -0.0
    end
  end

  # Removes every constraint and edit variable.
  def reset : Nil
    @cns.clear
    @rows.clear
    @vars.clear
    @edits.clear
    @infeasible.clear
    @objective = Row.new
    @artificial = nil
    @id_tick = 1_u32
  end

  private def new_symbol(kind : Sym::Kind) : Sym
    symbol = Sym.new(@id_tick, kind)
    @id_tick += 1
    symbol
  end

  private def var_symbol(variable : Variable) : Sym
    if entry = @vars[variable.object_id]?
      entry[1]
    else
      symbol = new_symbol(:external)
      @vars[variable.object_id] = {variable, symbol}
      symbol
    end
  end

  # Builds the tableau row for *constraint*, with every basic variable substituted out.
  private def create_row(constraint : Constraint) : {Tag, Row}
    expression = constraint.expression
    strength = constraint.strength
    row = Row.new(expression.constant)

    expression.terms.each do |term|
      next if Row.near_zero?(term.coefficient)
      symbol = var_symbol(term.variable)
      if basic = @rows[symbol]?
        row.insert(basic, term.coefficient)
      else
        row.insert(symbol, term.coefficient)
      end
    end

    tag = case constraint.operator
          in .less_equal?, .greater_equal?
            coefficient = constraint.operator.less_equal? ? 1.0 : -1.0
            slack = new_symbol(:slack)
            row.insert(slack, coefficient)
            if strength.required?
              Tag.new(slack)
            else
              error = new_symbol(:error)
              row.insert(error, -coefficient)
              @objective.insert(error, strength.value)
              Tag.new(slack, error)
            end
          in .equal?
            if strength.required?
              dummy = new_symbol(:dummy)
              row.insert(dummy)
              Tag.new(dummy)
            else
              plus = new_symbol(:error)
              minus = new_symbol(:error)
              row.insert(plus, -1.0)
              row.insert(minus, 1.0)
              @objective.insert(plus, strength.value)
              @objective.insert(minus, strength.value)
              Tag.new(plus, minus)
            end
          end

    row.reverse_sign if row.constant < 0.0
    {tag, row}
  end

  # Picks the symbol to solve a new row for, or `Sym::INVALID` if an artificial variable is needed.
  private def choose_subject(row : Row, tag : Tag) : Sym
    row.cells.each_key { |symbol| return symbol if symbol.external? }
    return tag.marker if tag.marker.restricted? && row.coefficient_for(tag.marker) < 0.0
    return tag.other if tag.other.restricted? && row.coefficient_for(tag.other) < 0.0
    Sym::INVALID
  end

  # Adds *row* through an artificial variable; returns false and restores the tableau
  # if the row cannot be satisfied.
  private def add_with_artificial_variable(row : Row) : Bool
    saved_rows = @rows.transform_values(&.copy)
    saved_objective = @objective.copy

    artificial_symbol = new_symbol(:slack)
    @rows[artificial_symbol] = row.copy
    artificial = row.copy
    @artificial = artificial
    optimize(artificial)
    success = Row.near_zero?(artificial.constant)
    @artificial = nil

    if success
      if basic = @rows.delete(artificial_symbol)
        unless basic.cells.empty?
          entering = basic.cells.each_key.find(&.restricted?)
          if entering
            basic.solve_for(artificial_symbol, entering)
            substitute(entering, basic)
            @rows[entering] = basic
          else
            success = false
          end
        end
      end
    end

    if success
      @rows.each_value(&.remove(artificial_symbol))
      @objective.remove(artificial_symbol)
    else
      @rows = saved_rows
      @objective = saved_objective
      @infeasible.clear
    end
    success
  end

  # Replaces *symbol* with *row* everywhere in the tableau.
  private def substitute(symbol : Sym, row : Row) : Nil
    @rows.each do |basic, r|
      r.substitute(symbol, row)
      @infeasible << basic if !basic.external? && r.constant < 0.0
    end
    @objective.substitute(symbol, row)
    @artificial.try(&.substitute(symbol, row))
  end

  # Minimizes *objective* with the primal simplex method.
  private def optimize(objective : Row) : Nil
    loop do
      entering = objective.cells.each.find { |symbol, c| !symbol.dummy? && c < 0.0 }
      return unless entering
      entering = entering[0]

      leaving = nil
      best = Float64::MAX
      @rows.each do |symbol, r|
        next if symbol.external?
        coefficient = r.coefficient_for(entering)
        next unless coefficient < 0.0
        ratio = -r.constant / coefficient
        if ratio < best
          best = ratio
          leaving = symbol
        end
      end
      raise InternalError.new("Objective function is unbounded") unless leaving

      row = @rows.delete(leaving).not_nil!
      row.solve_for(leaving, entering)
      substitute(entering, row)
      @rows[entering] = row
    end
  end

  # Restores feasibility after `#suggest` with the dual simplex method.
  private def dual_optimize : Nil
    while leaving = @infeasible.pop?
      row = @rows[leaving]?
      next unless row && !Row.near_zero?(row.constant) && row.constant < 0.0

      entering = Sym::INVALID
      best = Float64::MAX
      row.cells.each do |symbol, coefficient|
        next unless coefficient > 0.0 && !symbol.dummy?
        ratio = @objective.coefficient_for(symbol) / coefficient
        if ratio < best
          best = ratio
          entering = symbol
        end
      end
      raise InternalError.new("Dual optimize failed") if entering.invalid?

      @rows.delete(leaving)
      row.solve_for(leaving, entering)
      substitute(entering, row)
      @rows[entering] = row
    end
  end

  # Removes the objective contribution of the error symbol *marker*.
  private def remove_marker_effects(marker : Sym, strength : Strength) : Nil
    if row = @rows[marker]?
      @objective.insert(row, -strength.value)
    else
      @objective.insert(marker, -strength.value)
    end
  end

  # Picks the row to pivot *marker* into when removing its constraint.
  private def marker_leaving_symbol(marker : Sym) : Sym?
    first = second = third = nil
    ratio1 = ratio2 = Float64::MAX
    @rows.each do |symbol, row|
      coefficient = row.coefficient_for(marker)
      next if coefficient == 0.0
      if symbol.external?
        third = symbol
      elsif coefficient < 0.0
        ratio = -row.constant / coefficient
        if ratio < ratio1
          ratio1 = ratio
          first = symbol
        end
      else
        ratio = row.constant / coefficient
        if ratio < ratio2
          ratio2 = ratio
          second = symbol
        end
      end
    end
    first || second || third
  end
end
