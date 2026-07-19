note
	description: "[
		Conversational AutoSpec: describe a feature in plain English and the
		local model turns it into a formal specification, which Z3 checks for you.
		You never declare variables or type math -- you talk, and the results come
		back in prose (feasible? vacuous? does it hold together?). Refine by saying
		what you want changed; 'show' reveals the formal contract; 'accept' keeps it.

		The model is asked to emit a strict OUTPUT/REQUIRE/ENSURE form where each
		clause pairs a formal condition (in the decidable fragment) with a plain-
		English restatement. The formal half feeds Z3; the English half is shown.
		Requires a model oracle -- natural language is the whole point.
	]"
	author: "Larry Rix"

class
	AUTOSPEC_CHAT

create
	make

feature {NONE} -- Initialization

	make (a_autospec: SIMPLE_AUTOSPEC; a_oracle: AUTOSPEC_ORACLE)
			-- Conversational session backed by `a_oracle' (the model), checked by Z3.
		require
			autospec_attached: a_autospec /= Void
			oracle_attached: a_oracle /= Void
		do
			autospec := a_autospec
			oracle := a_oracle
			create parser.make (a_autospec.smt)
			working_output := ""
			create clause_kinds.make (6)
			create clause_formals.make (6)
			create clause_english.make (6)
		end

feature -- Access

	autospec: SIMPLE_AUTOSPEC
	oracle: AUTOSPEC_ORACLE
	parser: AUTOSPEC_EXPR_PARSER

	working_output: STRING
			-- Name the model chose for the result variable.
	clause_kinds: ARRAYED_LIST [STRING]
			-- "require" / "ensure" for each drafted clause (parallel lists).
	clause_formals: ARRAYED_LIST [STRING]
	clause_english: ARRAYED_LIST [STRING]
	has_draft: BOOLEAN
			-- Is there a current drafted spec?

feature -- Loop

	run
			-- Converse until `quit' or end-of-input.
		local
			l_line, l_first: STRING
			l_done: BOOLEAN
			l_sp: INTEGER
		do
			print_banner
			from until l_done loop
				io.put_string ("You> ")
				io.read_line
				l_line := io.last_string.twin
				l_line.left_adjust
				l_line.right_adjust
				if l_line.is_empty then
					if io.input.end_of_file then l_done := True end
				else
					l_sp := l_line.index_of (' ', 1)
					if l_sp > 0 then l_first := l_line.substring (1, l_sp - 1) else l_first := l_line.twin end
					l_first.to_lower
					if l_first.same_string ("quit") or l_first.same_string ("exit") or l_first.same_string ("q") then
						l_done := True
					elseif l_first.same_string ("accept") or l_first.same_string ("done") or l_first.same_string ("ok") then
						do_accept
					elseif l_first.same_string ("show") then
						show_math
					elseif l_first.same_string ("reset") or l_first.same_string ("new") then
						reset_all
					elseif l_first.same_string ("help") or l_first.same_string ("?") then
						print_help
					else
						converse (l_line)
					end
					if io.input.end_of_file then l_done := True end
				end
			end
			io.put_string ("bye.%N")
		end

