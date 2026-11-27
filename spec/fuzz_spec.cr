# spec/fuzz_spec.cr
require "./spec_helper"

# Checks that every row's symbols are indexed under that row and nothing else is.
private def check_column_index(solver : Solver) : Nil
  cells = 0
  solver.@rows.each do |basic, row|
    row.each_symbol do |symbol|
      cells += 1
      solver.@columns[symbol].includes?(basic).should be_true
    end
  end
  solver.@columns.sum(&.[1].size).should eq(cells)
end

private def random_expression(random : Random, variables : Array(Variable)) : Expression
  terms = variables.sample(random.rand(1..3), random).map do |variable|
    Term.new(variable, random.rand(1..5) * (random.rand(2) == 0 ? 1 : -1))
  end
  Expression.new(terms)
end

describe "Solver fuzzing" do
  10.times do |seed|
    it "keeps required constraints satisfied (seed #{seed})" do
      random = Random.new(seed)
      variables = Array.new(8) { |i| Variable.new("v#{i}") }
      # Every required constraint holds at this point, so they stay satisfiable together.
      point = variables.map { random.rand(-100..100).to_f64 }
      value_at = ->(expression : Expression) do
        expression.terms.sum(expression.constant) { |t| t.coefficient * point[variables.index!(&.same?(t.variable))] }
      end

      solver = Solver.new
      required = [] of Constraint
      optional = [] of Constraint
      variables.each do |v|
        required << solver.add(v >= -1000)
        required << solver.add(v <= 1000)
      end

      300.times do
        case random.rand(10)
        when 0..2
          expression = random_expression(random, variables)
          at = value_at.call(expression)
          constraint = case random.rand(3)
                       when 0 then expression <= at + random.rand(0..20)
                       when 1 then expression >= at - random.rand(0..20)
                       else        expression == at
                       end
          required << solver.add(constraint)
        when 3..4
          strength = {Strength::Preset::Weak, Strength::Preset::Medium, Strength::Preset::Strong}.sample(random)
          optional << solver.add((variables.sample(random) == random.rand(-500..500)).strength(strength))
        when 5
          variable = variables.sample(random)
          bad = random.rand(2) == 0 ? variable >= 2000 : variable + variables.sample(random) * 0.5 <= -3000
          size = solver.@cns.size
          expect_raises(UnsatisfiableConstraint) { solver.add(bad) }
          solver.has?(bad).should be_false
          solver.@cns.size.should eq(size)
        when 6
          constraint = required.size > 16 ? required.delete_at(random.rand(16...required.size)) : nil
          solver.remove(constraint) if constraint
        when 7
          solver.remove(optional.delete_at(random.rand(optional.size))) unless optional.empty?
        when 8
          variable = variables.sample(random)
          solver.add_edit(variable, :strong) unless solver.has_edit?(variable)
          solver.suggest(variable, random.rand(-1500..1500))
        else
          variable = variables.sample(random)
          solver.remove_edit(variable) if solver.has_edit?(variable)
        end

        solver.update
        required.each { |c| c.violated?.should be_false }
        check_column_index(solver)
      end

      required.each { |c| solver.remove(c) }
      optional.each { |c| solver.remove(c) }
      variables.each { |v| solver.remove_edit(v) if solver.has_edit?(v) }
      solver.@rows.should be_empty
      solver.@columns.should be_empty
      solver.@vars.should be_empty
    end
  end
end
