# cassowary

An incremental linear constraint solver for Crystal, based on the Cassowary algorithm.
Build constraints with ordinary operators, give them strengths, and steer edit variables
for interactive layout.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  cassowary:
    github: shpeckman/cassowary
```

Then run `shards install`.

## Usage

```crystal
require "cassowary"

left = Cassowary::Variable.new("left")
width = Cassowary::Variable.new("width")
right = Cassowary::Variable.new("right")

solver = Cassowary::Solver.new
solver.add(right == left + width)
solver.add(width >= 100)
solver.add((left == 0).strength(:strong))

solver.add_edit(width, :strong)
solver.suggest(width, 250)
solver.update
right.value # => 250.0

solver.suggest(width, 50) # violates width >= 100
solver.update
width.value # => 100.0
```

### Variables

`Variable.new(name)` creates an unknown. `Solver#update` writes the solution into
`Variable#value`; values do not change between calls to `#update`.

`==` on a variable builds a constraint, so a variable cannot be compared with `==`.
`!=` does not compile, because no constraint expresses it. Use `same?` for identity, and
call `compare_by_identity` on a `Hash` keyed by variables:

```crystal
targets = Hash(Cassowary::Variable, Float64).new.compare_by_identity
targets[width] = 250.0
```

The solver keeps a variable only while a constraint or edit uses it, so a variable whose
last constraint is removed is forgotten and costs nothing.

Use each variable in one solver only: every solver that uses a variable writes its own
solution into `Variable#value` on `#update`.

### Expressions

`Variable`, `Term` and `Expression` include `Operand`, which provides:

| Operator         | Operand           | Result       |
|------------------|-------------------|--------------|
| `+`, `-`         | operand or number | `Expression` |
| `*`, `/`         | number            | `Expression` |
| unary `-`        |                   | `Expression` |
| `==`, `<=`, `>=` | operand or number | `Constraint` |

Numbers on the left side work too: `2 * x`, `10 - x`, `100 <= x`. Expressions must stay
linear; a variable cannot multiply another variable.

`Expression#value` and `Term#value` evaluate with the variables' current values.

### Constraints

A comparison returns a required `Constraint`. `Constraint#strength` returns a copy with
another strength:

```crystal
(x + 10 <= y).strength(:medium)
(x == 0).strength(Cassowary::Strength.new(0, 5, 0))
```

Constraints are immutable; the solver identifies them by object identity, so keep the
returned constraint to remove it later.

`Constraint#to_s` writes the readable form, with positive terms on the left, negative
ones moved to the right, and the strength unless required: `x + 10 <= y | strong`.

`Constraint#violated?` reports whether the constraint fails for the variables' current
values, which is useful after `Solver#update` to see which optional constraints gave way.
It ignores differences below 1e-8 of the constraint's largest term or constant. The
solver's own tolerance scales with the largest constant it has been given, so
coordinates far from 1 (1e4, 1e7) solve as reliably as small ones; rounding then grows
with that magnitude, so a constraint near zero can report a tiny violation.

### Strengths

| Strength                                           | Meaning                |
|----------------------------------------------------|------------------------|
| `Strength::REQUIRED` / `:required`                 | must hold; the default |
| `Strength::STRONG` / `:strong`                     |                        |
| `Strength::MEDIUM` / `:medium`                     |                        |
| `Strength::WEAK` / `:weak`                         |                        |
| `Strength.new(strong, medium, weak, weight = 1.0)` | custom strength        |

Each weighted component is clamped to `0..1000` and readable through `#strong`,
`#medium` and `#weak`; `#to_s` writes a preset's name (`strong`) or the components
(`Strength(0, 5, 0)`). The solver minimizes violation level by
level: any violation of a strong component outweighs every medium and weak violation, and
any medium violation outweighs every weak one. Within a level, violations add up,
multiplied by the component.

### Solver

| Method                                            | Effect                                                                             |
|---------------------------------------------------|------------------------------------------------------------------------------------|
| `add(constraint)`                                 | adds a constraint and returns it                                                   |
| `add(*constraints)` / `add(constraints)`          | adds several constraints; on failure none of them stays added                      |
| `remove(constraint)`                              | removes a constraint                                                               |
| `remove(*constraints)` / `remove(constraints)`    | removes several constraints; checks all are present before removing any            |
| `has?(constraint)`                                | whether the constraint is in the solver                                            |
| `explain(constraint)`                             | a minimal set of required constraints a rejected constraint conflicts with         |
| `add_edit(variable, strength = :strong)`          | makes a variable steerable by `suggest`                                            |
| `remove_edit(variable)`                           | stops a variable from being an edit variable                                       |
| `has_edit?(variable)`                             | whether the variable is an edit variable                                           |
| `edit(variable, strength = :strong) { \|edit\| }` | makes a variable an edit variable for the block; `edit.suggest(value)` steers it   |
| `suggest(variable, value)`                        | suggests a value for an edit variable                                              |
| `suggest(values)`                                 | suggests values for several edit variables at once, from `{variable, value}` pairs |
| `update`                                          | writes the solution into the variables                                             |
| `update { \|variable\| }`                         | writes the solution and yields each variable whose value changed                   |
| `reset`                                           | removes every constraint and edit variable                                         |
| `dump` / `dump(io)`                               | describes the internal state, for debugging                                        |

### Errors

All errors inherit from `Cassowary::Error`.

| Error                     | Raised by                | When                                                                                                                                                                         |
|---------------------------|--------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `DuplicateConstraint`     | `add`                    | the constraint is already in the solver                                                                                                                                      |
| `UnsatisfiableConstraint` | `add`                    | a required constraint conflicts; solver unchanged; `conflicts` lists required constraints it conflicts with, possibly more than needed; `Solver#explain` gives a minimal set |
| `UnknownConstraint`       | `remove`                 | the constraint is not in the solver                                                                                                                                          |
| `DuplicateEdit`           | `add_edit`               | the variable is already an edit variable                                                                                                                                     |
| `BadRequiredStrength`     | `add_edit`               | the edit strength is required                                                                                                                                                |
| `UnknownEdit`             | `remove_edit`, `suggest` | the variable is not an edit variable; `suggest(values)` checks every variable before changing anything                                                                       |
| `InternalError`           | any                      | a solver bug                                                                                                                                                                 |

## Development

```sh
make spec          # run the specs; FUZZ_SEEDS=200 make spec fuzzes deeper
make bench         # run the benchmarks
make bench-cycles  # count CPU cycles per benchmark scenario (needs perf)
make docs          # generate the API docs
crystal run examples/layout.cr  # a resizable two-pane layout and an explained conflict
```

The benchmarks measure expression building and solver operations: adding a layout,
suggesting edit values, adding and removing constraints, and rejecting unsatisfiable
ones. On a processor with both performance and efficiency cores, pin the run to one core
(`taskset -c 2 ./bench-suite`) so the scheduler does not move it mid-measurement.
Wall-clock results still vary by tens of percent between runs; `make bench-cycles`
runs fixed work per scenario pinned to one CPU (`CPU=2`, best of `RUNS=5`) and reports
millions of user-space cycles, which is stable enough to compare changes.

## License

MIT, see `LICENSE`.