feature {NONE} -- Conversation

	converse (a_text: STRING)
			-- Send `a_text' (a description or a refinement) to the model, parse the
			-- specification it returns, and report Z3's verdict in prose.
		local
			l_reply: STRING
		do
			io.put_string ("  thinking...%N")
			l_reply := oracle.propose (build_prompt (a_text))
			if parse_reply (l_reply) then
				present_draft
			else
				io.put_string ("  I couldn't turn that into a clean spec. Try naming the result and%N")
				io.put_string ("  what must be true about it -- e.g. 'the smaller of two numbers a and b'.%N")
			end
		end

	present_draft
			-- Build the spec from the current draft, print the English readings,
			-- and translate Z3's verdict into a sentence.
		local
			l_spec: AUTOSPEC_SPEC
			l_skipped: INTEGER
			i: INTEGER
			l_feasible, l_vacuous: BOOLEAN
		do
			l_spec := autospec.new_spec ("chat")
			l_spec.declare_output (autospec.smt.real_const (working_output))
			from i := 1 until i > clause_formals.count loop
				if attached parser.parse_clause (clause_formals [i]) as al and then parser.produced_boolean then
					if clause_kinds [i].same_string ("require") then
						l_spec.require_that (al)
					else
						l_spec.ensure_that (al)
					end
				else
					l_skipped := l_skipped + 1
				end
				i := i + 1
			end

			io.put_string ("%N  Here's what it would guarantee:%N")
			from i := 1 until i > clause_english.count loop
				if clause_kinds [i].same_string ("require") then
					io.put_string ("   - (about the inputs) " + clause_english [i] + "%N")
				else
					io.put_string ("   - " + clause_english [i] + "%N")
				end
				i := i + 1
			end

			l_feasible := autospec.is_feasible (l_spec)
			if l_feasible and then attached trivial_for (l_spec) as al_triv then
					-- Sound vacuity for input-dependent queries: the trivial result
					-- (output = 0) is "trivially acceptable" only if it satisfies the
					-- obligation for EVERY input, not merely some. That is validity,
					-- not satisfiability -- so prove ((pre and out=0) implies obligation)
					-- rather than checking `admits' (which asks only "for some input").
				autospec.smt.reset
				l_vacuous := autospec.smt.prove (l_spec.precondition.conjoined (al_triv).entails (l_spec.obligation))
			end
			io.put_string ("%N")
			if not l_feasible then
				io.put_string ("  Z3 check: these clash -- there is no result that can satisfy them all%N")
				io.put_string ("  at once. Something has to give; tell me which part matters more.%N")
			elseif l_vacuous then
				io.put_string ("  Z3 check: it holds, but a lazy 'always return 0' answer would already%N")
				io.put_string ("  pass it -- so it is under-constrained. Tell me more about the result.%N")
			else
				io.put_string ("  Z3 check: it holds together and is NOT vacuous -- a trivial answer would%N")
				io.put_string ("  fail it. Looks solid. Say 'accept', 'show' the math, or refine it.%N")
			end
			if l_skipped > 0 then
				io.put_string ("  (I set aside " + l_skipped.out + " clause(s) the model phrased outside the math I can check.)%N")
			end
		end

	do_accept
			-- Confirm the current draft as the human's chosen spec.
		do
			if has_draft then
				io.put_string ("%N  Accepted. Your specification for '" + working_output + "':%N")
				print_readings
				io.put_string ("  Describe another feature, or 'quit'.%N")
			else
				io.put_string ("  Nothing to accept yet -- describe a feature first.%N")
			end
		end

	show_math
			-- Reveal the formal contract behind the current draft.
		local
			i: INTEGER
		do
			if has_draft then
				io.put_string ("  Formal contract (result = " + working_output + "):%N")
				from i := 1 until i > clause_formals.count loop
					io.put_string ("    " + clause_kinds [i] + " " + clause_formals [i] + "%N")
					i := i + 1
				end
			else
				io.put_string ("  No draft yet.%N")
			end
		end

	reset_all
			-- Discard the current draft.
		do
			working_output := ""
			clause_kinds.wipe_out
			clause_formals.wipe_out
			clause_english.wipe_out
			has_draft := False
			io.put_string ("  cleared -- describe a new feature.%N")
		end

