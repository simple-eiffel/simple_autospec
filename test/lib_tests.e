note
	description: "[
		Tests for simple_autospec: the mechanical spec-hardening checks run for
		real through Z3. Centerpiece is the sort-spec vacuity story -- is_sorted
		alone is under-constrained, adding the permutation conservation law fixes
		it -- exactly the AutoSpec Socratic move, mechanized.
	]"
	author: "Larry Rix"

class
	LIB_TESTS

inherit
	TEST_SET_BASE

feature -- Feasibility / liveness

	test_infeasible_spec_detected
			-- ensure Result > 0 AND Result < 0 is unimplementable -- caught at spec time.
		local
			asp: SIMPLE_AUTOSPEC
			spec: AUTOSPEC_SPEC
			r, zero: SMT_EXPR
		do
			create asp.make
			r := asp.smt.int_const ("r"); zero := asp.smt.int_value (0)
			spec := asp.new_spec ("contradictory")
			spec.ensure_that (r.greater (zero))
			spec.ensure_that (r.less (zero))
			assert ("contradictory spec is NOT feasible", not asp.is_feasible (spec))
		end

	test_feasible_spec_accepted
			-- ensure Result >= 0 is implementable.
		local
			asp: SIMPLE_AUTOSPEC
			spec: AUTOSPEC_SPEC
			r, zero: SMT_EXPR
		do
			create asp.make
			r := asp.smt.int_const ("r"); zero := asp.smt.int_value (0)
			spec := asp.new_spec ("nonneg")
			spec.ensure_that (r.at_least (zero))
			assert ("nonneg spec is feasible", asp.is_feasible (spec))
		end

	test_dead_precondition_detected
			-- require x > 0 AND x < 0 -> the feature can never be called.
		local
			asp: SIMPLE_AUTOSPEC
			spec: AUTOSPEC_SPEC
			x, zero: SMT_EXPR
		do
			create asp.make
			x := asp.smt.int_const ("x"); zero := asp.smt.int_value (0)
			spec := asp.new_spec ("dead")
			spec.require_that (x.greater (zero))
			spec.require_that (x.less (zero))
			assert ("dead precondition detected", not asp.is_precondition_live (spec))
		end

	test_live_precondition_accepted
			-- require x > 0 is satisfiable.
		local
			asp: SIMPLE_AUTOSPEC
			spec: AUTOSPEC_SPEC
			x, zero: SMT_EXPR
		do
			create asp.make
			x := asp.smt.int_const ("x"); zero := asp.smt.int_value (0)
			spec := asp.new_spec ("live")
			spec.require_that (x.greater (zero))
			assert ("live precondition", asp.is_precondition_live (spec))
		end

feature -- Vacuity (the AutoSpec headline)

	test_weak_sort_spec_is_vacuous
			-- is_sorted ALONE admits the dumb result (0,0,0) for input {1,2,3}.
		local
			asp: SIMPLE_AUTOSPEC
			weak: AUTOSPEC_SPEC
			b1, b2, b3, dumb: SMT_EXPR
		do
			create asp.make
			b1 := asp.smt.int_const ("b1"); b2 := asp.smt.int_const ("b2"); b3 := asp.smt.int_const ("b3")
			weak := asp.new_spec ("sort_weak")
			weak.ensure_that (b1.at_most (b2))
			weak.ensure_that (b2.at_most (b3))
			dumb := all_zero (asp, b1, b2, b3)
			assert ("weak sort spec is vacuous (accepts 0,0,0)", asp.is_vacuous_for (weak, dumb))
		end

	test_strong_sort_spec_rejects_dumb
			-- Adding the permutation conservation law rejects (0,0,0).
		local
			asp: SIMPLE_AUTOSPEC
			strong: AUTOSPEC_SPEC
			b1, b2, b3, dumb: SMT_EXPR
		do
			create asp.make
			b1 := asp.smt.int_const ("b1"); b2 := asp.smt.int_const ("b2"); b3 := asp.smt.int_const ("b3")
			strong := sort_spec_strong (asp, b1, b2, b3)
			dumb := all_zero (asp, b1, b2, b3)
			assert ("strong sort spec is NOT vacuous", not asp.is_vacuous_for (strong, dumb))
		end

	test_strong_sort_spec_admits_correct_result
			-- The correct result (1,2,3) IS admitted by the strong spec.
		local
			asp: SIMPLE_AUTOSPEC
			strong: AUTOSPEC_SPEC
			b1, b2, b3, good: SMT_EXPR
		do
			create asp.make
			b1 := asp.smt.int_const ("b1"); b2 := asp.smt.int_const ("b2"); b3 := asp.smt.int_const ("b3")
			strong := sort_spec_strong (asp, b1, b2, b3)
			good := b1.is_equal_to (asp.smt.int_value (1))
				.conjoined (b2.is_equal_to (asp.smt.int_value (2)))
				.conjoined (b3.is_equal_to (asp.smt.int_value (3)))
			assert ("strong spec admits (1,2,3)", asp.admits (strong, good))
		end

