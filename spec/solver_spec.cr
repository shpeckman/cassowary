# spec/solver_spec.cr
require "./spec_helper"

describe Solver do
  it "solves required constraints" do
    x = Variable.new("x")
    y = Variable.new("y")
    solver = Solver.new
    solver.add(x == 20)
    solver.add(x + 2 == y + 10)
    solver.update
    x.value.should eq(20.0)
    y.value.should eq(12.0)
  end

  it "trades off non-required constraints by strength" do
    x = Variable.new("x")
    solver = Solver.new
    solver.add((x == 10).strength(:weak))
    solver.add((x == 20).strength(:strong))
    solver.update
    x.value.should eq(20.0)
  end

  it "satisfies inequalities" do
    x = Variable.new("x")
    solver = Solver.new
    solver.add(x >= 10)
    solver.add((x == 0).strength(:weak))
    solver.update
    x.value.should eq(10.0)
  end

  it "lays out a box with edit variables" do
    left = Variable.new("left")
    width = Variable.new("width")
    right = Variable.new("right")
    solver = Solver.new
    solver.add(right == left + width)
    solver.add(width >= 100)
    solver.add((left == 0).strength(:strong))
    solver.add_edit(width, :strong)

    solver.suggest(width, 250)
    solver.update
    left.value.should eq(0.0)
    right.value.should eq(250.0)

    solver.suggest(width, 50)
    solver.update
    width.value.should eq(100.0)
    right.value.should eq(100.0)
  end

  it "keeps a centered layout while suggesting" do
    left = Variable.new("left")
    right = Variable.new("right")
    mid = Variable.new("mid")
    solver = Solver.new
    solver.add(mid == (left + right) / 2)
    solver.add(right == left + 10)
    solver.add(right <= 100)
    solver.add(left >= 0)
    solver.add_edit(mid, :strong)

    solver.suggest(mid, 30)
    solver.update
    left.value.should eq(25.0)
    right.value.should eq(35.0)

    solver.suggest(mid, 200)
    solver.update
    right.value.should eq(100.0)
    left.value.should eq(90.0)
  end

  it "removes constraints" do
    x = Variable.new("x")
    solver = Solver.new
    solver.add((x == 10).strength(:weak))
    strong = solver.add((x == 20).strength(:strong))
    solver.has?(strong).should be_true
    solver.remove(strong)
    solver.has?(strong).should be_false
    solver.update
    x.value.should eq(10.0)
  end

  it "removes required inequalities" do
    x = Variable.new("x")
    solver = Solver.new
    solver.add((x == 0).strength(:weak))
    floor = solver.add(x >= 50)
    solver.update
    x.value.should eq(50.0)
    solver.remove(floor)
    solver.update
    x.value.should eq(0.0)
  end

  it "raises on duplicate and unknown constraints" do
    x = Variable.new("x")
    solver = Solver.new
    c = solver.add(x >= 0)
    expect_raises(DuplicateConstraint) { solver.add(c) }
    expect_raises(UnknownConstraint) { solver.remove(x <= 5) }
  end

  it "rejects unsatisfiable required constraints and stays usable" do
    x = Variable.new("x")
    solver = Solver.new
    solver.add(x >= 10)
    solver.add(x <= 20)
    solver.add((x == 15).strength(:weak))
    bad = x >= 30
    expect_raises(UnsatisfiableConstraint) { solver.add(bad) }
    expect_raises(UnsatisfiableConstraint) { solver.add(x == 5) }
    solver.has?(bad).should be_false
    solver.update
    x.value.should eq(15.0)
  end

  it "rejects contradictory equalities" do
    x = Variable.new("x")
    solver = Solver.new
    solver.add(x == 10)
    expect_raises(UnsatisfiableConstraint) { solver.add(x == 11) }
    solver.add(x == 10)
    solver.update
    x.value.should eq(10.0)
  end

  it "validates edit variables" do
    x = Variable.new("x")
    solver = Solver.new
    expect_raises(BadRequiredStrength) { solver.add_edit(x, :required) }
    solver.add_edit(x, Strength::MEDIUM)
    solver.has_edit?(x).should be_true
    expect_raises(DuplicateEdit) { solver.add_edit(x) }
    solver.remove_edit(x)
    solver.has_edit?(x).should be_false
    expect_raises(UnknownEdit) { solver.remove_edit(x) }
    expect_raises(UnknownEdit) { solver.suggest(x, 1) }
  end

  it "resets" do
    x = Variable.new("x")
    solver = Solver.new
    c = solver.add(x == 5)
    solver.add_edit(x, :weak)
    solver.reset
    solver.has?(c).should be_false
    solver.has_edit?(x).should be_false
    solver.add(x == 7)
    solver.update
    x.value.should eq(7.0)
  end

  it "solves a chain of boxes" do
    boxes = Array.new(20) { |i| {Variable.new("l#{i}"), Variable.new("r#{i}")} }
    solver = Solver.new
    solver.add(boxes[0][0] == 0)
    boxes.each_with_index do |(l, r), i|
      solver.add(r - l >= 10)
      solver.add((r - l == 10).strength(:medium))
      solver.add(boxes[i + 1][0] == r + 5) if i < boxes.size - 1
    end
    solver.update
    boxes.last[1].value.should eq(295.0)
  end
end
