# bench/solver.cr
require "./bench_helper"

Bench.group("building a #{Bench::BOXES}-box row layout") do |job|
  job.report("add #{Bench::BOXES * 3 + 1} constraints + update") do
    solver, lefts, _ = Bench.row_layout(Bench::BOXES)
    solver.update
    Bench.keep(lefts[-1].value)
  end
end

edit_solver, edit_lefts, edit_widths = Bench.row_layout(Bench::BOXES)
edit_solver.add_edit(edit_widths[0], :strong)
edit_solver.add_edit(edit_widths[1], :strong)
edit_value = 0

Bench.group("editing a #{Bench::BOXES}-box row layout") do |job|
  job.report("suggest + update") do
    edit_value = (edit_value + 7) % 300
    edit_solver.suggest(edit_widths[0], edit_value)
    edit_solver.update
    Bench.keep(edit_lefts[-1].value)
  end
  job.report("suggest 2 values + update") do
    edit_value = (edit_value + 7) % 300
    edit_solver.suggest({ {edit_widths[0], edit_value}, {edit_widths[1], edit_value} })
    edit_solver.update
    Bench.keep(edit_lefts[-1].value)
  end
end

churn_solver, churn_lefts, churn_widths = Bench.row_layout(Bench::BOXES)
middle = Bench::BOXES // 2

Bench.group("changing a #{Bench::BOXES}-box row layout") do |job|
  job.report("add + remove a strong constraint") do
    constraint = churn_solver.add((churn_widths[middle] == 30).strength(:strong))
    churn_solver.remove(constraint)
    churn_solver.update
  end
  job.report("add + remove a required constraint") do
    constraint = churn_solver.add(churn_lefts[middle] + churn_widths[middle] <= churn_lefts[middle + 1])
    churn_solver.remove(constraint)
    churn_solver.update
  end
  job.report("reject an unsatisfiable constraint") do
    begin
      churn_solver.add(churn_lefts[-1] >= Bench::BOXES * 40 + 1)
    rescue Cassowary::UnsatisfiableConstraint
    end
    churn_solver.update
  end
  job.report("add + remove a constraint on new variables") do
    a = Cassowary::Variable.new("a")
    constraint = churn_solver.add(a == churn_lefts[middle] + 1)
    churn_solver.remove(constraint)
    churn_solver.update
  end
end

Bench.keep(churn_lefts[-1].value)
