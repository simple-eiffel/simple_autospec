note
	description: "[
		The AutoSpec mechanical core: the deterministic checks that harden a
		specification, run through Z3 (simple_smt). These are the "dispose" half
		of an LLM-proposes / Z3-disposes loop -- nothing here judges correctness
		by fiat; every verdict is discharged by the solver.

		Checks:
		  * is_feasible          -- is the spec implementable at all? (pre&post&inv sat)
		  * is_precondition_live -- is the precondition satisfiable? (else dead feature)
		  * admits               -- does a concrete result-assignment satisfy the obligation?
		  * is_vacuous_for       -- does a deliberately-trivial witness satisfy the spec?
		  * strengthens          -- does spec A entail spec B? (prune 1:M mined candidates)

		Usage:
		  create autospec.make
		  smt := autospec.smt
		  b1 := smt.int_const ("b1")  ...
		  create spec.make (smt, "sort3")
		  spec.ensure_that (b1.at_most (b2))                 -- is_sorted only (weak)
		  autospec.is_vacuous_for (spec, dumb_all_zero)      -- True: spec is under-constrained
	]"
	author: "Larry Rix"

class
	SIMPLE_AUTOSPEC

create
	make

feature {NONE} -- Initialization

	make
			-- Create an AutoSpec checker with its own solver.
		do
			create smt.make
			last_witness := ""
		end

feature -- Access

	smt: SIMPLE_SMT
			-- The solver / expression factory specs are built over.

	last_witness: STRING
			-- Counter-model or admitting assignment from the last check ("" if none).

feature -- Spec factory

	new_spec (a_name: STRING): AUTOSPEC_SPEC
			-- A fresh spec over this checker's solver.
		require
			name_not_empty: not a_name.is_empty
		do
			create Result.make (smt, a_name)
		ensure
			same_solver: Result.smt = smt
		end

feature -- Structural checks

	is_precondition_live (a_spec: AUTOSPEC_SPEC): BOOLEAN
			-- Is `a_spec's precondition satisfiable? A dead (unsatisfiable)
			-- precondition means the feature can never be called.
		require
			same_solver: a_spec.smt = smt
		do
			smt.reset
			smt.assume (a_spec.precondition)
			Result := smt.is_satisfiable
			record_witness (Result)
		end

	is_feasible (a_spec: AUTOSPEC_SPEC): BOOLEAN
			-- Is `a_spec' implementable at all? False when pre and post and
			-- invariant are mutually contradictory (an impossible requirement,
			-- caught at spec time before any code exists).
			-- Note: sound only for single-state specs (queries, or specs whose
			-- pre and post reference disjoint variables); conjoining a command's
			-- pre-state and post-state is not a valid feasibility test.
		require
			same_solver: a_spec.smt = smt
		do
			smt.reset
			smt.assume (a_spec.all_conditions)
			Result := smt.is_satisfiable
			record_witness (Result)
		end

	is_obligation_satisfiable (a_spec: AUTOSPEC_SPEC): BOOLEAN
			-- Is `a_spec's obligation (postcondition and invariant) satisfiable?
			-- Both describe the SAME post-state, so this IS a sound feasibility
			-- test: False means the postcondition contradicts itself or the
			-- invariant -- a real, unimplementable requirement.
		require
			same_solver: a_spec.smt = smt
		do
			smt.reset
			smt.assume (a_spec.obligation)
			Result := smt.is_satisfiable
			record_witness (Result)
		end

feature -- Assignment checks

	admits (a_spec: AUTOSPEC_SPEC; a_result_assignment: SMT_EXPR): BOOLEAN
			-- Does the concrete result-assignment `a_result_assignment' (a
			-- conjunction of equalities pinning the result variables) satisfy
			-- `a_spec's obligation (postcondition and invariant)?
		require
			same_solver: a_spec.smt = smt
			assignment_same_context: a_result_assignment.context = smt.context
		do
			smt.reset
			smt.assume (a_spec.obligation)
			smt.assume (a_result_assignment)
			Result := smt.is_satisfiable
			record_witness (Result)
		end

	is_vacuous_for (a_spec: AUTOSPEC_SPEC; a_trivial_result: SMT_EXPR): BOOLEAN
			-- Does the deliberately-trivial (dumb) result `a_trivial_result'
			-- satisfy `a_spec's obligation? True means the spec is
			-- under-constrained -- it accepts an implementation that should be
			-- rejected. `last_witness' holds the admitted assignment.
		require
			same_solver: a_spec.smt = smt
			trivial_same_context: a_trivial_result.context = smt.context
		do
			Result := admits (a_spec, a_trivial_result)
		end

feature -- Comparison / pruning

	strengthens (a_strong, a_weak: AUTOSPEC_SPEC): BOOLEAN
			-- Does `a_strong' entail `a_weak' -- i.e. is every implementation
			-- satisfying `a_strong' also acceptable to `a_weak'? Used to prune
			-- 1:M mined candidate specs by subsumption.
		require
			strong_same_solver: a_strong.smt = smt
			weak_same_solver: a_weak.smt = smt
		do
			smt.reset
			Result := smt.prove (a_strong.all_conditions.entails (a_weak.all_conditions))
			last_witness := ""
		end

	are_equivalent (a, b: AUTOSPEC_SPEC): BOOLEAN
			-- Do `a' and `b' constrain implementations identically?
		require
			a_same_solver: a.smt = smt
			b_same_solver: b.smt = smt
		do
			Result := strengthens (a, b) and then strengthens (b, a)
		end

feature -- Reporting

	feasibility_report (a_spec: AUTOSPEC_SPEC): STRING
			-- A one-line human summary of `a_spec's structural health.
		require
			same_solver: a_spec.smt = smt
		do
			create Result.make (80)
			Result.append (a_spec.name + ": ")
			if not is_precondition_live (a_spec) then
				Result.append ("DEAD (precondition unsatisfiable)")
			elseif not is_feasible (a_spec) then
				Result.append ("INFEASIBLE (pre/post/invariant contradict -- unimplementable)")
			else
				Result.append ("feasible, " + a_spec.clause_count.out + " clauses")
			end
		ensure
			result_attached: Result /= Void
		end

feature {NONE} -- Implementation

	record_witness (a_sat: BOOLEAN)
			-- Capture the satisfying model into `last_witness' when `a_sat'.
		do
			if a_sat and then smt.is_satisfiable and then attached smt.solver.model as al_m then
				last_witness := al_m.to_string_representation
				al_m.dispose_model
			else
				last_witness := ""
			end
		end

invariant
	smt_attached: smt /= Void
	witness_attached: last_witness /= Void

end
