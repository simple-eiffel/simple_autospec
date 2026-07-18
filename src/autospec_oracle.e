note
	description: "[
		The propose side of AutoSpec's propose/dispose loop, as an interface.
		An oracle returns candidate spec-clause TEXT given a prompt; the proposer
		parses and checks each candidate with Z3, feeding counterexamples back.

		Two implementations: AUTOSPEC_LLM_CLIENT (a local llama.cpp server) and
		AUTOSPEC_SCRIPTED_ORACLE (canned responses, for deterministic tests). The
		oracle is never trusted to judge correctness -- only to suggest.
	]"
	author: "Larry Rix"

deferred class
	AUTOSPEC_ORACLE

feature -- Proposal

	propose (a_prompt: STRING): STRING
			-- A candidate response to `a_prompt' (expected to contain a single
			-- Eiffel boolean clause). "" when the oracle has nothing to offer.
		require
			prompt_not_empty: not a_prompt.is_empty
		deferred
		ensure
			result_attached: Result /= Void
		end

	is_available: BOOLEAN
			-- Can the oracle currently serve proposals?
		deferred
		end

end
