# bench/cycles.cr
#
# Runs one fixed amount of work per scenario, so `bench/cycles.sh` can count its CPU
# cycles with `perf stat`. Cycle counts vary far less between runs than wall-clock time.
#
# Usage: cycles SCENARIO, where SCENARIO is one of SCENARIOS or "none" (setup only).

require "./bench_helper"

module Cycles
  SCENARIOS = %w[layout strong required reject suggest suggest2 suggest20]

  def self.run(scenario : String) : Nil
    solver, lefts, widths = Bench.row_layout(Bench::BOXES)
    solver.update

    case scenario
    when "none"
    when "layout"
      20.times do
        fresh, fresh_lefts, _ = Bench.row_layout(Bench::BOXES)
        fresh.update
        Bench.keep(fresh_lefts[-1].value)
      end
    when "strong"
      2000.times do
        constraint = solver.add((widths[100] == 30).strength(:strong))
        solver.remove(constraint)
        solver.update
      end
    when "required"
      2000.times do
        constraint = solver.add(lefts[100] + widths[100] <= lefts[101])
        solver.remove(constraint)
        solver.update
      end
    when "reject"
      2000.times do
        solver.add(lefts[-1] >= 8001)
      rescue Cassowary::UnsatisfiableConstraint
      end
    when "suggest"
      suggest(solver, widths, 1, 1000)
    when "suggest2"
      suggest(solver, widths, 2, 1000)
    when "suggest20"
      suggest(solver, widths, 20, 300)
    else
      abort "unknown scenario #{scenario}; one of none #{SCENARIOS.join(' ')}"
    end
    Bench.keep(lefts[-1].value)
  end

  # Moves *count* spread-out widths *rounds* times, updating after each round.
  def self.suggest(solver : Cassowary::Solver, widths : Array(Cassowary::Variable), count : Int32, rounds : Int32) : Nil
    edited = Array.new(count) { |i| widths[i * (widths.size // count)] }
    edited.each { |width| solver.add_edit(width, :strong) }
    value = 0
    rounds.times do
      value = (value + 7) % 300
      solver.suggest(edited.map_with_index { |width, i| {width, (value + i * 13) % 300} })
      solver.update
    end
  end
end

Cycles.run(ARGV[0]? || abort "usage: cycles SCENARIO")
