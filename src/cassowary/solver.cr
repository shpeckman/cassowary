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
  # Relative size below which an objective coefficient counts as rounding residue.
  private RESIDUE = 1.0e-12

  # Rows kept for reuse by the rollback journal.
  private SPARE_ROWS = 256

  @cns = Hash(Constraint, Tag).new
  @vars = Hash(UInt64, VarInfo).new
  @edits = Hash(UInt64, EditInfo).new

  # Indexed by symbol id; id 0 is `Sym::INVALID`.
  @symbols : Array(Sym) = [Sym::INVALID] of Sym
  @rows = [nil] of Row(Float64)?
  @columns = [nil] of SymSet?
  @markers = [nil] of Constraint?
  @free_ids = [] of UInt32

  @infeasible = [] of Sym
  @objective = Row(Cost).new(Cost::ZERO)
  @artificial : Row(Float64)? = nil
  @dirty = false

  # Rollback journal of a required constraint that may be rejected.
  @journaling = false
  @journal = [] of {Sym, Row(Float64)?}
  @journaled = [false]
  @created = [] of Sym
  @saved_objective = Row(Cost).new(Cost::ZERO)
  @spare_rows = [] of Row(Float64)

  # Adds *constraint* to the solver and returns it.
  #
  # Raises `DuplicateConstraint` if the constraint is already in the solver and
  # `UnsatisfiableConstraint` if it is required and conflicts with the required constraints.
  # A rejected constraint leaves the solver unchanged.
  def add(constraint : Constraint) : Constraint
    raise DuplicateConstraint.new(constraint) if @cns.has_key?(constraint)

    tag, row = create_row(constraint)
    subject = choose_subject(row, tag)
    conflicts = nil

    if subject.invalid? && row.all_symbols?(&.dummy?)
      if Row.near_zero?(row.constant)
        subject = tag.marker
      else
        conflicts = conflicts_in(row)
        recycle(row)
      end
    end

    unless conflicts
      if !subject.invalid?
        row.solve_for(subject)
        substitute(subject, row)
        put_row(subject, row)
      elsif tag.marker.slack?
        conflicts = add_infeasible_row(row, tag.marker)
      else
        conflicts = add_with_artificial_variable(row)
      end
    end

    if conflicts
      free_symbol(tag.marker)
      free_symbol(tag.other) unless tag.other.invalid?
      raise UnsatisfiableConstraint.new(constraint, conflicts)
    end

    @cns[constraint] = tag
    @markers[tag.marker.id] = constraint
    @markers[tag.other.id] = constraint unless tag.other.invalid?
    each_variable(constraint) { |variable| retain(variable) }
    @dirty = true
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
    free_symbol(tag.marker)
    drop_symbol(tag.other) unless tag.other.invalid?
    each_variable(constraint) { |variable| release(variable) }
    @dirty = true
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
    info = edit_info(variable)
    remove(info.constraint)
    @edits.delete(variable.object_id)
  end

  # Returns whether *variable* is an edit variable.
  def has_edit?(variable : Variable) : Bool
    @edits.has_key?(variable.object_id)
  end

  # Makes *variable* an edit variable with *strength* for the duration of the block, and
  # yields an `Edit` that steers it.
  #
  # Raises like `#add_edit`. The edit variable is removed when the block returns or
  # raises.
  #
  # ```
  # solver.edit(width) do |edit|
  #   edit.suggest(250)
  #   solver.update
  # end
  # ```
  def edit(variable : Variable, strength : Strength | Strength::Preset = Strength::STRONG, & : Edit ->) : Nil
    add_edit(variable, strength)
    begin
      yield Edit.new(self, variable)
    ensure
      remove_edit(variable) if has_edit?(variable)
    end
  end

  # Suggests *value* for the edit variable *variable*.
  #
  # Raises `UnknownEdit` if *variable* is not an edit variable.
  def suggest(variable : Variable, value : Number) : Nil
    info = edit_info(variable)
    optimize_objective
    shift(variable, info, value.to_f64)
    restore_feasibility
  end

  # Suggests a value for each edit variable in *values*, a collection of
  # `{variable, value}` pairs, at once.
  #
  # Raises `UnknownEdit`, before changing anything, if a variable is not an edit
  # variable.
  #
  # ```
  # solver.suggest([{width, 250}, {height, 100}])
  # ```
  def suggest(values : Enumerable({Variable, Number})) : Nil
    values.each { |variable, _| edit_info(variable) }
    optimize_objective
    values.each { |variable, value| shift(variable, edit_info(variable), value.to_f64) }
    restore_feasibility
  end

  # Writes the current solution into the value of every variable in the solver.
  def update : Nil
    update { }
  end

  # Writes the current solution into the value of every variable in the solver, and
  # yields each variable whose value changed.
  def update(& : Variable ->) : Nil
    optimize_objective
    @vars.each_value do |info|
      value = (@rows[info.symbol.id].try(&.constant) || 0.0) + 0.0 # normalizes -0.0
      variable = info.variable
      next if value == variable.value
      variable.value = value
      yield variable
    end
  end

  # Removes every constraint and edit variable.
  def reset : Nil
    @cns.clear
    @vars.clear
    @edits.clear
    @symbols = [Sym::INVALID] of Sym
    @rows = [nil] of Row(Float64)?
    @columns = [nil] of SymSet?
    @markers = [nil] of Constraint?
    @free_ids.clear
    @infeasible.clear
    @objective = Row(Cost).new(Cost::ZERO)
    @artificial = nil
    @dirty = false
    @journaled = [false]
  end

  # Writes the solver's internal state to *io*, for debugging.
  #
  # The format is not stable.
  def dump(io : IO) : Nil
    io << "Objective\n  " << @objective << '\n'
    io << "Tableau\n"
    each_row { |basic, row| io << "  " << basic << " = " << row << '\n' }
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

  private def edit_info(variable : Variable) : EditInfo
    @edits[variable.object_id]? || raise UnknownEdit.new(variable)
  end

  # Moves the edit constant of *variable* to *value*, queueing rows that turn infeasible.
  private def shift(variable : Variable, info : EditInfo, value : Float64) : Nil
    delta = value - info.constant
    @edits[variable.object_id] = info.with_constant(value)
    marker = info.tag.marker
    other = info.tag.other

    if row = @rows[marker.id]
      @infeasible << marker if row.add(-delta) < 0.0
    elsif row = @rows[other.id]
      @infeasible << other if row.add(delta) < 0.0
    else
      each_basic_with(marker) do |basic|
        r = row_of(basic)
        @infeasible << basic if r.add(delta * r.coefficient_for(marker)) < 0.0 && !basic.external?
      end
    end
  end

  private def restore_feasibility : Nil
    dual_optimize.try { raise InternalError.new("Dual optimize failed") }
  end

  private def optimize_objective : Nil
    return unless @dirty
    optimize(@objective)
    @dirty = false
  end

  # Returns a new symbol, reusing the id of a freed one if possible.
  private def new_symbol(kind : Sym::Kind) : Sym
    if id = @free_ids.pop?
      symbol = Sym.new(id, kind)
      @symbols[id] = symbol
    else
      id = @symbols.size.to_u32
      raise InternalError.new("Symbol ids exhausted") if id > Sym::MAX_ID
      symbol = Sym.new(id, kind)
      @symbols << symbol
      @rows << nil
      @columns << nil
      @markers << nil
      @journaled << false
    end
    @created << symbol if @journaling
    symbol
  end

  # Releases the id of *symbol*, which no row may hold.
  private def free_symbol(symbol : Sym) : Nil
    id = symbol.id
    @objective.remove(symbol)
    @symbols[id] = Sym::INVALID
    @markers[id] = nil
    @free_ids << id
  end

  # Removes *symbol* from the tableau and the objective, fixing it at zero, and frees it.
  private def drop_symbol(symbol : Sym) : Nil
    take_row(symbol).try { |row| recycle(row) }
    remove_column(symbol)
    free_symbol(symbol)
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

  # Forgets *variable* when no constraint uses it anymore. Its column should be empty
  # then; any rounding residue is cleared with it.
  private def release(variable : Variable) : Nil
    info = @vars[variable.object_id]
    if info.count > 1
      @vars[variable.object_id] = info.with_count(info.count - 1)
    else
      @vars.delete(variable.object_id)
      drop_symbol(info.symbol)
    end
  end

  private def row_of(basic : Sym) : Row(Float64)
    @rows[basic.id] || raise InternalError.new("Symbol #{basic} is not basic")
  end

  private def each_row(& : Sym, Row(Float64) ->) : Nil
    @rows.each_with_index { |row, id| yield @symbols[id], row if row }
  end

  # Stores *row* as the row of *basic* and indexes its symbols.
  private def put_row(basic : Sym, row : Row(Float64)) : Nil
    record(basic)
    @rows[basic.id] = row
    row.each_symbol { |symbol| column(symbol) << basic }
  end

  # Removes and returns the row of *basic*, if it is basic.
  private def take_row(basic : Sym) : Row(Float64)?
    record(basic)
    row = @rows[basic.id] || return
    @rows[basic.id] = nil
    row.each_symbol { |symbol| unindex(symbol, basic) }
    row
  end

  # Makes *entering* basic in place of *leaving*.
  private def pivot(leaving : Sym, entering : Sym) : Nil
    row = take_row(leaving).not_nil!
    row.solve_for(leaving, entering)
    substitute(entering, row)
    put_row(entering, row)
  end

  # Yields the basic symbol of every row that contains *symbol*.
  private def each_basic_with(symbol : Sym, & : Sym ->) : Nil
    @columns[symbol.id].try &.each { |basic| yield basic }
  end

  # Deletes the column of *symbol* from every row, fixing *symbol* at zero.
  private def remove_column(symbol : Sym) : Nil
    basics = @columns[symbol.id] || return
    basics.each do |basic|
      record(basic)
      row_of(basic).remove(symbol)
    end
    basics.clear
  end

  private def column(symbol : Sym) : SymSet
    @columns[symbol.id] ||= SymSet.new
  end

  private def unindex(symbol : Sym, basic : Sym) : Nil
    @columns[symbol.id].try &.delete(basic)
  end

  # Builds the tableau row for *constraint*, with every basic variable substituted out.
  private def create_row(constraint : Constraint) : {Tag, Row(Float64)}
    expression = constraint.expression
    strength = constraint.strength
    row = spare_row
    row.clear(expression.constant)

    expression.terms.each do |term|
      next if Row.near_zero?(term.coefficient)
      symbol = var_symbol(term.variable)
      if basic = @rows[symbol.id]
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
              @objective.insert(error, strength.cost)
              Tag.new(slack, error)
            end
          in .equal?
            if strength.required?
              dummy = new_symbol(:dummy)
              row.insert(dummy, 1.0)
              Tag.new(dummy)
            else
              plus = new_symbol(:error)
              minus = new_symbol(:error)
              row.insert(plus, -1.0)
              row.insert(minus, 1.0)
              @objective.insert(plus, strength.cost)
              @objective.insert(minus, strength.cost)
              Tag.new(plus, minus)
            end
          end

    row.reverse_sign if row.constant < 0.0
    {tag, row}
  end

  # Picks the symbol to solve a new row for, or `Sym::INVALID` if there is none that
  # keeps the tableau feasible.
  private def choose_subject(row : Row(Float64), tag : Tag) : Sym
    row.each_symbol { |symbol| return symbol if symbol.external? }
    return tag.marker if tag.marker.restricted? && row.coefficient_for(tag.marker) < 0.0
    return tag.other if tag.other.restricted? && row.coefficient_for(tag.other) < 0.0
    Sym::INVALID
  end

  # Substitutes out the symbols of *row* that became basic since it was built.
  private def resubstitute(row : Row(Float64)) : Nil
    while basic = row.find_symbol { |symbol| !@rows[symbol.id].nil? }
      row.substitute(basic, row_of(basic))
    end
    row.reverse_sign if row.constant < 0.0
  end

  # Adds the row of a required inequality whose slack *marker* would start out negative,
  # and restores feasibility with the dual simplex method. Returns the conflicting
  # constraints, after undoing the attempt, if the row cannot be satisfied.
  private def add_infeasible_row(row : Row(Float64), marker : Sym) : Array(Constraint)?
    if @dirty
      optimize_objective
      resubstitute(row)
    end
    begin_journal
    row.solve_for(marker)
    put_row(marker, row)
    @infeasible << marker
    if failed = dual_optimize
      conflicts = conflicts_in(row_of(failed), failed)
      rollback
      conflicts
    else
      commit
      nil
    end
  end

  # Adds *row* through an artificial variable. Returns the conflicting constraints,
  # after undoing the attempt, if the row cannot be satisfied.
  private def add_with_artificial_variable(row : Row(Float64)) : Array(Constraint)?
    begin_journal
    artificial_symbol = new_symbol(:slack)
    put_row(artificial_symbol, row)
    artificial = spare_row.copy_from(row)
    @artificial = artificial
    optimize(artificial)
    @artificial = nil

    if Row.near_zero?(artificial.constant) && pivot_out_artificial(artificial_symbol)
      commit
      drop_symbol(artificial_symbol)
      conflicts = nil
    else
      conflicts = conflicts_in(artificial)
      rollback
    end
    recycle(artificial)
    conflicts
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

  # Returns the required constraints whose markers appear in *row* or are *basic*.
  private def conflicts_in(row : Row(Float64), basic : Sym = Sym::INVALID) : Array(Constraint)
    conflicts = [] of Constraint
    collect = ->(symbol : Sym) do
      if (constraint = @markers[symbol.id]) && constraint.strength.required? && conflicts.none?(&.same?(constraint))
        conflicts << constraint
      end
    end
    collect.call(basic) unless basic.invalid?
    row.each_symbol { |symbol| collect.call(symbol) }
    conflicts
  end

  private def begin_journal : Nil
    @journaling = true
    @saved_objective.copy_from(@objective)
  end

  # Saves the row of *basic*, or its absence, the first time a journaled add changes it.
  private def record(basic : Sym) : Nil
    return unless @journaling
    id = basic.id
    return if @journaled[id]
    @journaled[id] = true
    @journal << {basic, @rows[id].try { |row| spare_row.copy_from(row) }}
  end

  # Keeps the changes and stops journaling.
  private def commit : Nil
    @journaling = false
    @journal.each do |basic, saved|
      @journaled[basic.id] = false
      saved.try { |row| recycle(row) }
    end
    @journal.clear
    @created.clear
  end

  # Restores every journaled row and the objective, frees the symbols created since the
  # journal began, and stops journaling.
  private def rollback : Nil
    @journaling = false
    @journal.each do |basic, saved|
      id = basic.id
      @journaled[id] = false
      current = @rows[id]
      if saved && current
        current.each_difference(saved) do |symbol, in_current|
          in_current ? unindex(symbol, basic) : column(symbol) << basic
        end
        @rows[id] = saved
        recycle(current)
      elsif saved
        put_row(basic, saved)
      elsif current
        take_row(basic)
        recycle(current)
      end
    end
    @journal.clear
    @objective, @saved_objective = @saved_objective, @objective
    @infeasible.clear
    @created.each { |symbol| free_symbol(symbol) }
    @created.clear
  end

  private def spare_row : Row(Float64)
    @spare_rows.pop? || Row(Float64).new(0.0)
  end

  private def recycle(row : Row(Float64)) : Nil
    @spare_rows << row if @spare_rows.size < SPARE_ROWS
  end

  # Eliminates *marker* from the tableau, dropping the one row that defines it.
  # Returns false if no row holds *marker*.
  private def remove_symbol(marker : Sym) : Bool
    if row = take_row(marker)
      recycle(row)
      return true
    end
    leaving = marker_leaving_symbol(marker) || return false
    row = take_row(leaving).not_nil!
    row.solve_for(leaving, marker)
    substitute(marker, row)
    recycle(row)
    true
  end

  # Replaces *symbol* with *row* everywhere in the tableau.
  private def substitute(symbol : Sym, row : Row(Float64)) : Nil
    if basics = @columns[symbol.id]
      basics.each do |basic|
        record(basic)
        r = row_of(basic)
        r.substitute(symbol, row) do |s, entered|
          next if s == symbol
          entered ? column(s) << basic : unindex(s, basic)
        end
        @infeasible << basic if !basic.external? && r.constant < 0.0 && !Row.near_zero?(r.constant)
      end
      basics.clear
    end
    @objective.substitute(symbol, row)
    @artificial.try(&.substitute(symbol, row))
  end

  # Minimizes *objective* with the primal simplex method.
  private def optimize(objective : Row(T)) : Nil forall T
    while entering = objective.entering_symbol
      leaving = nil
      best = Float64::MAX
      each_basic_with(entering) do |basic|
        next if basic.external?
        row = row_of(basic)
        coefficient = row.coefficient_for(entering)
        next unless coefficient < 0.0
        ratio = -row.constant / coefficient
        if ratio < best
          best = ratio
          leaving = basic
        end
      end

      if leaving
        pivot(leaving, entering)
      else
        # The objective is bounded below, so an unbounded direction can only come from a
        # coefficient that rounding left behind. Drop it if it is negligible.
        unless Row.magnitude(objective.coefficient_for(entering)) < RESIDUE * Math.max(1.0, objective.max_magnitude)
          raise InternalError.new("Objective function is unbounded")
        end
        objective.remove(entering)
      end
    end
  end

  # Restores feasibility with the dual simplex method. Returns the basic symbol of a row
  # that cannot be made feasible, or nil on success.
  private def dual_optimize : Sym?
    while leaving = @infeasible.pop?
      row = @rows[leaving.id]
      next unless row && row.constant < 0.0 && !Row.near_zero?(row.constant)

      entering = Sym::INVALID
      best = Cost::ZERO
      row.each do |symbol, coefficient|
        next unless coefficient > 0.0 && !symbol.dummy?
        ratio = @objective.coefficient_for(symbol) * (1.0 / coefficient)
        if entering.invalid? || ratio < best
          best = ratio
          entering = symbol
        end
      end

      if entering.invalid?
        @infeasible.clear
        return leaving
      end
      pivot(leaving, entering)
    end
    nil
  end

  # Removes the objective contribution of the error symbol *marker*.
  private def remove_marker_effects(marker : Sym, strength : Strength) : Nil
    if row = @rows[marker.id]
      @objective.insert(row, -strength.cost)
    else
      @objective.insert(marker, -strength.cost)
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
      row = row_of(basic)
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
