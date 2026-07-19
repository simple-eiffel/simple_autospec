# simple_autospec

[GitHub](https://github.com/simple-eiffel/simple_autospec) •
[Issues](https://github.com/simple-eiffel/simple_autospec/issues)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Eiffel 25.02](https://img.shields.io/badge/Eiffel-25.02-purple.svg)
![tests 23/23](https://img.shields.io/badge/tests-23%2F23-green.svg)

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

## Closing the loop: LLM proposes, Z3 disposes

`AUTOSPEC_PROPOSER` completes the propose/dispose cycle: given a vacuous spec, it asks
an oracle for a candidate conservation clause, parses it, and checks it with Z3 — *does
adding it keep the spec feasible and reject the trivial witness?* On rejection it feeds
the reason (an unparseable clause, or the surviving counter-witness) into the next prompt
and retries. This is the research-validated pattern (LLM proposes / SMT disposes with
counterexample feedback); the oracle is **never trusted to be correct** — Z3 accepts or
rejects every candidate, so a weak or local model suffices.

```eiffel
create proposer.make (asp, oracle)
if attached proposer.strengthen_to_non_vacuous (spec, 5) as clause then
    -- `spec' now hardens clean; `proposer.attempts' logs each try + verdict
end
```

Two oracles ship: `AUTOSPEC_LLM_CLIENT` (POSTs to a local **llama.cpp** server via curl —
run any GGUF model; build the server with the **Vulkan** backend to use whatever GPU is
present) and `AUTOSPEC_SCRIPTED_ORACLE` (canned responses, for deterministic tests). The
recommended local model is **Qwen3-Coder-30B-A3B** — but because the feedback loop, not
the model, does the converging, the client is model-agnostic.

## The core loop: `harden`

`AUTOSPEC_SESSION.harden` runs the whole diagnostic battery through Z3 and returns
prioritized findings — the Socratic prompts you (or an LLM) read to know what to fix:

```eiffel
create session.make (asp, spec)
session.harden
print (session.report)
--   [WARNING] vacuous-spec: a trivial result (all outputs = 0) satisfies the spec
--             -- add a conservation law  {witness: b1 -> 0  b2 -> 0  b3 -> 0}
--   => needs work
```

Findings, most severe first:

| Severity | Kind | Meaning |
|---|---|---|
| CRITICAL | dead-precondition | precondition unsatisfiable (feature un-callable) |
| CRITICAL | contradictory-obligation | postcondition and invariant can't both hold |
| WARNING | unconstrained-result | no postcondition — any implementation passes |
| WARNING | vacuous-spec | a trivial output (all `declare_output`s = 0) satisfies it |
| info | redundant-clause | one postcondition implies another |

The vacuity probe is automatic — you `declare_output` the result variables and it
finds the dumb witness itself. `is_bulletproof` is True when nothing critical or
warning remains.

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

## Talk to it in plain English (`--chat`)

Describe what a function should do; the local model turns your words into a formal
specification and Z3 checks it. No variables, no math syntax — you talk, it specs,
Z3 disposes, and the answer comes back in prose.

```
$ ./bin/simple_autospec.exe --chat model.gguf gpu_server.exe cpu_server.exe 8137

You> the larger of two numbers a and b
  Here's what it would guarantee:
   - the result is at least as large as a
   - the result is at least as large as b
   - the result is one of the two inputs
  Z3 check: it holds together and is NOT vacuous -- looks solid.
You> show          # reveal the formal contract
You> accept        # keep it
```

Say what you want changed to refine it; `show` reveals the math, `accept` keeps it,
`quit` leaves. (Needs a model — natural language is the point.)

## Interactive contract playground (`--repl`)

Drive the engine by hand: declare result variables, type contract clauses, and let
Z3 tell you whether the spec is feasible or vacuous — and, with a local model
attached, ask it to strengthen a vacuous spec until Z3 accepts.

```
$ ./bin/simple_autospec.exe --repl               # Z3-only
$ ./bin/simple_autospec.exe --repl model.gguf gpu_server.exe cpu_server.exe 8137

AutoSpec> outputs b1 b2 b3
AutoSpec> ensure b1 <= b2
AutoSpec> ensure b2 <= b3
AutoSpec> check
  VACUOUS: the trivial result (all outputs = 0) satisfies it
AutoSpec> harden
  attempt 1: ACCEPTED '(b1 + b2 + b3) > 0'   => BULLET-PROOF
AutoSpec> quit
```

Commands: `outputs`, `require`/`ensure`/`invariant`, `test` (try without keeping),
`check`, `show`, `harden`, `reset`, `help`, `quit`. Operators: `+ - * < <= > >= = /= and or not`.

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
