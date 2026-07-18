note
	description: "A test/replay oracle that returns canned proposals in order — lets the proposer loop be verified deterministically without a live model"
	author: "Larry Rix"

class
	AUTOSPEC_SCRIPTED_ORACLE

inherit
	AUTOSPEC_ORACLE

create
	make

feature {NONE} -- Initialization

	make (a_responses: ARRAY [STRING])
			-- Create an oracle that returns `a_responses' in order, then "".
		do
			create responses.make_from_array (a_responses)
			next_index := 1
			create prompts_seen.make (a_responses.count)
		end

feature -- Access

	responses: ARRAYED_LIST [STRING]
			-- The scripted proposals.

	prompts_seen: ARRAYED_LIST [STRING]
			-- Prompts the proposer sent (for asserting feedback happened).

feature -- Proposal

	propose (a_prompt: STRING): STRING
			-- Next scripted response, or "" when exhausted.
		do
			prompts_seen.extend (a_prompt)
			if next_index <= responses.count then
				Result := responses [next_index]
				next_index := next_index + 1
			else
				Result := ""
			end
		end

	is_available: BOOLEAN = True
			-- A scripted oracle is always available.

feature {NONE} -- Implementation

	next_index: INTEGER
			-- Cursor into `responses'.

end
