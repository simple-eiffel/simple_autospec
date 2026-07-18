# simple_autospec

[GitHub](https://github.com/simple-eiffel/simple_autospec) •
[Issues](https://github.com/simple-eiffel/simple_autospec/issues)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Eiffel 25.02](https://img.shields.io/badge/Eiffel-25.02-purple.svg)
![tests 15/15](https://img.shields.io/badge/tests-15%2F15-green.svg)

The **AutoSpec** mechanical core: harden a specification with Z3-backed checks —
feasibility, precondition-liveness, **vacuity detection**, and subsumption — built on
[simple_smt](https://github.com/simple-eiffel/simple_smt).

Part of the [Simple Eiffel](https://github.com/simple-eiffel) ecosystem.

## The idea

A specification is only as good as it is *non-vacuous*: a weak spec silently accepts
wrong implementations. AutoSpec makes that mechanical. Given a spec's precondition,
postcondition, and invariant clauses, it asks Z3:

- **Is it feasible?** — are pre ∧ post ∧ invariant mutually satisfiable, or did you write
  an impossible requirement? (caught at spec time, before any code)
- **Is the precondition live?** — or is the feature un-callable (dead)?
- **Is it vacuous?** — does a deliberately-dumb result satisfy it? If so, the spec is
  under-constrained and needs a conservation law.
- **Does A strengthen B?** — subsumption, to prune the 1:M candidate specs mined from code.

These are the *dispose* half of an LLM-proposes / Z3-disposes loop: nothing here judges
correctness by fiat; every verdict is discharged by the solver.

## Quick Start

```eiffel
create asp.make
b1 := asp.smt.int_const ("b1"); b2 := asp.smt.int_const ("b2"); b3 := asp.smt.int_const ("b3")

-- Weak sort spec: is_sorted only
weak := asp.new_spec ("sort")
weak.ensure_that (b1.at_most (b2))
weak.ensure_that (b2.at_most (b3))

-- A dumb result (0,0,0) is sorted but not a permutation of the input:
dumb := b1.is_equal_to (asp.smt.int_value (0))
    .conjoined (b2.is_equal_to (asp.smt.int_value (0)))
    .conjoined (b3.is_equal_to (asp.smt.int_value (0)))

asp.is_vacuous_for (weak, dumb)      -- True: the spec is under-constrained!

-- Add the permutation conservation law -> the strengthened spec rejects (0,0,0).
```

## Brownfield intake: mine contracts from existing code

Point the miner at real Eiffel source. It extracts each feature's `require`/`ensure`
clauses, translates the ones in the decidable fragment into candidate specs, and
**records what it cannot translate** rather than faking it — dotted calls (`a.count`),
`old`, strings, and reals are skipped honestly.

```eiffel
create asp.make
create miner.make (asp)
mined := miner.mine (source_text)          -- one candidate per feature
across mined as ic loop
    print (asp.feasibility_report (ic.spec))   -- e.g. "bad_seek: INFEASIBLE (...)"
    -- ic.kept  = clauses translated;  ic.skipped = clauses out of fragment
end
```

Every mined clause is a **seed, not truth** — mining from code alone would bake in the
code's bugs, so AutoSpec then interrogates each candidate with Z3 (feasibility, vacuity,
subsumption). CVEs, worked examples, and human intent are other seed sources.

## API

- `SIMPLE_AUTOSPEC` — `new_spec`, `is_feasible`, `is_precondition_live`, `admits`,
  `is_vacuous_for`, `strengthens`, `are_equivalent`, `feasibility_report`, `last_witness`.
- `AUTOSPEC_SPEC` — `require_that`, `ensure_that`, `invariant_that`, and the composed
  formulas `precondition`/`postcondition`/`class_invariant`/`obligation`/`all_conditions`.
- `AUTOSPEC_EXPR_PARSER` — compiles Eiffel boolean/arithmetic text into `SMT_EXPR` for
  the decidable fragment (`+ - *`, comparisons, `and or not implies xor`); fails cleanly
  outside it.
- `AUTOSPEC_MINER` / `AUTOSPEC_MINED` — the brownfield intake and its per-feature result.

## Where it fits

`simple_autospec` is Phase 1 of the AutoSpec arc: the deterministic engine that the
LLM/human Socratic loop drives. Two intakes feed it — greenfield ideas and brownfield
specs mined from existing code (every `require`/`ensure` a seed) — and its output feeds
verification or synthesis. It sits on `simple_smt` (Phase 0, the trusted decision procedure).

## Installation

```
<library name="simple_autospec" location="$SIMPLE_EIFFEL/simple_autospec/simple_autospec.ecf"/>
```

Depends on `simple_smt`, which vendors Z3; `libz3.dll` must be beside the executable
(the build copies it into `bin/`).

```bash
/d/prod/ec.sh test -config simple_autospec.ecf -target simple_autospec_tests   # 10/10
```

## License

MIT.
