note
	description: "AutoSpec demo: harden a 3-element sort spec from vacuous to bullet-proof"
	author: "Larry Rix"

class
	AUTOSPEC_APP

create
	make

feature {NONE} -- Initialization

	make
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
		end

feature {NONE} -- Implementation

	yn (a: BOOLEAN): STRING
		do
			if a then Result := "yes" else Result := "no" end
		end

end
