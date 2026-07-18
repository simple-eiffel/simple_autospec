note
	description: "[
		The AutoSpec core loop: a hardening session over one specification.
		`harden' runs the full deterministic diagnostic battery through Z3 and
		produces prioritized findings -- the Socratic prompts a human or LLM
		reads to know what to strengthen next:

		  CRITICAL  dead precondition            (precondition unsatisfiable)
		  CRITICAL  self-contradictory obligation (post and invariant unsat)
		  WARNING   unconstrained result          (no postcondition)
		  WARNING   vacuous spec                  (a trivial output satisfies it)
		  info      redundant clause              (one postcondition implies another)

		This is the dispose+diagnose half of a propose/dispose loop: it never
		invents intent; it tells you, with witnesses, where the spec is weak.
	]"
	author: "Larry Rix"

class
	AUTOSPEC_SESSION

create
	make

feature {NONE} -- Initialization

	make (a_autospec: SIMPLE_AUTOSPEC; a_spec: AUTOSPEC_SPEC)
			-- Start a hardening session for `a_spec'.
		require
			same_solver: a_spec.smt = a_autospec.smt
		do
			autospec := a_autospec
			spec := a_spec
			create findings.make (4)
		ensure
			spec_set: spec = a_spec
		end

feature -- Access

	autospec: SIMPLE_AUTOSPEC
			-- The Z3-backed checker.

	spec: AUTOSPEC_SPEC
			-- The specification being hardened.

	findings: ARRAYED_LIST [AUTOSPEC_FINDING]
			-- Diagnostics from the last `harden'.

feature -- Status

	is_bulletproof: BOOLEAN
			-- Did the last `harden' find no CRITICAL or WARNING issues?
		do
			Result := True
			across findings as ic loop
				if ic.severity <= {AUTOSPEC_FINDING}.Warning then
					Result := False
				end
			end
		end

	critical_count: INTEGER
			-- Number of CRITICAL findings.
		do
			across findings as ic loop
				if ic.severity = {AUTOSPEC_FINDING}.Critical then Result := Result + 1 end
			end
		end

feature -- The core loop

	harden
			-- Run the full diagnostic battery; refill `findings' (most severe first).
		do
			findings.wipe_out
			check_dead_precondition
			check_obligation_consistency
			check_unconstrained_result
			check_vacuity
			check_redundancy
		end

feature -- Output

	report: STRING
			-- Human report of the last hardening pass.
		do
			create Result.make (256)
			Result.append ("AutoSpec hardening -- " + spec.name + "%N")
			if findings.is_empty then
				Result.append ("  (no diagnostics: spec is feasible, constrained, and non-vacuous)%N")
			else
				across findings as ic loop
					Result.append ("  " + ic.as_line + "%N")
				end
			end
			if is_bulletproof then
				Result.append ("  => BULLET-PROOF (no critical or warning issues)%N")
			else
				Result.append ("  => needs work (" + critical_count.out + " critical)%N")
			end
		ensure
			result_attached: Result /= Void
		end

feature {NONE} -- Diagnostics

	check_dead_precondition
			-- CRITICAL when the precondition can never hold.
		local
			l_f: AUTOSPEC_FINDING
		do
			if spec.preconditions.count > 0 and then not autospec.is_precondition_live (spec) then
				create l_f.make ({AUTOSPEC_FINDING}.Critical, "dead-precondition",
					"the precondition is unsatisfiable -- this feature can never be called")
				findings.extend (l_f)
			end
		end

	check_obligation_consistency
			-- CRITICAL when postcondition and invariant contradict (unimplementable).
		local
			l_f: AUTOSPEC_FINDING
		do
			if (spec.postconditions.count > 0 or spec.invariants.count > 0)
				and then not autospec.is_obligation_satisfiable (spec)
			then
				create l_f.make ({AUTOSPEC_FINDING}.Critical, "contradictory-obligation",
					"postcondition and invariant contradict -- no result can satisfy them")
				findings.extend (l_f)
			end
		end

	check_unconstrained_result
			-- WARNING when there is nothing constraining the result.
		local
			l_f: AUTOSPEC_FINDING
		do
			if spec.postconditions.is_empty and spec.invariants.is_empty then
				create l_f.make ({AUTOSPEC_FINDING}.Warning, "unconstrained-result",
					"no postcondition or invariant -- any implementation satisfies this spec")
				findings.extend (l_f)
			end
		end

	check_vacuity
			-- WARNING when a trivial output (all declared outputs = 0) satisfies
			-- the obligation -- a strong sign the spec is under-constrained.
		local
			l_f: AUTOSPEC_FINDING
			l_trivial, l_zero: SMT_EXPR
			l_first: BOOLEAN
		do
			if not spec.outputs.is_empty and then (spec.postconditions.count > 0 or spec.invariants.count > 0) then
				l_zero := autospec.smt.real_value ("0")
				l_first := True
				l_trivial := autospec.smt.true_expr
				across spec.outputs as ic loop
					if l_first then
						l_trivial := ic.is_equal_to (l_zero)
						l_first := False
					else
						l_trivial := l_trivial.conjoined (ic.is_equal_to (l_zero))
					end
				end
				if autospec.admits (spec, l_trivial) then
					create l_f.make ({AUTOSPEC_FINDING}.Warning, "vacuous-spec",
						"a trivial result (all outputs = 0) satisfies the spec -- add a conservation law")
					l_f.set_witness (autospec.last_witness)
					findings.extend (l_f)
				end
			end
		end

	check_redundancy
			-- info when one postcondition clause implies another (redundant).
		local
			l_f: AUTOSPEC_FINDING
			i, j: INTEGER
		do
			from i := 1 until i > spec.postconditions.count loop
				from j := 1 until j > spec.postconditions.count loop
					if i /= j and then implies_clause (spec.postconditions [i], spec.postconditions [j]) then
						create l_f.make ({AUTOSPEC_FINDING}.Info, "redundant-clause",
							"postcondition clause " + j.out + " is implied by clause " + i.out)
						findings.extend (l_f)
					end
					j := j + 1
				end
				i := i + 1
			end
		end

	implies_clause (a, b: SMT_EXPR): BOOLEAN
			-- Does clause `a' entail clause `b'?
		do
			autospec.smt.reset
			Result := autospec.smt.prove (a.entails (b))
		end

invariant
	autospec_attached: autospec /= Void
	spec_attached: spec /= Void

end
