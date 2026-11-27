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

`==` on a variable builds a constraint, so a variable cannot be compared with `==` or
used as a `Hash` key. Use `same?` for identity.

### Expressions

`Variable`, `Term` and `Expression` include `Operand`, which provides:

| Operator           | Operand            | Result       |
|--------------------|--------------------|--------------|
| `+`, `-`           | operand or number  | `Expression` |
| `*`, `/`           | number             | `Expression` |
| unary `-`          |                    | `Expression` |
| `==`, `<=`, `>=`   | operand or number  | `Constraint` |

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

### Strengths

| Strength                           | Meaning                              |
|------------------------------------|--------------------------------------|
| `Strength::REQUIRED` / `:required` | must hold; the default               |
| `Strength::STRONG` / `:strong`     |                                      |
| `Strength::MEDIUM` / `:medium`     |                                      |
| `Strength::WEAK` / `:weak`         |                                      |
| `Strength.new(strong, medium, weak, weight = 1.0)` | custom strength      |

Each weighted component is clamped to `0..1000`. One unit of a level outweighs up to 999
units of the levels below it.

### Solver

| Method                              | Effect                                                    |
|-------------------------------------|-----------------------------------------------------------|
| `add(constraint)`                   | adds a constraint and returns it                          |
| `remove(constraint)`                | removes a constraint                                      |
| `has?(constraint)`                  | whether the constraint is in the solver                   |
| `add_edit(variable, strength = :strong)` | makes a variable steerable by `suggest`              |
| `remove_edit(variable)`             | stops a variable from being an edit variable              |
| `has_edit?(variable)`               | whether the variable is an edit variable                  |
| `suggest(variable, value)`          | suggests a value for an edit variable                     |
| `update`                            | writes the solution into the variables                    |
| `reset`                             | removes every constraint and edit variable                |

### Errors

All errors inherit from `Cassowary::Error`.

| Error                     | Raised by                         | When                                              |
|---------------------------|-----------------------------------|---------------------------------------------------|
| `DuplicateConstraint`     | `add`                             | the constraint is already in the solver           |
| `UnsatisfiableConstraint` | `add`                             | a required constraint conflicts; solver unchanged |
| `UnknownConstraint`       | `remove`                          | the constraint is not in the solver               |
| `DuplicateEdit`           | `add_edit`                        | the variable is already an edit variable          |
| `BadRequiredStrength`     | `add_edit`                        | the edit strength is required                     |
| `UnknownEdit`             | `remove_edit`, `suggest`          | the variable is not an edit variable              |
| `InternalError`           | any                               | a solver bug                                      |

## Development

```sh
make spec   # run the specs
make docs   # generate the API docs
```

## License

MIT