feature -- Subsumption (pruning 1:M candidates)

	test_strong_strengthens_weak
			-- sorted+permutation entails sorted; not the other way round.
		local
			asp: SIMPLE_AUTOSPEC
			weak, strong: AUTOSPEC_SPEC
			b1, b2, b3: SMT_EXPR
		do
			create asp.make
			b1 := asp.smt.int_const ("b1"); b2 := asp.smt.int_const ("b2"); b3 := asp.smt.int_const ("b3")
			weak := asp.new_spec ("weak")
			weak.ensure_that (b1.at_most (b2))
			weak.ensure_that (b2.at_most (b3))
			strong := sort_spec_strong (asp, b1, b2, b3)
			assert ("strong strengthens weak", asp.strengthens (strong, weak))
			assert ("weak does NOT strengthen strong", not asp.strengthens (weak, strong))
		end

	test_bound_subsumption
			-- x > 5 strengthens x > 0.
		local
			asp: SIMPLE_AUTOSPEC
			tight, loose: AUTOSPEC_SPEC
			x: SMT_EXPR
		do
			create asp.make
			x := asp.smt.int_const ("x")
			tight := asp.new_spec ("gt5"); tight.require_that (x.greater (asp.smt.int_value (5)))
			loose := asp.new_spec ("gt0"); loose.require_that (x.greater (asp.smt.int_value (0)))
			assert ("x>5 strengthens x>0", asp.strengthens (tight, loose))
			assert ("x>0 does not strengthen x>5", not asp.strengthens (loose, tight))
		end

	test_feasibility_report
			-- The one-line report classifies specs.
		local
			asp: SIMPLE_AUTOSPEC
			bad: AUTOSPEC_SPEC
			r: SMT_EXPR
		do
			create asp.make
			r := asp.smt.int_const ("r")
			bad := asp.new_spec ("bad")
			bad.ensure_that (r.greater (asp.smt.int_value (0)))
			bad.ensure_that (r.less (asp.smt.int_value (0)))
			assert ("report flags infeasible", asp.feasibility_report (bad).has_substring ("INFEASIBLE"))
		end

feature -- Expression parser (decidable-fragment translation)

	test_parser_translates_arithmetic_clauses
			-- Real contract-shaped expressions translate to SMT_EXPR.
		local
			asp: SIMPLE_AUTOSPEC
			p: AUTOSPEC_EXPR_PARSER
		do
			create asp.make
			create p.make (asp.smt)
			assert ("a >= 1", p.parse_clause ("a >= 1") /= Void)
			assert ("1 <= k and k <= n", p.parse_clause ("1 <= k and k <= n") /= Void)
			assert ("n > 0 and n < 100", p.parse_clause ("n > 0 and n < 100") /= Void)
			assert ("count = capacity - 1 implies count < capacity",
				p.parse_clause ("count = capacity - 1 implies count < capacity") /= Void)
		end

	test_parser_rejects_out_of_fragment
			-- Dotted calls, old, strings are rejected (not faked).
		local
			asp: SIMPLE_AUTOSPEC
			p: AUTOSPEC_EXPR_PARSER
		do
			create asp.make
			create p.make (asp.smt)
			assert ("a.count rejected", p.parse_clause ("a.count >= 0") = Void)
			assert ("old x rejected", p.parse_clause ("value = old value + 1") = Void)
			assert ("not a boolean clause rejected", p.parse_clause ("n + 1") = Void)
		end

	test_parsed_clause_is_checkable
			-- A parsed clause feeds straight into the AutoSpec checks.
		local
			asp: SIMPLE_AUTOSPEC
			p: AUTOSPEC_EXPR_PARSER
			spec: AUTOSPEC_SPEC
		do
			create asp.make
			create p.make (asp.smt)
			spec := asp.new_spec ("parsed")
			if attached p.parse_clause ("x > 0") as al then spec.require_that (al) end
			if attached p.parse_clause ("x < 0") as al then spec.require_that (al) end
			assert ("contradictory parsed precondition is dead", not asp.is_precondition_live (spec))
		end

