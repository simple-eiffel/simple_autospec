# Changelog

## 1.0.0 — 2026-07-18

Initial release. The AutoSpec mechanical core, built on simple_smt.

### Added
- `AUTOSPEC_SPEC` — a specification under construction: require/ensure/invariant
  clauses (each a boolean SMT_EXPR), with composed `precondition`/`postcondition`/
  `class_invariant`/`obligation`/`all_conditions`.
- `SIMPLE_AUTOSPEC` — the Z3-backed checks: `is_feasible` (pre&post&inv satisfiable),
  `is_precondition_live`, `admits` (a result-assignment satisfies the obligation),
  `is_vacuous_for` (a trivial witness satisfies the spec — under-constrained!),
  `strengthens`/`are_equivalent` (subsumption for pruning 1:M candidates),
  `feasibility_report`, `last_witness`.
- 10 tests: infeasible/dead-spec detection, the sort-spec vacuity story (weak spec
  vacuous, strengthened spec non-vacuous + admits the correct result), subsumption.
- Demo app: hardens a sort spec from vacuous to bullet-proof in two rounds.

### Notes
- Phase 1 of the AutoSpec arc; the deterministic engine an LLM/human Socratic loop
  drives. Sits on simple_smt (Phase 0). Z3 is the trusted oracle.

## 1.1.0 — 2026-07-18

### Added
- `AUTOSPEC_EXPR_PARSER` — recursive-descent compiler from Eiffel boolean/arithmetic
  expression text to SMT_EXPR over the decidable fragment (identifiers, integer literals,
  + - *, unary minus, parens, = /= < <= > >=, and/or/not/implies/xor). Out-of-fragment
  constructs (dotted calls, `old`, strings, reals) fail cleanly rather than mistranslate.
- `AUTOSPEC_MINER` / `AUTOSPEC_MINED` — brownfield intake: read Eiffel source, extract each
  feature's require/ensure clauses, translate the fragment into candidate AUTOSPEC_SPECs,
  record skipped clauses. Mined clauses are seeds, then interrogated by the checker.
- 5 new tests (parser translate/reject, parsed-clause checkable, miner extract+translate,
  miner detects infeasible real contract): 15/15 total. Demo mines real-shaped source.

## 1.2.0 — 2026-07-18

### Added
- `AUTOSPEC_SCANNER` + CLI `--scan <dir>`: batch contract audit — walk an Eiffel
  source tree, mine every feature's contracts, and flag DEAD (unsatisfiable)
  preconditions across a whole library or the ecosystem.

### Fixed (soundness)
- The expression parser now uses linear REAL arithmetic (identifiers and numerals
  are reals), not integers. Real-valued ranges like `0 < p < 1` are no longer
  falsely reported unsatisfiable.
- The batch audit reports ONLY dead preconditions. The previous pre-and-post
  "infeasible" check conflated a command's pre-state and post-state (e.g. `require
  id = 0 ... a_id > 0` with `ensure id = a_id`) and produced false positives; that
  check is unsound without weakest-precondition/framing and was removed from the
  batch audit. (The library's `is_feasible`/`is_vacuous_for` remain correct for
  intentional single-state specs.)

### Verified
- Sound ecosystem audit: 127 libraries, 6,581 features, 10,281 clauses in the
  decidable fragment, 0 dead preconditions. Tool confirmed sensitive: correctly
  flags a genuine dead precondition (`x > 100 and x < 10`).

## 1.3.0 — 2026-07-18

### Added
- `AUTOSPEC_SESSION` — the AutoSpec core loop. `harden` runs the full diagnostic
  battery through Z3 and produces prioritized findings: dead-precondition and
  contradictory-obligation (CRITICAL), unconstrained-result and vacuous-spec
  (WARNING), redundant-clause (info). `is_bulletproof` / `report`.
- `AUTOSPEC_FINDING` — a severity + kind + message + witness diagnostic.
- Automatic vacuity probe: `AUTOSPEC_SPEC.declare_output` marks result variables,
  and harden pins them to a trivial value and checks whether the spec still accepts
  it -- no caller-supplied witness needed.
- `SIMPLE_AUTOSPEC.is_obligation_satisfiable` -- a SOUND feasibility test (post and
  invariant share the post-state), unlike the pre-and-post conjunction.
- 5 session tests: 20/20 total. Demo shows harden turning a weak sort spec's
  findings into a bullet-proof verdict after the conservation law is added.

## 1.4.0 — 2026-07-18

### Added
- `AUTOSPEC_ORACLE` (deferred) — the propose side as a pluggable interface.
- `AUTOSPEC_LLM_CLIENT` — a self-contained local-LLM oracle: POSTs a completion
  request to a running llama.cpp server via the system curl (any GGUF model; build the
  server with the Vulkan backend for GPU-agnostic acceleration). Its own client, reusing
  only the well-known llama.cpp-server + curl pattern -- no dependency on any private
  model project.
- `AUTOSPEC_SCRIPTED_ORACLE` — canned proposals for deterministic tests.
- `AUTOSPEC_PROPOSER` — the propose/dispose loop with counterexample feedback:
  strengthen_to_non_vacuous asks the oracle for a clause, parses it, checks with Z3, and
  on rejection feeds the reason (unparseable, or the surviving trivial witness) into the
  next prompt and retries. The oracle is never trusted to be correct.
- 3 proposer tests (accept-after-feedback, feedback-carried, give-up-on-garbage): 23/23.
- Demo: the loop repairs a vacuous sort spec (reject "b1>=0", accept the permutation),
  then harden reports BULLET-PROOF.

### Changed
- The AutoSpec layer now uses linear REAL arithmetic consistently (matching the parser),
  so mined/parsed clauses and hand-built spec variables share a Z3 sort. (Fixes a
  parser/spec sort mismatch that made the proposer's clauses not constrain the outputs.)

## 1.5.0 — 2026-07-18

### Added
- `AUTOSPEC_SERVER` — ensures there is always a llama.cpp server to run against:
  reuses one already answering /health, else spawns one preferring a Vulkan (GPU)
  build and falling back to a CPU build; polls /health with a generous timeout.
  Generic (binary + model paths are arguments; no private-model dependency).
- CLI `--live <model.gguf> [gpu_exe] [cpu_exe] [port]`: starts a server and runs the
  propose/dispose loop against the real model.
- Model-reply cleaning: strips markdown code fences and a leading `label:` from the
  model's output; the prompt now names the actual output variables and current clauses.

### Fixed
- Health check and the LLM POST use SIMPLE_PROCESS.command_output (not launch +
  captured_output, which did not capture) -- matching the proven llama.cpp+curl pattern.

### Verified (LIVE)
- Full end-to-end run against a real local model (Qwen2.5-Coder-3B-Instruct Q4_K_M on
  llama.cpp Vulkan): the model proposed `(b1 + b2 + b3) > 0` -- a valid conservation law
  that rejects the trivial (0,0,0) result -- Z3 ACCEPTED it on attempt 1, and harden
  then reported BULLET-PROOF. See reports/live_run.txt.
