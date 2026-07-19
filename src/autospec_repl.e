note
	description: "[
		Interactive AutoSpec: a contract playground. You declare the result
		variables, type require/ensure/invariant clauses, ask Z3 whether the
		spec is feasible or vacuous, `test' candidate clauses without keeping
		them, and `harden' -- run the deterministic diagnostic battery and,
		when a live model oracle is configured, ask it to strengthen a vacuous
		spec until Z3 accepts.

		Two tiers: the Z3 commands need no model; `harden' auto-strengthens only
		when created via `make_live'. Reads commands from standard input until
		`quit' or end-of-input.
	]"
	author: "Larry Rix"

class
	AUTOSPEC_REPL

create
	make, make_live

feature {NONE} -- Initialization

	make (a_autospec: SIMPLE_AUTOSPEC)
			-- A Z3-only REPL: `harden' reports diagnostics but cannot auto-strengthen.
		require
			autospec_attached: a_autospec /= Void
		do
			autospec := a_autospec
			create output_name_list.make (8)
			create parser.make (a_autospec.smt)
			spec := a_autospec.new_spec ("repl")
		end

	make_live (a_autospec: SIMPLE_AUTOSPEC; a_oracle: AUTOSPEC_ORACLE)
			-- A REPL whose `harden' can ask `a_oracle' to strengthen the spec.
		require
			autospec_attached: a_autospec /= Void
			oracle_attached: a_oracle /= Void
		do
			make (a_autospec)
			oracle := a_oracle
		ensure
			live: has_oracle
		end

