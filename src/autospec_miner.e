note
	description: "[
		Brownfield intake for AutoSpec: read real Eiffel source text, extract the
		require/ensure clauses of each feature (using the ecosystem's indentation
		convention), translate the decidable-fragment clauses into candidate
		AUTOSPEC_SPECs via AUTOSPEC_EXPR_PARSER, and record what could not be
		translated. Every mined clause is a SEED, not truth -- AutoSpec then
		interrogates the candidate (feasibility, vacuity, subsumption) with Z3.
	]"
	author: "Larry Rix"

class
	AUTOSPEC_MINER

create
	make

feature {NONE} -- Initialization

	make (a_autospec: SIMPLE_AUTOSPEC)
			-- Create a miner feeding candidate specs to `a_autospec'.
		do
			autospec := a_autospec
		end

feature -- Access

	autospec: SIMPLE_AUTOSPEC
			-- The checker whose solver the mined specs are built over.

feature -- Mining

	mine (a_source: STRING): ARRAYED_LIST [AUTOSPEC_MINED]
			-- One mined candidate per feature in `a_source' that carries at
			-- least one translatable contract clause.
		local
			l_lines: LIST [STRING]
			l_state: INTEGER
			l_feature: STRING
			l_reqs, l_ensures: ARRAYED_LIST [STRING]
			l_trim: STRING
			l_indent: INTEGER
		do
			create Result.make (8)
			l_lines := a_source.split ('%N')
			l_feature := ""
			create l_reqs.make (4)
			create l_ensures.make (4)
			l_state := St_normal
			across l_lines as ic loop
				l_trim := trimmed (ic)
				l_indent := indent_of (ic)
				if l_indent = 1 and then is_feature_signature (l_trim) then
						-- New feature: flush the previous one.
					flush (Result, l_feature, l_reqs, l_ensures)
					l_feature := first_token (l_trim)
					create l_reqs.make (4)
					create l_ensures.make (4)
					l_state := St_normal
				elseif l_trim.same_string ("require") or l_trim.same_string ("require else") then
					l_state := St_require
				elseif l_trim.same_string ("ensure") or l_trim.same_string ("ensure then") then
					l_state := St_ensure
				elseif is_body_keyword (l_trim) then
					if l_state = St_require then l_state := St_normal end
				elseif l_trim.same_string ("end") or l_trim.same_string ("rescue") or l_trim.starts_with ("invariant") then
					if l_state = St_ensure then l_state := St_normal end
				elseif l_state = St_require and then not l_trim.is_empty then
					l_reqs.extend (clause_expression (l_trim))
				elseif l_state = St_ensure and then not l_trim.is_empty then
					l_ensures.extend (clause_expression (l_trim))
				end
			end
			flush (Result, l_feature, l_reqs, l_ensures)
		ensure
			result_attached: Result /= Void
		end

