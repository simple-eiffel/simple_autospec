note
	description: "[
		The propose/dispose loop, closed. Given a spec that AutoSpec has flagged
		vacuous, the proposer asks an oracle for a candidate conservation clause,
		parses it (AUTOSPEC_EXPR_PARSER), and checks it with Z3: does adding it
		still leave the spec feasible AND no longer vacuous? On rejection it
		feeds the reason -- an unparseable clause, or the surviving trivial
		witness -- back into the next prompt and retries.

		This is the research-validated pattern (LLM proposes / SMT disposes with
		counterexample feedback). The oracle is never trusted to be correct; Z3
		accepts or rejects every candidate. A weak or local model is sufficient
		because the feedback loop, not the model, does the converging.
	]"
	author: "Larry Rix"

class
	AUTOSPEC_PROPOSER

create
	make

feature {NONE} -- Initialization

	make (a_autospec: SIMPLE_AUTOSPEC; a_oracle: AUTOSPEC_ORACLE)
			-- Create a proposer using `a_oracle' to suggest clauses, checked by `a_autospec'.
		do
			autospec := a_autospec
			oracle := a_oracle
			create attempts.make (4)
		end

feature -- Access

	autospec: SIMPLE_AUTOSPEC
	oracle: AUTOSPEC_ORACLE

	attempts: ARRAYED_LIST [STRING]
			-- One line per attempt (candidate + verdict), for transparency.

	accepted_clause_text: STRING
			-- Text of the clause that was accepted ("" if none).
		attribute
			create Result.make_empty
		end

feature -- The loop

	strengthen_to_non_vacuous (a_spec: AUTOSPEC_SPEC; a_max_attempts: INTEGER): detachable SMT_EXPR
			-- Find and add a postcondition clause that makes `a_spec' no longer
			-- vacuous while keeping it feasible. Returns the accepted clause, or
			-- Void if the oracle could not produce one within `a_max_attempts'.
		require
			same_solver: a_spec.smt = autospec.smt
			has_outputs: not a_spec.outputs.is_empty
			max_positive: a_max_attempts >= 1
		local
			l_parser: AUTOSPEC_EXPR_PARSER
			l_prompt, l_candidate: STRING
			l_attempt: INTEGER
			l_trivial: SMT_EXPR
		do
			attempts.wipe_out
			accepted_clause_text := ""
			create l_parser.make (autospec.smt)
			l_trivial := trivial_assignment (a_spec)
			from l_attempt := 1 until l_attempt > a_max_attempts or Result /= Void loop
				l_prompt := build_prompt (a_spec, l_trivial)
				l_candidate := oracle.propose (l_prompt)
				if l_candidate.is_empty then
					attempts.extend ("attempt " + l_attempt.out + ": oracle returned nothing")
					l_attempt := a_max_attempts + 1
				elseif attached l_parser.parse_clause (l_candidate) as al_clause then
						-- Tentatively add and re-check with Z3.
					a_spec.ensure_that (al_clause)
					if autospec.is_obligation_satisfiable (a_spec) and then not autospec.admits (a_spec, l_trivial) then
						attempts.extend ("attempt " + l_attempt.out + ": ACCEPTED '" + l_candidate + "'")
						accepted_clause_text := l_candidate
						Result := al_clause
					else
							-- Reject: undo, record why (feeds the next prompt).
						a_spec.postconditions.finish
						a_spec.postconditions.remove
						if not autospec.is_obligation_satisfiable (a_spec) then
							last_rejection := "'" + l_candidate + "' made the obligation unsatisfiable"
						else
							last_rejection := "'" + l_candidate + "' still admits the trivial result " + autospec.last_witness
						end
						attempts.extend ("attempt " + l_attempt.out + ": rejected -- " + last_rejection)
					end
				else
					last_rejection := "'" + l_candidate + "' is not a parseable boolean clause (" + l_parser.last_error + ")"
					attempts.extend ("attempt " + l_attempt.out + ": rejected -- " + last_rejection)
				end
				l_attempt := l_attempt + 1
			end
		ensure
			accepted_added: Result /= Void implies a_spec.postconditions.has (Result)
		end

feature {NONE} -- Implementation

	last_rejection: STRING
			-- Reason the previous candidate was rejected ("" initially).
		attribute
			create Result.make_empty
		end

	trivial_assignment (a_spec: AUTOSPEC_SPEC): SMT_EXPR
			-- The dumb result: every declared output = 0.
		local
			l_zero: SMT_EXPR
			l_first: BOOLEAN
		do
			l_zero := autospec.smt.real_value ("0")
			l_first := True
			Result := autospec.smt.true_expr
			across a_spec.outputs as ic loop
				if l_first then
					Result := ic.is_equal_to (l_zero)
					l_first := False
				else
					Result := Result.conjoined (ic.is_equal_to (l_zero))
				end
			end
		end

	build_prompt (a_spec: AUTOSPEC_SPEC; a_trivial: SMT_EXPR): STRING
			-- The instruction sent to the oracle, including any prior rejection.
		do
			create Result.make (400)
			Result.append ("You are hardening an Eiffel specification named '" + a_spec.name + "'.%N")
			Result.append ("Its current postcondition is under-constrained: a trivial result where every%N")
			Result.append ("output variable equals 0 wrongly satisfies it. Propose ONE additional Eiffel%N")
			Result.append ("boolean clause (a conservation law) that rejects that trivial result while%N")
			Result.append ("remaining satisfiable. Use only integer/boolean operators (+, -, *, <, <=, >,%N")
			Result.append (">=, =, /=, and, or, not, implies). Output the clause only, no explanation.%N")
			if not last_rejection.is_empty then
				Result.append ("Your previous attempt was rejected: " + last_rejection + "%N")
				Result.append ("Try a different, stronger clause.%N")
			end
		end

invariant
	autospec_attached: autospec /= Void
	oracle_attached: oracle /= Void

end