feature {NONE} -- Model I/O

	build_prompt (a_text: STRING): STRING
			-- The instruction sent to the model for `a_text'.
		local
			i: INTEGER
		do
			create Result.make (700)
			Result.append ("You turn a plain-English description of a function into a formal specification.%N")
			Result.append ("Reply ONLY with lines in exactly this format, nothing else:%N")
			Result.append ("OUTPUT: <one short name for the result>%N")
			Result.append ("ENSURE: <condition> | <plain-English restatement>%N")
			Result.append ("REQUIRE: <condition on the inputs> | <plain-English restatement>%N")
			Result.append ("Give one or more ENSURE lines; use REQUIRE only if the inputs must be limited.%N")
			Result.append ("A <condition> may use ONLY names, whole numbers, parentheses, and these operators:%N")
			Result.append ("  + - *   = /= < <= > >=   and  or  not  implies  xor%N")
			Result.append ("No function calls, no words inside a condition, no quotes, no code fences.%N%N")
			Result.append ("Example -- Description: return the larger of two numbers a and b%N")
			Result.append ("OUTPUT: r%N")
			Result.append ("ENSURE: r >= a | the result is at least as large as a%N")
			Result.append ("ENSURE: r >= b | the result is at least as large as b%N")
			Result.append ("ENSURE: r = a or r = b | the result is one of the two inputs%N%N")
			if has_draft then
				Result.append ("The current specification is:%N")
				from i := 1 until i > clause_formals.count loop
					Result.append ("  " + clause_kinds [i] + " " + clause_formals [i] + "%N")
					i := i + 1
				end
				Result.append ("The user now says: " + a_text + "%N")
				Result.append ("Reply with the FULL updated specification in the same format.%N")
			else
				Result.append ("Description: " + a_text + "%N")
			end
		end

	parse_reply (a_reply: STRING): BOOLEAN
			-- Parse the model's OUTPUT/REQUIRE/ENSURE lines into a fresh draft.
			-- True (and the draft is replaced) only if an output and at least one
			-- clause were found; otherwise the previous draft is left intact.
		local
			l_lines: LIST [STRING]
			l_line, l_rest, l_out: STRING
			l_kinds, l_formals, l_english: ARRAYED_LIST [STRING]
			l_bar: INTEGER
		do
			create l_kinds.make (6)
			create l_formals.make (6)
			create l_english.make (6)
			l_out := ""
			l_lines := a_reply.split ('%N')
			across l_lines as ic loop
				l_line := ic.twin
				l_line.prune_all ('%R')
				l_line.left_adjust
				l_line.right_adjust
				if line_starts (l_line, "output:") then
					l_rest := l_line.substring (8, l_line.count)
					l_rest.left_adjust
					l_out := first_token (l_rest)
				elseif line_starts (l_line, "ensure:") or line_starts (l_line, "require:") then
					if line_starts (l_line, "ensure:") then
						l_rest := l_line.substring (8, l_line.count)
						l_kinds.extend ("ensure")
					else
						l_rest := l_line.substring (9, l_line.count)
						l_kinds.extend ("require")
					end
					l_rest.left_adjust
					l_bar := l_rest.index_of ('|', 1)
					if l_bar > 0 then
						l_formals.extend (trimmed (l_rest.substring (1, l_bar - 1)))
						l_english.extend (trimmed (l_rest.substring (l_bar + 1, l_rest.count)))
					else
						l_formals.extend (trimmed (l_rest))
						l_english.extend (trimmed (l_rest))
					end
				end
			end
			if not l_out.is_empty and then not l_formals.is_empty then
				working_output := l_out
				clause_kinds := l_kinds
				clause_formals := l_formals
				clause_english := l_english
				has_draft := True
				Result := True
			end
		end

feature {NONE} -- Helpers

	trivial_for (a_spec: AUTOSPEC_SPEC): detachable SMT_EXPR
			-- The output pinned to 0 (the vacuity probe), or Void if no output.
		local
			l_first: BOOLEAN
			l_zero: SMT_EXPR
		do
			l_zero := autospec.smt.real_value ("0")
			l_first := True
			across a_spec.outputs as ic loop
				if l_first then
					Result := ic.is_equal_to (l_zero)
					l_first := False
				elseif attached Result as al then
					Result := al.conjoined (ic.is_equal_to (l_zero))
				end
			end
		end

	print_readings
			-- Print the plain-English guarantees of the current draft.
		local
			i: INTEGER
		do
			from i := 1 until i > clause_english.count loop
				io.put_string ("   - " + clause_english [i] + "%N")
				i := i + 1
			end
		end

	line_starts (a_line, a_prefix: STRING): BOOLEAN
			-- Does `a_line' start with `a_prefix' (case-insensitive)?
		do
			if a_line.count >= a_prefix.count then
				Result := a_line.substring (1, a_prefix.count).as_lower.same_string (a_prefix)
			end
		end

	first_token (a_text: STRING): STRING
			-- The first whitespace/comma-delimited token of `a_text'.
		local
			i: INTEGER
			c: CHARACTER
		do
			create Result.make (16)
			from i := 1 until i > a_text.count loop
				c := a_text [i]
				if c = ' ' or c = ',' or c = '%T' then
					i := a_text.count + 1
				else
					Result.append_character (c)
					i := i + 1
				end
			end
		end

	trimmed (a_text: STRING): STRING
			-- `a_text' with surrounding whitespace removed.
		do
			Result := a_text.twin
			Result.left_adjust
			Result.right_adjust
		end

	print_banner
			-- Opening lines.
		do
			io.put_string ("AutoSpec -- describe a feature, I'll spec it and Z3 will check it%N")
			io.put_string ("================================================================%N")
			io.put_string ("Just say what a function should do, in plain words. Examples:%N")
			io.put_string ("  the larger of two numbers%N")
			io.put_string ("  clamp a number between 0 and 100%N")
			io.put_string ("Then refine ('it can't be negative'), 'show' the math, 'accept', or 'quit'.%N%N")
		end

	print_help
			-- Command reference.
		do
			io.put_string ("  Describe a function in plain English and I turn it into a checked spec.%N")
			io.put_string ("  Anything that isn't one of these words is treated as a description:%N")
			io.put_string ("    show     reveal the formal contract%N")
			io.put_string ("    accept   keep the current spec%N")
			io.put_string ("    reset    start over%N")
			io.put_string ("    quit     leave%N")
		end

end