feature -- Brownfield miner

	test_miner_extracts_and_translates
			-- Mine a feature's contracts: translate the fragment, skip the rest.
		local
			asp: SIMPLE_AUTOSPEC
			miner: AUTOSPEC_MINER
			mined: ARRAYED_LIST [AUTOSPEC_MINED]
		do
			create asp.make
			create miner.make (asp)
			mined := miner.mine (toy_source)
			assert ("one feature mined", mined.count = 1)
			if not mined.is_empty then
				assert ("feature name is increment", mined.first.feature_name.same_string ("increment"))
				assert ("three clauses translated", mined.first.translated_count = 3)
				assert ("one clause skipped (old)", mined.first.skipped_count = 1)
				assert ("mined spec is feasible", asp.is_feasible (mined.first.spec))
			end
		end

	test_miner_detects_infeasible_real_contract
			-- A feature whose (translatable) contracts contradict is flagged.
		local
			asp: SIMPLE_AUTOSPEC
			miner: AUTOSPEC_MINER
			mined: ARRAYED_LIST [AUTOSPEC_MINED]
		do
			create asp.make
			create miner.make (asp)
			mined := miner.mine (contradictory_source)
			assert ("one feature mined", mined.count = 1)
			if not mined.is_empty then
				assert ("mined spec is NOT feasible", not asp.is_feasible (mined.first.spec))
			end
		end

feature {NONE} -- Miner fixtures

	toy_source: STRING
			-- A well-formed feature: 3 translatable clauses, 1 with `old' (skipped).
			-- Built with explicit tabs (%T) so indentation is exact.
		do
			Result := "class TOY%N" + "feature -- Element change%N"
				+ "%Tincrement (a_amount: INTEGER)%N"
				+ "%T%Trequire%N"
				+ "%T%T%Tpositive: a_amount > 0%N"
				+ "%T%T%Tbounded: a_amount <= 100%N"
				+ "%T%Tdo%N"
				+ "%T%T%Tvalue := value + a_amount%N"
				+ "%T%Tensure%N"
				+ "%T%T%Tstill_bounded: value <= max_value%N"
				+ "%T%T%Tgrown: value = old value + a_amount%N"
				+ "%T%Tend%N"
				+ "end%N"
		end

	contradictory_source: STRING
			-- A feature whose translatable preconditions contradict.
		do
			Result := "class BAD%N" + "feature%N"
				+ "%Tf (x: INTEGER)%N"
				+ "%T%Trequire%N"
				+ "%T%T%Tlo: x > 10%N"
				+ "%T%T%Thi: x < 5%N"
				+ "%T%Tdo%N"
				+ "%T%Tend%N"
				+ "end%N"
		end

feature {NONE} -- Helpers

	all_zero (a_asp: SIMPLE_AUTOSPEC; b1, b2, b3: SMT_EXPR): SMT_EXPR
			-- The dumb result b1=b2=b3=0.
		local
			zero: SMT_EXPR
		do
			zero := a_asp.smt.int_value (0)
			Result := b1.is_equal_to (zero).conjoined (b2.is_equal_to (zero)).conjoined (b3.is_equal_to (zero))
		end

	sort_spec_strong (a_asp: SIMPLE_AUTOSPEC; b1, b2, b3: SMT_EXPR): AUTOSPEC_SPEC
			-- A well-specified 3-element sort of input {1,2,3}: sorted AND a
			-- permutation of {1,2,3} (distinct + in range 1..3).
		local
			one, three: SMT_EXPR
		do
			one := a_asp.smt.int_value (1); three := a_asp.smt.int_value (3)
			Result := a_asp.new_spec ("sort_strong")
			Result.ensure_that (b1.at_most (b2))
			Result.ensure_that (b2.at_most (b3))
			Result.ensure_that (a_asp.smt.all_distinct (<<b1, b2, b3>>))
			Result.ensure_that (one.at_most (b1))
			Result.ensure_that (b1.at_most (three))
			Result.ensure_that (one.at_most (b2))
			Result.ensure_that (b2.at_most (three))
			Result.ensure_that (one.at_most (b3))
			Result.ensure_that (b3.at_most (three))
		end

end
