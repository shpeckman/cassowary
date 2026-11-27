# examples/layout.cr
#
# Lays out a sidebar and a content pane in a resizable window, then explains a rejected
# constraint. Run with `crystal run examples/layout.cr`.

require "../src/cassowary"

include Cassowary

window = Variable.new("window")
sidebar = Variable.new("sidebar")
content_left = Variable.new("content_left")
content_width = Variable.new("content_width")
gap = 8

solver = Solver.new
solver.add(
  sidebar >= 120,
  sidebar <= 300,
  content_left == sidebar + gap,
  content_left + content_width == window,
  content_width >= 200,
  (sidebar == window * 0.25).strength(:medium),
)

solver.edit(window) do |edit|
  {400, 800, 1600}.each do |size|
    edit.suggest(size)
    solver.update
    puts "window #{window.value}: sidebar #{sidebar.value}, content #{content_left.value}..#{window.value}"
  end
end

narrow = window <= 250
begin
  solver.add(narrow)
rescue UnsatisfiableConstraint
  puts "#{narrow} conflicts with:"
  solver.explain(narrow).each { |constraint| puts "  #{constraint}" }
end
