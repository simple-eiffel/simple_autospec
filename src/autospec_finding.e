note
	description: "A single diagnostic from an AutoSpec hardening pass: a severity, a kind, a message, and an optional witness"
	author: "Larry Rix"

class
	AUTOSPEC_FINDING

create
	make

feature {NONE} -- Initialization

	make (a_severity: INTEGER; a_kind, a_message: STRING)
			-- Create a finding.
		require
			severity_valid: a_severity = Critical or a_severity = Warning or a_severity = Info
			kind_not_empty: not a_kind.is_empty
		do
			severity := a_severity
			kind := a_kind
			message := a_message
			witness := ""
		ensure
			severity_set: severity = a_severity
			kind_set: kind = a_kind
		end

feature -- Severity levels

	Critical: INTEGER = 1
			-- An unimplementable or dead spec: must fix.

	Warning: INTEGER = 2
			-- A likely under-constrained (vacuous / weak) spec: should fix.

	Info: INTEGER = 3
			-- A redundancy or note: may tidy.

feature -- Access

	severity: INTEGER
	kind: STRING
	message: STRING
	witness: STRING

	severity_label: STRING
			-- Human label for `severity'.
		do
			if severity = Critical then Result := "CRITICAL"
			elseif severity = Warning then Result := "WARNING"
			else Result := "info" end
		end

feature -- Modification

	set_witness (a_witness: STRING)
			-- Attach a concrete witness (counter-model / admitted assignment).
		do
			witness := a_witness
		ensure
			witness_set: witness = a_witness
		end

feature -- Output

	as_line: STRING
			-- One-line rendering.
		do
			Result := "[" + severity_label + "] " + kind + ": " + message
			if not witness.is_empty then
				Result := Result + "  {witness: " + compact (witness) + "}"
			end
		ensure
			result_attached: Result /= Void
		end

feature {NONE} -- Implementation

	compact (a_text: STRING): STRING
			-- `a_text' with newlines collapsed to spaces.
		do
			Result := a_text.twin
			Result.replace_substring_all ("%N", " ")
			Result.replace_substring_all ("  ", " ")
			Result.left_adjust
			Result.right_adjust
		end

invariant
	kind_not_empty: not kind.is_empty
	witness_attached: witness /= Void

end
