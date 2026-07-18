note
	description: "Test runner for simple_autospec"
	author: "Larry Rix"

class
	TEST_APP

create
	make

feature {NONE} -- Initialization

	make
		local
			t: LIB_TESTS
		do
			create t
			io.put_string ("simple_autospec test runner%N====================================%N%N")
			passed := 0; failed := 0

			io.put_string ("Feasibility / liveness%N----------------------%N")
			run_test (agent t.test_infeasible_spec_detected, "infeasible_spec_detected")
			run_test (agent t.test_feasible_spec_accepted, "feasible_spec_accepted")
			run_test (agent t.test_dead_precondition_detected, "dead_precondition_detected")
			run_test (agent t.test_live_precondition_accepted, "live_precondition_accepted")

			io.put_string ("%NVacuity detection%N-----------------%N")
			run_test (agent t.test_weak_sort_spec_is_vacuous, "weak_sort_spec_is_vacuous")
			run_test (agent t.test_strong_sort_spec_rejects_dumb, "strong_sort_spec_rejects_dumb")
			run_test (agent t.test_strong_sort_spec_admits_correct_result, "strong_sort_spec_admits_correct_result")

			io.put_string ("%NSubsumption / pruning%N---------------------%N")
			run_test (agent t.test_strong_strengthens_weak, "strong_strengthens_weak")
			run_test (agent t.test_bound_subsumption, "bound_subsumption")
			run_test (agent t.test_feasibility_report, "feasibility_report")

			io.put_string ("%NExpression parser%N-----------------%N")
			run_test (agent t.test_parser_translates_arithmetic_clauses, "parser_translates_arithmetic_clauses")
			run_test (agent t.test_parser_rejects_out_of_fragment, "parser_rejects_out_of_fragment")
			run_test (agent t.test_parsed_clause_is_checkable, "parsed_clause_is_checkable")

			io.put_string ("%NBrownfield miner%N----------------%N")
			run_test (agent t.test_miner_extracts_and_translates, "miner_extracts_and_translates")
			run_test (agent t.test_miner_detects_infeasible_real_contract, "miner_detects_infeasible_real_contract")

			io.put_string ("%NCore loop (AUTOSPEC_SESSION)%N----------------------------%N")
			run_test (agent t.test_session_flags_dead_precondition, "session_flags_dead_precondition")
			run_test (agent t.test_session_flags_contradictory_obligation, "session_flags_contradictory_obligation")
			run_test (agent t.test_session_flags_vacuous_spec, "session_flags_vacuous_spec")
			run_test (agent t.test_session_bulletproof_when_strong, "session_bulletproof_when_strong")
			run_test (agent t.test_session_flags_unconstrained_result, "session_flags_unconstrained_result")

			io.put_string ("%N====================================%N")
			io.put_string ("Results: " + passed.out + " passed, " + failed.out + " failed%N")
			if failed > 0 then io.put_string ("TESTS FAILED%N") else io.put_string ("ALL TESTS PASSED%N") end
		end

feature {NONE} -- Implementation

	passed, failed: INTEGER

	run_test (a_test: PROCEDURE; a_name: STRING)
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				io.put_string ("  PASS: " + a_name + "%N")
				passed := passed + 1
			end
		rescue
			io.put_string ("  FAIL: " + a_name + "%N")
			failed := failed + 1
			l_retried := True
			retry
		end

end
