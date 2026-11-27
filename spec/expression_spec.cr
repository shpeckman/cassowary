# spec/expression_spec.cr
require "./spec_helper"

private def coefficients(expression : Expression) : Array({String, Float64})
  expression.terms.map { |term| {term.variable.name, term.coefficient} }
end

describe Expression do
  x = Variable.new("x")
  y = Variable.new("y")

  it "builds expressions with operators" do
    e = 2 * x + y / 2 - 10
    coefficients(e).should eq([{"x", 2.0}, {"y", 0.5}])
    e.constant.should eq(-10.0)
  end

  it "supports numbers on the left" do
    e = 10 - x
    coefficients(e).should eq([{"x", -1.0}])
    e.constant.should eq(10.0)
    (3 + x).constant.should eq(3.0)
  end

  it "negates" do
    e = -(x - y + 1)
    coefficients(e).should eq([{"x", -1.0}, {"y", 1.0}])
    e.constant.should eq(-1.0)
  end

  it "evaluates with current values" do
    (2 * x + 1).value.should eq(1.0)
    Term.new(x, 3).value.should eq(0.0)
  end

  it "builds an expression from a constant" do
    Expression.new(5).constant.should eq(5.0)
  end
end
