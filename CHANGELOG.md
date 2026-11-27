# Changelog

## 0.1.0 (2026-11-27)

First release.

### Solver

- Adds and removes constraints one at a time or in batches; a rejected constraint or
  failed batch leaves the solver unchanged.
- Edit variables with `add_edit`, `suggest`, `suggest(values)` and the `edit` block.
- `update` writes the solution into the variables and can yield the ones that changed;
  `solver[variable]` reads a value without writing it.
- `constraints`, `has?`, `has_edit?`, `reset` and `dump` for inspection.
- `UnsatisfiableConstraint#conflicts` and `Solver#explain` name the required
  constraints a rejected one conflicts with.
- Strengths are weighed level by level: no amount of weak violation outweighs a medium
  one.
- Tolerances scale with the magnitude of the constants in the solver.

### Constraints

- Built with `+ - * / == <= >=` on variables, terms, expressions and numbers; `!=` is
  a compile-time error.
- `Constraint#violated?` and readable `to_s` for constraints, expressions and
  strengths.

### Changed during development

- `Strength#value` is removed; `Strength#strong`, `#medium` and `#weak` return the
  components.
