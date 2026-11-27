# spec/fuzz_spec.cr
require "./spec_helper"

# Checks that every row's symbols are indexed under that row and nothing else is.
private def check_column_index(solver : Solver) : Nil
  cells = 0
  solver.@rows.each_with_index do |row, id|
    next unless row
    basic = solver.@symbols[id]
    row.each_symbol do |symbol|
      cells += 1
      solver.@columns[symbol.id].try(&.includes?(basic)).should be_true
    end
  end
  solver.@columns.sum { |column| column.try(&.size) || 0 }.should eq(cells)
end

# Returns the total violation of each strength level, strong first.
private def violation_costs(constraints : Enumerable(Constraint)) : Array(Float64)
  costs = [0.0, 0.0, 0.0]
  constraints.each do |constraint|
    value = constraint.expression.value
    error = case constraint.operator
            in .equal?         then value.abs
            in .less_equal?    then Math.max(value, 0.0)
            in .greater_equal? then Math.max(-value, 0.0)
            end
    level = {Strength::STRONG, Strength::MEDIUM, Strength::WEAK}.index!(constraint.strength)
    costs[level] += error
  end
  costs
end

# Checks that *solver* reaches the same cost per strength level as a fresh solver given
# the same constraints in another order, up to rounding at coordinates near *bound*.
private def check_optimal(solver : Solver, random : Random, required : Array(Constraint),
                          optional : Array(Constraint), suggested : Hash(Variable, Float64), bound : Float64) : Nil
  edits = suggested.map { |variable, value| (variable == value).strength(:strong) }
  solver.update
  expected = violation_costs(optional + edits)

  fresh = Solver.new
  (required + optional + edits).shuffle(random).each do |constraint|
    fresh.add(Constraint.new(constraint.expression, constraint.operator, constraint.strength))
  end
  fresh.update
  actual = violation_costs(optional + edits)
  actual.zip(expected) { |a, e| a.should be_close(e, 1.0e-6 * (1.0 + e.abs) + 1.0e-12 * bound) }

  solver.update
end

# Checks that *explained* is a minimal conflict for *rejected* among *required*: the set
# alone rejects it, and without any one of its constraints it is accepted.
private def check_explained(explained : Array(Constraint), rejected : Constraint, required : Array(Constraint)) : Nil
  explained.should_not be_empty
  explained.each { |constraint| required.any?(&.same?(constraint)).should be_true }
  copy = ->(c : Constraint) { Constraint.new(c.expression, c.operator, c.strength) }
  expect_raises(UnsatisfiableConstraint) { Solver.new.add(explained.map(&copy) << copy.call(rejected)) }
  explained.each do |left_out|
    trial = Solver.new
    trial.add(explained.reject(&.same?(left_out)).map(&copy))
    trial.add(copy.call(rejected))
  end
end

# Number of seeds to fuzz; set FUZZ_SEEDS for a deeper run.
private FUZZ_SEEDS = (ENV["FUZZ_SEEDS"]? || "10").to_i

private def random_expression(random : Random, variables : Array(Variable)) : Expression
  terms = variables.sample(random.rand(1..3), random).map do |variable|
    Term.new(variable, random.rand(1..5) * (random.rand(2) == 0 ? 1 : -1))
  end
  Expression.new(terms)
end

# Magnitudes the fuzzed coordinates are scaled by.
private FUZZ_SCALES = {1.0, 1.0e4, 1.0e7}

describe "Solver fuzzing" do
  FUZZ_SCALES.each do |scale|
    FUZZ_SEEDS.times do |seed|
      it "keeps required constraints satisfied and the solution optimal (scale #{scale}, seed #{seed})" do
        random = Random.new(seed)
        variables = Array.new(8) { |i| Variable.new("v#{i}") }
        # Every required constraint holds at this point, so they stay satisfiable together.
        point = variables.map { random.rand(-100..100) * scale }
        value_at = ->(expression : Expression) do
          expression.terms.sum(expression.constant) { |term| term.coefficient * point[variables.index!(&.same?(term.variable))] }
        end

        bound = 1000 * scale
        solver = Solver.new
        required = [] of Constraint
        optional = [] of Constraint
        suggested = Hash(Variable, Float64).new.compare_by_identity
        variables.each do |v|
          required << solver.add(v >= -bound)
          required << solver.add(v <= bound)
        end

        300.times do |step|
          case random.rand(10)
          when 0..2
            expression = random_expression(random, variables)
            at = value_at.call(expression)
            constraint = case random.rand(3)
                         when 0 then expression <= at + random.rand(0..20) * scale
                         when 1 then expression >= at - random.rand(0..20) * scale
                         else        expression == at
                         end
            required << solver.add(constraint)
          when 3..4
            strength = {Strength::Preset::Weak, Strength::Preset::Medium, Strength::Preset::Strong}.sample(random)
            optional << solver.add((variables.sample(random) == random.rand(-500..500) * scale).strength(strength))
          when 5
            variable = variables.sample(random)
            bad = random.rand(2) == 0 ? variable >= 2000 * scale : variable + variables.sample(random) * 0.5 <= -3000 * scale
            size = solver.@cns.size
            expect_raises(UnsatisfiableConstraint) { solver.add(bad) }
            solver.has?(bad).should be_false
            solver.@cns.size.should eq(size)
            check_explained(solver.explain(bad), bad, required)
            solver.@cns.size.should eq(size)
          when 6
            constraint = required.size > 16 ? required.delete_at(random.rand(16...required.size)) : nil
            solver.remove(constraint) if constraint
          when 7
            solver.remove(optional.delete_at(random.rand(optional.size))) unless optional.empty?
          when 8
            variable = variables.sample(random)
            solver.add_edit(variable, :strong) unless solver.has_edit?(variable)
            value = random.rand(-1500..1500) * scale
            solver.suggest(variable, value)
            suggested[variable] = value
          else
            variable = variables.sample(random)
            if solver.has_edit?(variable)
              solver.remove_edit(variable)
              suggested.delete(variable)
            end
          end

          solver.update
          variables.each { |v| solver[v].should eq(v.value) }
          listed = solver.constraints
          listed.size.should eq(required.size + optional.size)
          (required + optional).each { |added| listed.any?(&.same?(added)).should be_true }
          # Rounding grows with the largest coordinate, not with each constraint's own terms.
          required.each { |held| (held.violated? && held.expression.value.abs > 1.0e-12 * bound).should be_false }
          check_column_index(solver)
          check_optimal(solver, random, required, optional, suggested, bound) if step % 25 == 24
        end

        required.each { |constraint| solver.remove(constraint) }
        optional.each { |constraint| solver.remove(constraint) }
        variables.each { |v| solver.remove_edit(v) if solver.has_edit?(v) }
        solver.@rows.all?(Nil).should be_true
        solver.@columns.all? { |column| column.nil? || column.empty? }.should be_true
        solver.@objective.empty?.should be_true
        solver.@vars.should be_empty
        solver.@free_ids.size.should eq(solver.@symbols.size - 1)
      end
    end
  end
end
