# AGENTS.md

Orientation for AI agents working on this shard.

## Layout

```
src/cassowary.cr              entry point, requires every file in dependency order
src/cassowary/errors.cr       Error and its subclasses
src/cassowary/strength.cr     Strength, Strength::Preset
src/cassowary/operand.cr      Operand: the operators shared by Variable, Term, Expression
src/cassowary/variable.cr     Variable
src/cassowary/term.cr         Term
src/cassowary/expression.cr   Expression
src/cassowary/constraint.cr   Constraint, Constraint::Operator
src/cassowary/number.cr       Number reopened for `2 * x`, `10 - x`, `100 <= x`
src/cassowary/symbol.cr       private Sym: tableau column (id + kind)
src/cassowary/row.cr          private Row: tableau row, private NEAR_ZERO
src/cassowary/solver.cr       Solver, private Tag and EditInfo
spec/                         one spec file per area, spec_helper.cr includes Cassowary
```

## Commands

```sh
crystal spec      # or: make spec
crystal docs      # or: make docs; output in docs/ (gitignored)
```

Prefix commands that change files with `dev`.

## Algorithm

Port of kiwi (C++), the Badros/Borning/Stuckey Cassowary with the dual simplex for edits.

- Tableau: `@rows : Hash(Sym, Row)`; each row is `basic = constant + Σ coeff * sym`.
- Symbol kinds: External (user variable), Slack (inequality), Error (non-required
  violation, weighted in `@objective` by strength), Dummy (required equality marker).
- `Solver#add`: `create_row` → `choose_subject` → pivot, or `add_with_artificial_variable`
  when no subject exists. The artificial path snapshots `@rows` and `@objective` and
  restores them on failure, so an unsatisfiable add leaves the tableau unchanged.
- `Solver#suggest`: shifts row constants, queues infeasible rows, `dual_optimize`.
- `NEAR_ZERO = 1.0e-8` drops vanishing coefficients.
- Variables are keyed by `object_id`, never by `Variable`, because `Variable#==` builds
  a `Constraint` (see below). Constraints are keyed by identity (`Reference#hash`).
- `Solver#update` adds `0.0` to normalize `-0.0`.

## Design notes

- `==`, `<=`, `>=` on operands build constraints. Consequence: `Variable` and
  `Expression` must never be hash keys or compared with `==`/`!=`; use `same?`.
- `Expression` operators concatenate terms; `Constraint.new` merges like terms (`reduce`).
- Methods taking a strength accept `Strength | Strength::Preset`, so symbols autocast
  (`:strong`).
- Strength value = `strong*1e6 + medium*1e3 + weak`, components clamped to `0..1000`.

## Code standards

- Compiler-friendly, performance-focused, idiomatic Crystal; data-driven design.
- Ergonomic user-facing API; avoid shotgun surgery (operators live once in `Operand`).
- Visibility: `private` for types/constants/methods used only inside their namespace;
  `protected` for methods other types in `Cassowary` call (`Variable#value=`,
  `Expression#concat/offset/scale/reduce`); `# :nodoc:` for public code users must not use
  (none yet).
- Doc comments: first sentence in third person present; italicize parameters; no
  implementation details in public docs; never reference private or `:nodoc:` features.
- Check `crystal docs`: only the public API (Cassowary types, errors, Number
  operators) may appear.
- Keep README.md (public API) and AGENTS.md (internals) in sync with the code.
- Do not change the version in shard.yml.

## Extension points

None. Everything outside the public API is private or protected.
