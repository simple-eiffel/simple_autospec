note
	description: "[
		A specification under construction: precondition, postcondition, and
		invariant clauses, each a boolean SMT_EXPR built over a shared solver
		context. The clauses ARE the spec; AutoSpec's checker interrogates them
		via Z3 (feasibility, precondition-liveness, vacuity, subsumption).
	]"
	author: "Larry Rix"

class
	AUTOSPEC_SPEC

create
	make

feature {NONE} -- Initialization

	make (a_smt: SIMPLE_SMT; a_name: STRING)
			-- Create an empty spec named `a_name' over solver `a_smt'.
		require
			name_not_empty: not a_name.is_empty
		do
			smt := a_smt
			name := a_name
			create preconditions.make (4)
			create postconditions.make (4)
			create invariants.make (4)
		ensure
			smt_set: smt = a_smt
			name_set: name = a_name
		end

feature -- Access

	name: STRING
			-- Human name of the specified feature.

	smt: SIMPLE_SMT
			-- Shared solver / expression factory.

	preconditions: ARRAYED_LIST [SMT_EXPR]
			-- require clauses.

	postconditions: ARRAYED_LIST [SMT_EXPR]
			-- ensure clauses.

	invariants: ARRAYED_LIST [SMT_EXPR]
			-- class-invariant clauses.

	clause_count: INTEGER
			-- Total number of clauses.
		do
			Result := preconditions.count + postconditions.count + invariants.count
		end

feature -- Construction

	require_that (a_clause: SMT_EXPR)
			-- Add a precondition clause.
		require
			same_context: a_clause.context = smt.context
		do
			preconditions.extend (a_clause)
		ensure
			added: preconditions.count = old preconditions.count + 1
		end

	ensure_that (a_clause: SMT_EXPR)
			-- Add a postcondition clause.
		require
			same_context: a_clause.context = smt.context
		do
			postconditions.extend (a_clause)
		ensure
			added: postconditions.count = old postconditions.count + 1
		end

	invariant_that (a_clause: SMT_EXPR)
			-- Add a class-invariant clause.
		require
			same_context: a_clause.context = smt.context
		do
			invariants.extend (a_clause)
		ensure
			added: invariants.count = old invariants.count + 1
		end

feature -- Composed formulas

	precondition: SMT_EXPR
			-- Conjunction of all require clauses (true when none).
		do
			Result := conjunction (preconditions)
		end

	postcondition: SMT_EXPR
			-- Conjunction of all ensure clauses (true when none).
		do
			Result := conjunction (postconditions)
		end

	class_invariant: SMT_EXPR
			-- Conjunction of all invariant clauses (true when none).
		do
			Result := conjunction (invariants)
		end

	all_conditions: SMT_EXPR
			-- pre and post and invariant.
		do
			Result := precondition.conjoined (postcondition).conjoined (class_invariant)
		end

	obligation: SMT_EXPR
			-- The core verification obligation: post and invariant hold
			-- (given the precondition and any assignment under test).
		do
			Result := postcondition.conjoined (class_invariant)
		end

feature {NONE} -- Implementation

	conjunction (a_clauses: ARRAYED_LIST [SMT_EXPR]): SMT_EXPR
			-- Fold `a_clauses' with `and'; `true' when empty.
		do
			Result := smt.true_expr
			across a_clauses as ic loop
				Result := Result.conjoined (ic)
			end
		ensure
			same_context: Result.context = smt.context
		end

invariant
	smt_attached: smt /= Void
	name_not_empty: not name.is_empty

end