feature -- Access

	autospec: SIMPLE_AUTOSPEC
	spec: AUTOSPEC_SPEC
	parser: AUTOSPEC_EXPR_PARSER
	output_name_list: ARRAYED_LIST [STRING]
			-- Names of the declared result variables (parallel to `spec.outputs').
	oracle: detachable AUTOSPEC_ORACLE

	has_oracle: BOOLEAN
			-- Is a live model configured for auto-strengthening?
		do
			Result := oracle /= Void
		end

feature -- Loop

	run
			-- Read and dispatch commands until `quit' or end-of-input.
		local
			l_line, l_cmd, l_arg: STRING
			l_done: BOOLEAN
			l_sp: INTEGER
		do
			print_banner
			from until l_done loop
				io.put_string ("AutoSpec> ")
				io.read_line
				l_line := io.last_string.twin
				l_line.left_adjust
				l_line.right_adjust
				if l_line.is_empty then
					if io.input.end_of_file then l_done := True end
				else
					l_sp := l_line.index_of (' ', 1)
					if l_sp > 0 then
						l_cmd := l_line.substring (1, l_sp - 1)
						l_arg := l_line.substring (l_sp + 1, l_line.count)
						l_arg.left_adjust
						l_arg.right_adjust
					else
						l_cmd := l_line.twin
						l_arg := ""
					end
					l_cmd.to_lower
					if l_cmd.same_string ("quit") or l_cmd.same_string ("exit") or l_cmd.same_string ("q") then
						l_done := True
					else
						dispatch (l_cmd, l_arg)
						if io.input.end_of_file then l_done := True end
					end
				end
			end
			io.put_string ("bye.%N")
		end

feature {NONE} -- Dispatch

	dispatch (a_cmd, a_arg: STRING)
			-- Run one command.
		do
			if a_cmd.same_string ("outputs") or a_cmd.same_string ("output") then
				declare_outputs (a_arg)
			elseif a_cmd.same_string ("require") or a_cmd.same_string ("req") then
				add_clause (a_arg, "require")
			elseif a_cmd.same_string ("ensure") or a_cmd.same_string ("ens") then
				add_clause (a_arg, "ensure")
			elseif a_cmd.same_string ("invariant") or a_cmd.same_string ("inv") then
				add_clause (a_arg, "invariant")
			elseif a_cmd.same_string ("test") then
				test_clause (a_arg)
			elseif a_cmd.same_string ("check") or a_cmd.same_string ("status") or a_cmd.same_string ("st") then
				report_status
			elseif a_cmd.same_string ("show") then
				show_spec
			elseif a_cmd.same_string ("harden") then
				do_harden
			elseif a_cmd.same_string ("reset") or a_cmd.same_string ("new") then
				reset_spec
			elseif a_cmd.same_string ("help") or a_cmd.same_string ("?") then
				print_help
			else
				io.put_string ("  ? unknown command '" + a_cmd + "' -- type 'help'.%N")
			end
		end

feature {NONE} -- Commands

	declare_outputs (a_arg: STRING)
			-- Declare each space-separated name in `a_arg' as a result variable.
		local
			l_names: LIST [STRING]
			l_name: STRING
			l_var: SMT_EXPR
			l_added: INTEGER
		do
			if a_arg.is_empty then
				io.put_string ("  usage: outputs <name> [name ...]%N")
			else
				l_names := a_arg.split (' ')
				across l_names as ic loop
					l_name := ic.twin
					l_name.left_adjust
					l_name.right_adjust
					if not l_name.is_empty and then is_identifier (l_name) and then not output_name_list.has (l_name) then
						l_var := autospec.smt.real_const (l_name)
						output_name_list.extend (l_name)
						spec.declare_output (l_var)
						l_added := l_added + 1
					elseif not l_name.is_empty and then not is_identifier (l_name) then
						io.put_string ("  skipped '" + l_name + "' (not a simple name)%N")
					end
				end
				io.put_string ("  outputs: " + output_names + " (" + l_added.out + " added)%N")
			end
		end

	add_clause (a_text, a_kind: STRING)
			-- Parse `a_text' and add it as an `a_kind' clause.
		do
			if a_text.is_empty then
				io.put_string ("  usage: " + a_kind + " <boolean expression>%N")
			elseif attached parser.parse_clause (a_text) as al_clause then
				if parser.produced_boolean then
					if a_kind.same_string ("require") then
						spec.require_that (al_clause)
					elseif a_kind.same_string ("ensure") then
						spec.ensure_that (al_clause)
					else
						spec.invariant_that (al_clause)
					end
					io.put_string ("  added " + a_kind + ": " + al_clause.to_string + "%N")
				else
					io.put_string ("  not a condition: an " + a_kind + " clause must be boolean.%N")
				end
			else
				io.put_string ("  parse error: " + parser.last_error + "%N")
			end
		end

	test_clause (a_text: STRING)
			-- Tentatively add `a_text' as an ensure clause, report its effect,
			-- then withdraw it (does not keep the clause).
		local
			l_sat, l_vac: BOOLEAN
		do
			if a_text.is_empty then
				io.put_string ("  usage: test <boolean expression>%N")
			elseif attached parser.parse_clause (a_text) as al_clause then
				if parser.produced_boolean then
					spec.ensure_that (al_clause)
					l_sat := autospec.is_obligation_satisfiable (spec)
					if attached trivial_assignment as al_triv then
						l_vac := autospec.admits (spec, al_triv)
					end
						-- Withdraw the tentative clause.
					spec.postconditions.finish
					spec.postconditions.remove
					if not l_sat then
						io.put_string ("  would make the obligation UNSATISFIABLE.%N")
					elseif l_vac then
						io.put_string ("  still VACUOUS -- admits the trivial result " + one_line (autospec.last_witness) + "%N")
					else
						io.put_string ("  OK -- feasible and rejects the trivial result. (not kept; use 'ensure' to add)%N")
					end
				else
					io.put_string ("  not a condition: 'test' expects a boolean expression.%N")
				end
			else
				io.put_string ("  parse error: " + parser.last_error + "%N")
			end
		end

	report_status
			-- Feasibility and vacuity of the current spec.
		do
			io.put_string ("  " + autospec.feasibility_report (spec) + "%N")
			if attached trivial_assignment as al_triv then
				if autospec.is_vacuous_for (spec, al_triv) then
					io.put_string ("  VACUOUS: the trivial result (all outputs = 0) satisfies it -- witness "
						+ one_line (autospec.last_witness) + "%N")
				else
					io.put_string ("  non-vacuous: the trivial result is rejected.%N")
				end
			else
				io.put_string ("  (declare outputs to enable the vacuity check)%N")
			end
		end

	show_spec
			-- Print the current outputs and clauses.
		do
			io.put_string ("  outputs:     " + output_names + "%N")
			io.put_string ("  require:     " + clause_list (spec.preconditions) + "%N")
			io.put_string ("  ensure:      " + clause_list (spec.postconditions) + "%N")
			io.put_string ("  invariant:   " + clause_list (spec.invariants) + "%N")
		end

	do_harden
			-- Auto-strengthen with the model (if configured), then run the
			-- deterministic diagnostic battery and print the verdict.
		local
			l_proposer: AUTOSPEC_PROPOSER
			l_session: AUTOSPEC_SESSION
		do
			if attached oracle as al_oracle then
				if attached trivial_assignment as al_triv then
					io.put_string ("  asking the model to strengthen the spec (Z3 checks each)...%N")
					create l_proposer.make (autospec, al_oracle)
					if attached l_proposer.strengthen_to_non_vacuous (spec, 6) then
						across l_proposer.attempts as ic loop
							io.put_string ("    " + ic + "%N")
						end
						io.put_string ("  kept: " + l_proposer.accepted_clause_text + "%N")
					else
						across l_proposer.attempts as ic loop
							io.put_string ("    " + ic + "%N")
						end
						io.put_string ("  the model did not find an accepted clause.%N")
					end
				else
					io.put_string ("  declare outputs first so the vacuity target is defined.%N")
				end
			end
			create l_session.make (autospec, spec)
			l_session.harden
			io.put_string (indent_block (l_session.report))
		end

	reset_spec
			-- Clear the spec and all declared outputs.
		do
			spec := autospec.new_spec ("repl")
			output_name_list.wipe_out
			create parser.make (autospec.smt)
			io.put_string ("  cleared.%N")
		end

feature {NONE} -- Helpers

	trivial_assignment: detachable SMT_EXPR
			-- Conjunction pinning every declared output to 0, or Void if none.
		local
			l_zero: SMT_EXPR
			l_first: BOOLEAN
		do
			if not spec.outputs.is_empty then
				l_zero := autospec.smt.real_value ("0")
				l_first := True
				across spec.outputs as ic loop
					if l_first then
						Result := ic.is_equal_to (l_zero)
						l_first := False
					elseif attached Result as al then
						Result := al.conjoined (ic.is_equal_to (l_zero))
					end
				end
			end
		end

	output_names: STRING
			-- Comma-separated declared output names.
		do
			create Result.make (32)
			across output_name_list as ic loop
				if not Result.is_empty then Result.append (", ") end
				Result.append (ic)
			end
			if Result.is_empty then Result.append ("(none)") end
		end

	clause_list (a_clauses: ARRAYED_LIST [SMT_EXPR]): STRING
			-- The clauses rendered as text, semicolon-separated.
		do
			create Result.make (48)
			across a_clauses as ic loop
				if not Result.is_empty then Result.append (" ; ") end
				Result.append (ic.to_string)
			end
			if Result.is_empty then Result.append ("(none)") end
		end

	one_line (a_text: STRING): STRING
			-- `a_text' with newlines collapsed to ", " (witnesses span lines).
		do
			Result := a_text.twin
			Result.replace_substring_all ("%R", "")
			Result.replace_substring_all ("%N", ", ")
			if Result.ends_with (", ") then Result.remove_tail (2) end
		end

	is_identifier (a_text: STRING): BOOLEAN
			-- Is `a_text' a simple Eiffel-style name (letter/underscore, then alnum)?
		local
			i: INTEGER
			c: CHARACTER
		do
			if not a_text.is_empty then
				c := a_text [1]
				Result := c.is_alpha or c = '_'
				from i := 2 until i > a_text.count or not Result loop
					c := a_text [i]
					Result := c.is_alpha or c.is_digit or c = '_'
					i := i + 1
				end
			end
		end

	indent_block (a_text: STRING): STRING
			-- `a_text' with two spaces before each line.
		local
			l_lines: LIST [STRING]
		do
			create Result.make (a_text.count + 16)
			l_lines := a_text.split ('%N')
			across l_lines as ic loop
				Result.append ("  ")
				Result.append (ic)
				Result.append_character ('%N')
			end
		end

	print_banner
			-- Opening lines.
		do
			io.put_string ("AutoSpec REPL -- an interactive contract playground%N")
			io.put_string ("===================================================%N")
			if has_oracle then
				io.put_string ("Model: connected (harden can auto-strengthen).%N")
			else
				io.put_string ("Model: none (Z3-only; harden reports diagnostics).%N")
			end
			io.put_string ("Type 'help' for commands, 'quit' to leave.%N%N")
		end

	print_help
			-- Command reference.
		do
			io.put_string ("  Commands:%N")
			io.put_string ("    outputs a b c        declare result variables%N")
			io.put_string ("    require <expr>       add a precondition clause%N")
			io.put_string ("    ensure <expr>        add a postcondition clause%N")
			io.put_string ("    invariant <expr>     add a class-invariant clause%N")
			io.put_string ("    test <expr>          try an ensure clause without keeping it%N")
			io.put_string ("    check                report feasibility and vacuity%N")
			io.put_string ("    show                 show the current spec%N")
			io.put_string ("    harden               diagnose (and, with a model, strengthen)%N")
			io.put_string ("    reset                clear the spec and outputs%N")
			io.put_string ("    quit                 leave%N")
			io.put_string ("  Operators: + - * < <= > >= = /= and or not%N")
		end

end
