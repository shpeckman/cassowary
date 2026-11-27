# spec/strength_spec.cr
require "./spec_helper"

describe Strength do
  it "orders the presets" do
    (Strength::REQUIRED > Strength::STRONG).should be_true
    (Strength::STRONG > Strength::MEDIUM).should be_true
    (Strength::MEDIUM > Strength::WEAK).should be_true
  end

  it "keeps one unit of a level above 999 units of the levels below" do
    (Strength::STRONG > Strength.new(0, 999, 999)).should be_true
    (Strength::MEDIUM > Strength.new(0, 0, 999)).should be_true
  end

  it "applies the weight and clamps each component" do
    Strength.new(0, 1, 0, 2).value.should eq(2000.0)
    Strength.new(5000, 0, 0).value.should eq(1_000_000_000.0)
    Strength.new(-1, 0, 0).value.should eq(0.0)
  end

  it "reports required" do
    Strength::REQUIRED.required?.should be_true
    Strength.new(1000, 1000, 1000, 10).required?.should be_true
    Strength::STRONG.required?.should be_false
  end

  it "maps presets to strengths" do
    Strength::Preset::Medium.strength.should eq(Strength::MEDIUM)
  end
end
