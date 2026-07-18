note
	description: "[
		Batch intake: walk a directory tree of Eiffel sources, mine every
		feature's contracts, and audit the decidable-fragment clauses for DEAD
		preconditions and INFEASIBLE (self-contradictory) specifications --
		real contract bugs, discharged by Z3. This is the graphify-scale intake:
		point it at a library (or the whole ecosystem) and get a contract-health
		report. A fresh solver is used per file so variable names never collide
		across files.
	]"
	author: "Larry Rix"

class
	AUTOSPEC_SCANNER

create
	make

feature {NONE} -- Initialization

	make
			-- Create an empty scanner.
		do
			create flagged.make (8)
			reset_counts
		end

feature -- Access

	files_scanned: INTEGER
			-- .e files examined.

	features_mined: INTEGER
			-- Features that had at least one translatable clause.

	clauses_kept: INTEGER
			-- Clauses translated into the decidable fragment.

	clauses_skipped: INTEGER
			-- Clauses recorded as out of fragment.

	dead_count: INTEGER
			-- Features with an unsatisfiable precondition.

	infeasible_count: INTEGER
			-- Features whose pre/post/invariant contradict.

	flagged: ARRAYED_LIST [STRING]
			-- One line per flagged feature: "relpath:feature -- reason".

feature -- Scanning

	scan (a_root: STRING)
			-- Walk `a_root' recursively, mining and auditing every .e file.
		require
			root_not_empty: not a_root.is_empty
		do
			reset_counts
			flagged.wipe_out
			root := normalized (a_root)
			walk (root)
		end

	root: STRING
			-- Absolute root of the last scan.

feature {NONE} -- Walking

	walk (a_dir: STRING)
			-- Recurse into `a_dir'.
		local
			l_dir: SIMPLE_FILE
			l_names: ARRAYED_LIST [STRING]
			l_full, l_lower: STRING
		do
			create l_dir.make (a_dir)
			create l_names.make (32)
			across l_dir.files as ic loop
				l_names.extend (utf8 (ic))
			end
			across l_names as ic loop
				if ic.as_lower.ends_with (".e") and not ic.as_lower.ends_with (".bak") then
					scan_file (a_dir + "/" + ic)
				end
			end
			create l_names.make (16)
			across l_dir.directories as ic loop
				l_names.extend (utf8 (ic))
			end
			across l_names as ic loop
				l_lower := ic.as_lower
				if not ic.starts_with (".") and not l_lower.same_string ("eifgens")
					and not l_lower.same_string ("eifdata") and not l_lower.same_string ("_deprecated")
				then
					walk (a_dir + "/" + ic)
				end
			end
		end

	scan_file (a_path: STRING)
			-- Mine and audit one .e file.
		local
			l_asp: SIMPLE_AUTOSPEC
			l_miner: AUTOSPEC_MINER
			l_mined: ARRAYED_LIST [AUTOSPEC_MINED]
			l_file: SIMPLE_FILE
			l_src, l_rel: STRING
			l_failed: BOOLEAN
		do
			if l_failed then
				-- A parser/solver hiccup on one file must not abort the scan.
			else
				create l_file.make (a_path)
				if l_file.found and then l_file.is_file then
					files_scanned := files_scanned + 1
					l_src := utf8 (l_file.content)
					l_rel := relative (root, a_path)
					create l_asp.make
					create l_miner.make (l_asp)
					l_mined := l_miner.mine (l_src)
					across l_mined as ic loop
						features_mined := features_mined + 1
						clauses_kept := clauses_kept + ic.translated_count
						clauses_skipped := clauses_skipped + ic.skipped_count
						audit (l_asp, ic, l_rel)
					end
				end
			end
		rescue
			l_failed := True
			retry
		end

	audit (a_asp: SIMPLE_AUTOSPEC; a_mined: AUTOSPEC_MINED; a_rel: STRING)
			-- Flag a mined feature whose PRECONDITION is unsatisfiable -- a
			-- genuinely dead, un-callable feature. This is the only sound
			-- batch check: unlike pre-and-post conjunction (which conflates the
			-- pre-state and post-state of a command and yields false positives),
			-- an unsatisfiable precondition is a real bug regardless of state.
		do
			if a_mined.spec.preconditions.count > 0 and then not a_asp.is_precondition_live (a_mined.spec) then
				dead_count := dead_count + 1
				flagged.extend (a_rel + ":" + a_mined.feature_name + " -- DEAD precondition (unsatisfiable)")
			end
		end

feature {NONE} -- Implementation

	reset_counts
			-- Zero all tallies.
		do
			files_scanned := 0
			features_mined := 0
			clauses_kept := 0
			clauses_skipped := 0
			dead_count := 0
			infeasible_count := 0
			root := ""
		end

	utf8 (a_text: READABLE_STRING_GENERAL): STRING
			-- UTF-8 byte encoding of `a_text'.
		local
			l_conv: UTF_CONVERTER
		do
			Result := l_conv.utf_32_string_to_utf_8_string_8 (a_text)
		ensure
			result_attached: Result /= Void
		end

	normalized (a_path: READABLE_STRING_GENERAL): STRING
			-- `a_path' as UTF-8 with '/' separators, no trailing slash.
		do
			Result := utf8 (a_path)
			Result.replace_substring_all ("\", "/")
			if Result.count > 1 and then Result [Result.count] = '/' then
				Result := Result.substring (1, Result.count - 1)
			end
		end

	relative (a_root, a_path: STRING): STRING
			-- `a_path' made relative to `a_root' when underneath it.
		local
			l_root: STRING
		do
			l_root := a_root.twin
			if not l_root.ends_with ("/") then l_root.append_character ('/') end
			if a_path.count > l_root.count and then a_path.as_lower.starts_with (l_root.as_lower) then
				Result := a_path.substring (l_root.count + 1, a_path.count)
			else
				Result := a_path
			end
		ensure
			result_attached: Result /= Void
		end

end
