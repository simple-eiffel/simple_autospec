note
	description: "AutoSpec demo: harden a 3-element sort spec from vacuous to bullet-proof"
	author: "Larry Rix"

class
	AUTOSPEC_APP

create
	make

feature {NONE} -- Initialization

	make
			-- With a file argument, mine that .e file's contracts; otherwise
			-- walk the built-in sort-spec hardening + brownfield demo.
		local
			l_args: ARGUMENTS_32
		do
			create l_args
			if l_args.argument_count >= 2 and then l_args.argument (1).same_string ("--scan") then
				scan_tree (l_args.argument (2).to_string_8)
			elseif l_args.argument_count >= 1 then
				mine_file (l_args.argument (1).to_string_8)
			else
				run_demo
			end
		end

	scan_tree (a_root: STRING)
			-- Audit every feature's contracts under `a_root' for dead/infeasible specs.
		local
			sc: AUTOSPEC_SCANNER
		do
			io.put_string ("AutoSpec contract audit: " + a_root + "%N")
			io.put_string ("=================================================%N%N")
			create sc.make
			sc.scan (a_root)
			io.put_string ("Files scanned:            " + sc.files_scanned.out + "%N")
			io.put_string ("Features with contracts:  " + sc.features_mined.out + "%N")
			io.put_string ("Clauses in decidable fragment: " + sc.clauses_kept.out + "%N")
			io.put_string ("Clauses skipped (out of fragment): " + sc.clauses_skipped.out + "%N%N")
			if sc.flagged.is_empty then
				io.put_string ("No DEAD preconditions found in the decidable fragment.%N")
			else
				io.put_string ("FLAGGED (" + sc.dead_count.out + " dead precondition(s)):%N")
				across sc.flagged as ic loop
					io.put_string ("  " + ic + "%N")
				end
			end
		end

	run_demo
			-- Walk the Socratic hardening of a sort specification.
		local
			asp: SIMPLE_AUTOSPEC
			weak, strong: AUTOSPEC_SPEC
			b1, b2, b3, dumb, good, one, three: SMT_EXPR
		do
			create asp.make
			b1 := asp.smt.int_const ("b1"); b2 := asp.smt.int_const ("b2"); b3 := asp.smt.int_const ("b3")
			one := asp.smt.int_value (1); three := asp.smt.int_value (3)
			dumb := b1.is_equal_to (asp.smt.int_value (0))
				.conjoined (b2.is_equal_to (asp.smt.int_value (0)))
				.conjoined (b3.is_equal_to (asp.smt.int_value (0)))
			good := b1.is_equal_to (one).conjoined (b2.is_equal_to (asp.smt.int_value (2))).conjoined (b3.is_equal_to (three))

			io.put_string ("AutoSpec demo: hardening a sort of {1,2,3}%N")
			io.put_string ("==========================================%N%N")

				-- Round 1: weak spec (is_sorted only).
			weak := asp.new_spec ("sort (weak)")
			weak.ensure_that (b1.at_most (b2))
			weak.ensure_that (b2.at_most (b3))
			io.put_string ("Round 1 -- ensure: b1<=b2<=b3 only%N")
			io.put_string ("  feasible?          " + yn (asp.is_feasible (weak)) + "%N")
			io.put_string ("  VACUOUS (accepts the dumb 0,0,0)?  " + yn (asp.is_vacuous_for (weak, dumb)) + "%N")
			io.put_string ("  -> Socratic prompt: your spec accepts (0,0,0), which is not a%N")
			io.put_string ("     permutation of the input. Add a conservation law.%N%N")

				-- Round 2: strong spec (add permutation of {1,2,3}).
			strong := asp.new_spec ("sort (strong)")
			strong.ensure_that (b1.at_most (b2))
			strong.ensure_that (b2.at_most (b3))
			strong.ensure_that (asp.smt.all_distinct (<<b1, b2, b3>>))
			strong.ensure_that (one.at_most (b1)); strong.ensure_that (b1.at_most (three))
			strong.ensure_that (one.at_most (b2)); strong.ensure_that (b2.at_most (three))
			strong.ensure_that (one.at_most (b3)); strong.ensure_that (b3.at_most (three))
			io.put_string ("Round 2 -- add: distinct and each in [1,3] (permutation)%N")
			io.put_string ("  feasible?          " + yn (asp.is_feasible (strong)) + "%N")
			io.put_string ("  VACUOUS for 0,0,0? " + yn (asp.is_vacuous_for (strong, dumb)) + "%N")
			io.put_string ("  admits the correct (1,2,3)?  " + yn (asp.admits (strong, good)) + "%N")
			io.put_string ("  strengthens the weak spec?   " + yn (asp.strengthens (strong, weak)) + "%N%N")

			io.put_string ("Result: the strengthened spec is feasible, non-vacuous, admits the%N")
			io.put_string ("right answer, and subsumes the weak one -- bullet-proof, checked by Z3.%N")

			core_loop_demo
			proposer_demo
			brownfield_demo
		end

	proposer_demo
			-- Show the propose/dispose loop repairing a vacuous spec (scripted
			-- oracle stands in for a local LLM; the loop and Z3 checks are real).
		local
			asp: SIMPLE_AUTOSPEC
			spec: AUTOSPEC_SPEC
			oracle: AUTOSPEC_SCRIPTED_ORACLE
			proposer: AUTOSPEC_PROPOSER
			session: AUTOSPEC_SESSION
			b1, b2, b3: SMT_EXPR
		do
			io.put_string ("%N%NProposer loop: LLM proposes / Z3 disposes (with feedback)%N")
			io.put_string ("=========================================================%N%N")
			create asp.make
			b1 := asp.smt.real_const ("b1"); b2 := asp.smt.real_const ("b2"); b3 := asp.smt.real_const ("b3")
			spec := asp.new_spec ("sort")
			spec.ensure_that (b1.at_most (b2)); spec.ensure_that (b2.at_most (b3))
			spec.declare_output (b1); spec.declare_output (b2); spec.declare_output (b3)
			io.put_string ("Vacuous spec: ensure b1<=b2<=b3 only (accepts the trivial 0,0,0).%N")
			io.put_string ("Oracle (scripted, stands in for Qwen3-Coder on llama.cpp/Vulkan):%N%N")
			create oracle.make (<<"b1 >= 0", "b1 = 1 and b2 = 2 and b3 = 3">>)
			create proposer.make (asp, oracle)
			if proposer.strengthen_to_non_vacuous (spec, 5) /= Void then end
			across proposer.attempts as ic loop
				io.put_string ("  " + ic + "%N")
			end
			io.put_string ("%NAfter the accepted clause, harden re-checks:%N")
			create session.make (asp, spec)
			session.harden
			io.put_string (session.report)
		end

	core_loop_demo
			-- Show the harden battery producing Socratic findings automatically.
		local
			asp: SIMPLE_AUTOSPEC
			weak, strong: AUTOSPEC_SPEC
			session: AUTOSPEC_SESSION
			b1, b2, b3, one, three: SMT_EXPR
		do
			io.put_string ("%N%NAutoSpec core loop: harden() emits Socratic findings%N")
			io.put_string ("====================================================%N%N")
			create asp.make
			b1 := asp.smt.int_const ("b1"); b2 := asp.smt.int_const ("b2"); b3 := asp.smt.int_const ("b3")
			one := asp.smt.int_value (1); three := asp.smt.int_value (3)

			weak := asp.new_spec ("sort (weak)")
			weak.ensure_that (b1.at_most (b2))
			weak.ensure_that (b2.at_most (b3))
			weak.declare_output (b1); weak.declare_output (b2); weak.declare_output (b3)
			create session.make (asp, weak)
			session.harden
			io.put_string (session.report)

			strong := asp.new_spec ("sort (strong)")
			strong.ensure_that (b1.at_most (b2)); strong.ensure_that (b2.at_most (b3))
			strong.ensure_that (asp.smt.all_distinct (<<b1, b2, b3>>))
			strong.ensure_that (one.at_most (b1)); strong.ensure_that (b1.at_most (three))
			strong.ensure_that (one.at_most (b2)); strong.ensure_that (b2.at_most (three))
			strong.ensure_that (one.at_most (b3)); strong.ensure_that (b3.at_most (three))
			strong.declare_output (b1); strong.declare_output (b2); strong.declare_output (b3)
			create session.make (asp, strong)
			session.harden
			io.put_string (session.report)
		end

	brownfield_demo
			-- Mine contracts out of real-shaped Eiffel source and check them.
		local
			asp: SIMPLE_AUTOSPEC
			miner: AUTOSPEC_MINER
			mined: ARRAYED_LIST [AUTOSPEC_MINED]
		do
			io.put_string ("%N%NBrownfield mining: contracts -> candidate specs%N")
			io.put_string ("===============================================%N%N")
			create asp.make
			create miner.make (asp)
			mined := miner.mine (sample_source)
			across mined as ic loop
				io.put_string ("Feature '" + ic.feature_name + "':%N")
				io.put_string ("  translated " + ic.translated_count.out + " clause(s) into the decidable fragment:%N")
				across ic.kept as ck loop io.put_string ("    + " + ck + "%N") end
				if ic.skipped_count > 0 then
					io.put_string ("  skipped " + ic.skipped_count.out + " clause(s) out of fragment (recorded, not faked):%N")
					across ic.skipped as sk loop io.put_string ("    - " + sk + "%N") end
				end
				io.put_string ("  " + asp.feasibility_report (ic.spec) + "%N%N")
			end
			io.put_string ("Every mined clause is a SEED; AutoSpec then interrogates it with Z3.%N")
		end

	mine_file (a_path: STRING)
			-- Mine the contracts of the Eiffel file at `a_path' and report.
		local
			asp: SIMPLE_AUTOSPEC
			miner: AUTOSPEC_MINER
			mined: ARRAYED_LIST [AUTOSPEC_MINED]
			l_src: STRING
			l_total_kept, l_total_skipped, l_dead, l_infeasible: INTEGER
		do
			l_src := read_source (a_path)
			if l_src.is_empty then
				io.put_string ("Cannot read or empty: " + a_path + "%N")
			else
				io.put_string ("AutoSpec mining: " + a_path + "%N")
				io.put_string ("========================================%N%N")
				create asp.make
				create miner.make (asp)
				mined := miner.mine (l_src)
				across mined as ic loop
					l_total_kept := l_total_kept + ic.translated_count
					l_total_skipped := l_total_skipped + ic.skipped_count
					io.put_string (asp.feasibility_report (ic.spec)
						+ "  [" + ic.translated_count.out + " kept, " + ic.skipped_count.out + " skipped]%N")
					if not asp.is_precondition_live (ic.spec) then
						l_dead := l_dead + 1
					elseif not asp.is_feasible (ic.spec) then
						l_infeasible := l_infeasible + 1
					end
				end
				io.put_string ("%N" + mined.count.out + " feature(s) with translatable contracts; "
					+ l_total_kept.out + " clauses in-fragment, " + l_total_skipped.out + " skipped.%N")
				if l_dead + l_infeasible > 0 then
					io.put_string ("FLAGGED: " + l_dead.out + " dead precondition(s), "
						+ l_infeasible.out + " infeasible spec(s).%N")
				else
					io.put_string ("No dead or infeasible contracts found in the decidable fragment.%N")
				end
			end
		end

	read_source (a_path: STRING): STRING
			-- Full text of the file at `a_path' ("" when unreadable).
		local
			f: PLAIN_TEXT_FILE
		do
			create Result.make (4096)
			create f.make_with_name (a_path)
			if f.exists and then f.is_readable then
				f.open_read
				from until f.end_of_file loop
					f.read_line
					Result.append (f.last_string)
					Result.append_character ('%N')
				end
				f.close
			end
		ensure
			result_attached: Result /= Void
		end

	sample_source: STRING
			-- Real-shaped Eiffel with a feasible feature and a contradictory one.
		do
			Result := "class SAMPLE%N" + "feature%N"
				+ "%Tset_level (a_level: INTEGER)%N"
				+ "%T%Trequire%N"
				+ "%T%T%Tin_range: a_level >= 1 and a_level <= 9%N"
				+ "%T%Tdo%N"
				+ "%T%T%Tlevel := a_level%N"
				+ "%T%Tensure%N"
				+ "%T%T%Tset: level = a_level%N"
				+ "%T%Tend%N"
				+ "%Tbad_seek (a_pos: INTEGER)%N"
				+ "%T%Trequire%N"
				+ "%T%T%Tlow: a_pos > 100%N"
				+ "%T%T%Thigh: a_pos < 10%N"
				+ "%T%Tdo%N"
				+ "%T%Tend%N"
				+ "end%N"
		end

feature {NONE} -- Implementation

	yn (a: BOOLEAN): STRING
		do
			if a then Result := "yes" else Result := "no" end
		end

end