feature {NONE} -- Building

	flush (a_result: ARRAYED_LIST [AUTOSPEC_MINED]; a_feature: STRING; a_reqs, a_ensures: ARRAYED_LIST [STRING])
			-- Build a mined candidate for `a_feature' and append it when it has
			-- at least one translatable clause.
		local
			l_parser: AUTOSPEC_EXPR_PARSER
			l_spec: AUTOSPEC_SPEC
			l_mined: AUTOSPEC_MINED
		do
			if not a_feature.is_empty and then (not a_reqs.is_empty or not a_ensures.is_empty) then
				create l_parser.make (autospec.smt)
				l_spec := autospec.new_spec (a_feature)
				create l_mined.make (a_feature, l_spec)
				translate (l_parser, a_reqs, l_mined, True)
				translate (l_parser, a_ensures, l_mined, False)
				if l_mined.translated_count > 0 then
					a_result.extend (l_mined)
				end
			end
		end

	translate (a_parser: AUTOSPEC_EXPR_PARSER; a_clauses: ARRAYED_LIST [STRING]; a_mined: AUTOSPEC_MINED; a_is_pre: BOOLEAN)
			-- Translate each clause; add the ones in the decidable fragment to
			-- the spec, record the rest as skipped.
		do
			across a_clauses as ic loop
				if not ic.is_empty then
					if attached a_parser.parse_clause (ic) as al_expr then
						if a_is_pre then
							a_mined.spec.require_that (al_expr)
						else
							a_mined.spec.ensure_that (al_expr)
						end
						a_mined.record_kept (ic)
					else
						a_mined.record_skipped (ic)
					end
				end
			end
		end

feature {NONE} -- Text helpers

	St_normal: INTEGER = 0
	St_require: INTEGER = 1
	St_ensure: INTEGER = 2

	clause_expression (a_trimmed_line: STRING): STRING
			-- The expression part of an assertion line, dropping a leading
			-- `tag:' when present (an identifier followed by ':' but not ':=').
		local
			l_colon: INTEGER
			l_head: STRING
		do
			Result := a_trimmed_line
			l_colon := a_trimmed_line.index_of (':', 1)
			if l_colon > 1 and then (l_colon >= a_trimmed_line.count or else a_trimmed_line [l_colon + 1] /= '=') then
				l_head := a_trimmed_line.substring (1, l_colon - 1)
				if is_identifier (l_head) then
					Result := a_trimmed_line.substring (l_colon + 1, a_trimmed_line.count)
				end
			end
			Result.left_adjust
			Result.right_adjust
		ensure
			result_attached: Result /= Void
		end

	trimmed (a_line: STRING): STRING
			-- `a_line' without surrounding whitespace or a trailing CR.
		do
			Result := a_line.twin
			Result.prune_all ('%R')
			Result.left_adjust
			Result.right_adjust
		end

	indent_of (a_line: STRING): INTEGER
			-- Number of leading tab characters.
		local
			i: INTEGER
		do
			from i := 1 until i > a_line.count or else a_line [i] /= '%T' loop
				Result := Result + 1
				i := i + 1
			end
		end

	first_token (a_text: STRING): STRING
			-- Leading identifier of `a_text'.
		local
			i: INTEGER
		do
			create Result.make (16)
			from i := 1 until i > a_text.count or else not (a_text [i].is_alpha_numeric or a_text [i] = '_') loop
				Result.append_character (a_text [i])
				i := i + 1
			end
		end

	is_feature_signature (a_trimmed: STRING): BOOLEAN
			-- Does `a_trimmed' look like a feature declaration (not a keyword)?
		local
			l_first: STRING
		do
			l_first := first_token (a_trimmed)
			Result := not l_first.is_empty
				and then (a_trimmed [1].is_alpha and then a_trimmed [1].is_lower or a_trimmed [1] = '_')
				and then not is_reserved (l_first)
		end

	is_identifier (a_text: STRING): BOOLEAN
			-- Is `a_text' a single identifier?
		do
			Result := not a_text.is_empty and then (a_text [1].is_alpha or a_text [1] = '_')
			if Result then
				across a_text as ic loop
					if not (ic.is_alpha_numeric or ic = '_') then Result := False end
				end
			end
		end

	is_body_keyword (a_trimmed: STRING): BOOLEAN
			-- Does `a_trimmed' open a feature body (ending a require block)?
		do
			Result := a_trimmed.same_string ("do") or a_trimmed.same_string ("local")
				or a_trimmed.same_string ("deferred") or a_trimmed.same_string ("once")
				or a_trimmed.same_string ("attribute") or a_trimmed.starts_with ("external")
				or a_trimmed.starts_with ("obsolete") or a_trimmed.starts_with ("once (")
		end

	is_reserved (a_word: STRING): BOOLEAN
			-- Is `a_word' an Eiffel keyword that can appear at feature indent?
		do
			Result := a_word.same_string ("feature") or a_word.same_string ("invariant")
				or a_word.same_string ("note") or a_word.same_string ("class")
				or a_word.same_string ("inherit") or a_word.same_string ("create")
				or a_word.same_string ("end") or a_word.same_string ("require")
				or a_word.same_string ("ensure") or a_word.same_string ("do")
				or a_word.same_string ("local") or a_word.same_string ("deferred")
		end

invariant
	autospec_attached: autospec /= Void

end
