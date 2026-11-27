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

# A variable known to the solver, its column and the number of constraints using it.
private struct Cassowary::VarInfo
  getter variable : Variable
  getter symbol : Sym
  getter count : Int32

  def initialize(@variable : Variable, @symbol : Sym, @count : Int32 = 0)
  end

  def with_count(count : Int32) : VarInfo
    VarInfo.new(@variable, @symbol, count)
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
  @columns = Hash(Sym, Set(Sym)).new
  @vars = Hash(UInt64, VarInfo).new
  @edits = Hash(UInt64, EditInfo).new
  @infeasible = [] of Sym
  @objective = Row.new
  @artificial : Row? = nil
  @journal : Hash(Sym, Row?)? = nil
  @id_tick = 1_u32

  # Relative size below which an objective coefficient counts as rounding residue.
  private RESIDUE = 1.0e-12

  # Adds *constraint* to the solver and returns it.
  #
  # Raises `DuplicateConstraint` if the constraint is already in the solver and
  # `UnsatisfiableConstraint` if it is required and conflicts with the required constraints.
  # A rejected constraint leaves the solver unchanged.
  def add(constraint : Constraint) : Constraint
    raise DuplicateConstraint.new(constraint) if @cns.has_key?(constraint)

    tag, row = create_row(constraint)
    subject = choose_subject(row, tag)

    if subject.invalid? && row.all_symbols?(&.dummy?)
      raise UnsatisfiableConstraint.new(constraint) unless Row.near_zero?(row.constant)
      subject = tag.marker
    end

    if subject.invalid?
      raise UnsatisfiableConstraint.new(constraint) unless add_with_artificial_variable(row)
    else
      row.solve_for(subject)
      substitute(subject, row)
      put_row(subject, row)
    end

    @cns[constraint] = tag
    each_variable(constraint) { |variable| retain(variable) }
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
    remove_symbol(tag.marker) || raise InternalError.new("Failed to find leaving row")
    each_variable(constraint) { |variable| release(variable) }

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
      each_basic_with(marker) do |basic|
        r = @rows[basic]
        @infeasible << basic if r.add(delta * r.coefficient_for(marker)) < 0.0 && !basic.external?
      end
    end

    dual_optimize
  end

  # Writes the current solution into the value of every variable in the solver.
  def update : Nil
    @vars.each_value do |info|
      info.variable.value = (@rows[info.symbol]?.try(&.constant) || 0.0) + 0.0 # normalizes -0.0
    end
  end

  # Removes every constraint and edit variable.
  def reset : Nil
    @cns.clear
    @rows.clear
    @columns.clear
    @vars.clear
    @edits.clear
    @infeasible.clear
    @objective = Row.new
    @artificial = nil
    @id_tick = 1_u32
  end

  # Writes the solver's internal state to *io*, for debugging.
  #
  # The format is not stable.
  def dump(io : IO) : Nil
    io << "Objective\n  " << @objective << '\n'
    io << "Tableau\n"
    @rows.each { |basic, row| io << "  " << basic << " = " << row << '\n' }
    io << "Infeasible\n"
    @infeasible.each { |symbol| io << "  " << symbol << '\n' }
    io << "Variables\n"
    @vars.each_value do |info|
      io << "  " << info.variable.name << ": " << info.symbol << ", used by " << info.count << '\n'
    end
    io << "Edit variables\n"
    @edits.each { |id, info| io << "  " << @vars[id].variable.name << " = " << info.constant << '\n' }
    io << "Constraints\n"
    @cns.each { |constraint, tag| io << "  " << constraint << " | " << tag.marker << ' ' << tag.other << '\n' }
  end

  # :ditto:
  def dump : String
    String.build { |io| dump(io) }
  end

  private def new_symbol(kind : Sym::Kind) : Sym
    raise InternalError.new("Symbol ids exhausted") if @id_tick > Sym::MAX_ID
    symbol = Sym.new(@id_tick, kind)
    @id_tick += 1
    symbol
  end

  private def var_symbol(variable : Variable) : Sym
    if info = @vars[variable.object_id]?
      info.symbol
    else
      symbol = new_symbol(:external)
      @vars[variable.object_id] = VarInfo.new(variable, symbol)
      symbol
    end
  end

  # Yields each variable of *constraint* that has a column in the tableau.
  private def each_variable(constraint : Constraint, & : Variable ->) : Nil
    constraint.expression.terms.each do |term|
      yield term.variable unless Row.near_zero?(term.coefficient)
    end
  end

  private def retain(variable : Variable) : Nil
    @vars.update(variable.object_id) { |info| info.with_count(info.count + 1) }
  end

  private def release(variable : Variable) : Nil
    info = @vars[variable.object_id]
    if info.count > 1
      @vars[variable.object_id] = info.with_count(info.count - 1)
    else
      drop_variable(info)
    end
  end

  # Forgets a variable no constraint uses. Its column should already be empty;
  # any rounding residue is cleared with it, including in the objective.
  private def drop_variable(info : VarInfo) : Nil
    @vars.delete(info.variable.object_id)
    symbol = info.symbol
    take_row(symbol)
    remove_column(symbol)
    @objective.remove(symbol)
  end

  # Stores *row* as the row of *basic* and indexes its symbols.
  private def put_row(basic : Sym, row : Row) : Nil
    record(basic)
    @rows[basic] = row
    row.each_symbol { |symbol| column(symbol) << basic }
  end

  # Removes and returns the row of *basic*, if it is basic.
  private def take_row(basic : Sym) : Row?
    record(basic)
    row = @rows.delete(basic) || return
    row.each_symbol { |symbol| unindex(symbol, basic) }
    row
  end

  # Yields the basic symbol of every row that contains *symbol*.
  private def each_basic_with(symbol : Sym, & : Sym ->) : Nil
    if basics = @columns[symbol]?
      basics.each { |basic| yield basic }
    end
  end

  # Deletes the column of *symbol* from every row, fixing *symbol* at zero.
  private def remove_column(symbol : Sym) : Nil
    if basics = @columns.delete(symbol)
      basics.each do |basic|
        record(basic)
        @rows[basic].remove(symbol)
      end
    end
  end

  private def column(symbol : Sym) : Set(Sym)
    @columns.put_if_absent(symbol) { Set(Sym).new }
  end

  private def unindex(symbol : Sym, basic : Sym) : Nil
    if basics = @columns[symbol]?
      basics.delete(basic)
      @columns.delete(symbol) if basics.empty?
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
    row.each_symbol { |symbol| return symbol if symbol.external? }
    return tag.marker if tag.marker.restricted? && row.coefficient_for(tag.marker) < 0.0
    return tag.other if tag.other.restricted? && row.coefficient_for(tag.other) < 0.0
    Sym::INVALID
  end

  # Adds *row* through an artificial variable. If the row cannot be satisfied, restores
  # the rows the attempt changed and the objective, and returns false.
  private def add_with_artificial_variable(row : Row) : Bool
    @journal = Hash(Sym, Row?).new
    objective = @objective.copy
    artificial_symbol = new_symbol(:slack)
    put_row(artificial_symbol, row.copy)
    artificial = row.copy
    @artificial = artificial
    optimize(artificial)
    @artificial = nil

    if Row.near_zero?(artificial.constant) && pivot_out_artificial(artificial_symbol)
      @journal = nil
      remove_column(artificial_symbol)
      @objective.remove(artificial_symbol)
      true
    else
      rollback(objective)
      false
    end
  end

  # Makes *artificial_symbol* parametric so it can be dropped. Returns false if its row
  # has no restricted symbol to pivot in.
  private def pivot_out_artificial(artificial_symbol : Sym) : Bool
    basic = take_row(artificial_symbol) || return true
    return true if basic.empty?
    entering = basic.find_symbol(&.restricted?) || return false
    basic.solve_for(artificial_symbol, entering)
    substitute(entering, basic)
    put_row(entering, basic)
    true
  end

  # Restores every journaled row and *objective*, and stops journaling.
  private def rollback(objective : Row) : Nil
    journal = @journal.not_nil!
    @journal = nil
    journal.each do |basic, saved|
      current = @rows[basic]?
      if saved && current
        current.each_difference(saved) do |symbol, in_current|
          in_current ? unindex(symbol, basic) : column(symbol) << basic
        end
        @rows[basic] = saved
      elsif saved
        put_row(basic, saved)
      else
        take_row(basic)
      end
    end
    @objective = objective
    @infeasible.clear
  end

  # Saves the row of *basic*, or its absence, the first time a rejectable add changes it.
  private def record(basic : Sym) : Nil
    if journal = @journal
      journal.put_if_absent(basic) { @rows[basic]?.try(&.copy) }
    end
  end

  # Eliminates *marker* from the tableau, dropping the one row that defines it.
  # Returns false if no row holds *marker*.
  private def remove_symbol(marker : Sym) : Bool
    return true if take_row(marker)
    leaving = marker_leaving_symbol(marker) || return false
    row = take_row(leaving).not_nil!
    row.solve_for(leaving, marker)
    substitute(marker, row)
    true
  end

  # Replaces *symbol* with *row* everywhere in the tableau.
  private def substitute(symbol : Sym, row : Row) : Nil
    if basics = @columns.delete(symbol)
      basics.each do |basic|
        record(basic)
        r = @rows[basic]
        r.substitute(symbol, row) do |s, entered|
          entered ? column(s) << basic : unindex(s, basic)
        end
        @infeasible << basic if !basic.external? && r.constant < 0.0 && !Row.near_zero?(r.constant)
      end
    end
    @objective.substitute(symbol, row)
    @artificial.try(&.substitute(symbol, row))
  end

  # Minimizes *objective* with the primal simplex method.
  private def optimize(objective : Row) : Nil
    while entering = entering_symbol(objective)
      leaving = nil
      best = Float64::MAX
      each_basic_with(entering) do |basic|
        next if basic.external?
        coefficient = @rows[basic].coefficient_for(entering)
        next unless coefficient < 0.0
        ratio = -@rows[basic].constant / coefficient
        if ratio < best
          best = ratio
          leaving = basic
        end
      end
      unless leaving
        # The objective is bounded below, so an unbounded direction can only come from a
        # coefficient that rounding left behind. Drop it if it is negligible.
        unless objective.coefficient_for(entering).abs < RESIDUE * Math.max(1.0, objective.max_magnitude)
          raise InternalError.new("Objective function is unbounded")
        end
        objective.remove(entering)
        next
      end

      row = take_row(leaving).not_nil!
      row.solve_for(leaving, entering)
      substitute(entering, row)
      put_row(entering, row)
    end
  end

  # Returns the first symbol whose increase lowers *objective*.
  private def entering_symbol(objective : Row) : Sym?
    objective.each { |symbol, coefficient| return symbol if !symbol.dummy? && coefficient < 0.0 }
    nil
  end

  # Restores feasibility after `#suggest` with the dual simplex method.
  private def dual_optimize : Nil
    while leaving = @infeasible.pop?
      row = @rows[leaving]?
      next unless row && !Row.near_zero?(row.constant) && row.constant < 0.0

      entering = Sym::INVALID
      best = Float64::MAX
      row.each do |symbol, coefficient|
        next unless coefficient > 0.0 && !symbol.dummy?
        ratio = @objective.coefficient_for(symbol) / coefficient
        if ratio < best
          best = ratio
          entering = symbol
        end
      end
      raise InternalError.new("Dual optimize failed") if entering.invalid?

      take_row(leaving)
      row.solve_for(leaving, entering)
      substitute(entering, row)
      put_row(entering, row)
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

  # Picks the row to pivot *marker* into when removing it.
  #
  # A basic dummy belongs to a redundant required equality and must stay at zero, so its
  # row wins outright: its constant is zero, so the pivot moves no other value, and the
  # redundant equality takes over from the removed one.
  private def marker_leaving_symbol(marker : Sym) : Sym?
    first = second = third = nil
    ratio1 = ratio2 = Float64::MAX
    each_basic_with(marker) do |basic|
      return basic if basic.dummy?
      row = @rows[basic]
      coefficient = row.coefficient_for(marker)
      if basic.external?
        third = basic
      elsif coefficient < 0.0
        ratio = -row.constant / coefficient
        if ratio < ratio1
          ratio1 = ratio
          first = basic
        end
      else
        ratio = row.constant / coefficient
        if ratio < ratio2
          ratio2 = ratio
          second = basic
        end
      end
    end
    first || second || third
  end
end
