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
