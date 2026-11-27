# spec/constraint_spec.cr
require "./spec_helper"

describe Constraint do
  x = Variable.new("x")
  y = Variable.new("y")

  it "moves everything to the left side" do
    c = x + 10 <= y
    c.operator.should eq(Constraint::Operator::LessEqual)
    c.expression.constant.should eq(10.0)
    c.expression.terms.map(&.coefficient).should eq([1.0, -1.0])
  end

  it "merges terms of the same variable" do
    c = x + x == 2 * x + y
    c.expression.terms.size.should eq(2)
    c.expression.terms[0].coefficient.should eq(0.0)
    c.expression.terms[1].coefficient.should eq(-1.0)
  end

  it "supports numbers on the left" do
    (100 <= x).operator.should eq(Constraint::Operator::GreaterEqual)
    (100 >= x).operator.should eq(Constraint::Operator::LessEqual)
    (0 == x).operator.should eq(Constraint::Operator::Equal)
  end

  it "defaults to required strength" do
    (x >= 0).strength.should eq(Strength::REQUIRED)
  end

  it "copies with a new strength" do
    c = x >= 0
    weak = c.strength(:weak)
    weak.strength.should eq(Strength::WEAK)
    c.strength.should eq(Strength::REQUIRED)
    weak.strength(Strength.new(0, 2, 0)).strength.value.should eq(2000.0)
  end
end
