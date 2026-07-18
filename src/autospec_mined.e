note
	description: "A feature's contracts mined into a candidate spec, with a record of what translated and what was skipped"
	author: "Larry Rix"

class
	AUTOSPEC_MINED

create
	make

feature {NONE} -- Initialization

	make (a_name: STRING; a_spec: AUTOSPEC_SPEC)
			-- Create a mined record for feature `a_name' with candidate `a_spec'.
		require
			name_not_empty: not a_name.is_empty
		do
			feature_name := a_name
			spec := a_spec
			create kept.make (4)
			create skipped.make (4)
		end

feature -- Access

	feature_name: STRING
			-- Name of the mined feature.

	spec: AUTOSPEC_SPEC
			-- Candidate spec built from the translatable clauses.

	kept: ARRAYED_LIST [STRING]
			-- Clause texts successfully translated into the spec.

	skipped: ARRAYED_LIST [STRING]
			-- Clause texts outside the decidable fragment (recorded, not faked).

	translated_count: INTEGER do Result := kept.count end
	skipped_count: INTEGER do Result := skipped.count end

feature -- Modification

	record_kept (a_clause: STRING) do kept.extend (a_clause) end
	record_skipped (a_clause: STRING) do skipped.extend (a_clause) end

invariant
	name_not_empty: not feature_name.is_empty

end
