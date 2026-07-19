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

## 1.6.0 — 2026-07-18

### Added — shared server rendezvous (decoupling by URL, not by library)
- `AUTOSPEC_SERVER` now resolves its endpoint from a shared rendezvous so unrelated
  projects reuse ONE llama.cpp server (one model resident in VRAM) without any of them
  depending on one another. Resolution order:
  1. `LLAMA_SERVER_URL` env var (reuse-only: never spawns or kills a server it was told
     about) — `endpoint_source = "env"`.
  2. A registry file (`<temp>/llama_server_registry.json`) written by a previous spawn,
     if it still names a healthy server — `endpoint_source = "registry"`.
  3. The passed-in port; a local server is spawned and its endpoint recorded in the
     registry for the next project to find — `endpoint_source = "default"`.
- New queries: `host`, `endpoint_source`, `is_local`, `from_shared_rendezvous`,
  `registry_path`. `stop` still leaves reused/shared servers alone.
- `--live` prints which rendezvous the endpoint came from and wires the LLM client to the
  resolved host/port (not a hardcoded one).

### Verified (LIVE)
- Env path: `--live ... 9999` with `LLAMA_SERVER_URL=http://127.0.0.1:8137` ignored the
  wrong port, reused 8137 (`endpoint from env`); model proposed `(b1 + b2 + b3) /= 0`,
  Z3 accepted attempt 1, harden -> BULLET-PROOF.
- Registry path: same wrong port with a registry entry naming 8137 -> `endpoint from
  registry`, reused. Both prove any project (including private HTTP-only ones) shares the
  one model by URL, with zero code dependency.
- 23/23 unit tests pass; zero compilation warnings.

## 1.7.0 — 2026-07-19

### Added — interactive contract playground (`--repl`)
- `AUTOSPEC_REPL` and `--repl [model_gguf] [gpu_exe] [cpu_exe] [port]`: an
  interactive session where you declare result variables, type require/ensure/
  invariant clauses, and drive Z3 directly:
  - `outputs a b c` — declare result variables
  - `require`/`ensure`/`invariant <expr>` — add a clause
  - `test <expr>` — try an ensure clause without keeping it (Z3 reports feasible /
    vacuous / would-be-unsatisfiable)
  - `check` — feasibility and vacuity (with a witness)
  - `show`, `reset`, `help`, `quit`
  - `harden` — run the deterministic diagnostic battery; with a model configured,
    first ask it to strengthen a vacuous spec until Z3 accepts.
- Two tiers: the Z3 commands need no model; `--repl` with a model path also starts
  a llama.cpp server (via `AUTOSPEC_SERVER`, GPU-preferred) so `harden` can
  auto-strengthen. Honors the `LLAMA_SERVER_URL` rendezvous.

### Verified (LIVE)
- Z3-only: declared a sort spec, `check` flagged it VACUOUS, added a conservation
  clause, `harden` -> BULLET-PROOF.
- With Qwen2.5-Coder-3B on Vulkan: `harden` asked the model, which proposed
  `(b1 + b2 + b3) > 0`, Z3 accepted on attempt 1, `show` confirmed the clause was
  kept, verdict BULLET-PROOF.

## 1.8.0 — 2026-07-19

### Added — conversational spec building (`--chat`)
- `AUTOSPEC_CHAT` and `--chat <model_gguf> [gpu_exe] [cpu_exe] [port]`: describe a
  feature in plain English and the local model turns it into a formal spec, which
  Z3 checks. You never declare variables or type math -- results come back as prose
  ("it holds together and is NOT vacuous -- looks solid" / "under-constrained" /
  "these clash"). Refine by talking; `show` reveals the formal contract; `accept`
  keeps it; `reset`/`help`/`quit`.
- The model is asked for a strict OUTPUT/REQUIRE/ENSURE form pairing a formal
  condition (decidable fragment) with a plain-English restatement; the formal half
  feeds Z3, the English half is shown. Requires a model.

### Fixed — sound vacuity for input-dependent queries
- Vacuity is now decided by validity, not satisfiability: a trivial result (output
  = 0) is "trivially acceptable" only if it satisfies the obligation for EVERY
  input. `--chat` proves `(precondition and out=0) implies obligation` instead of
  asking whether the trivial result works for *some* input. This stops `max(a,b)`
  (and any input-dependent query) from being wrongly flagged under-constrained,
  while a genuinely weak spec like `ensure r >= 0` is still correctly flagged.

### Verified (LIVE)
- Qwen2.5-Coder-3B on Vulkan: "the larger of two numbers" -> spec with three
  guarantees, Z3 verdict "NOT vacuous, looks solid"; "any non-negative number" ->
  correctly "under-constrained". `show` reveals the formal contract. 23/23 tests.
