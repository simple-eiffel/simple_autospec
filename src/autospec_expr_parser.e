note
	description: "[
		A small recursive-descent compiler from Eiffel boolean/arithmetic
		expression TEXT into an SMT_EXPR over simple_smt. It handles the
		DECIDABLE FRAGMENT that a solver can reason about:

		  identifiers (treated as integer variables), integer literals,
		  + - * , unary minus, parentheses,
		  = /= < <= > >= ,  and  or  not  implies  xor.

		Anything outside that fragment -- dotted feature calls (a.b), `old`,
		string/character literals, manifest arrays, `across`, agents, real
		literals -- makes `parse' fail (returns Void), and the clause is
		reported as out-of-fragment rather than mistranslated. That honesty is
		the point: a clause we cannot translate faithfully is skipped, never faked.
	]"
	author: "Larry Rix"

class
	AUTOSPEC_EXPR_PARSER

create
	make

feature {NONE} -- Initialization

	make (a_smt: SIMPLE_SMT)
			-- Create a parser building expressions over `a_smt'.
		do
			smt := a_smt
			create vars.make (8)
			create tokens.make (16)
			last_error := ""
		end

feature -- Access

	smt: SIMPLE_SMT
			-- Expression factory.

	vars: HASH_TABLE [SMT_EXPR, STRING]
			-- Integer variables seen, by name (shared across clauses of one spec).

	last_error: STRING
			-- Why the last `parse' failed ("" on success).

	produced_boolean: BOOLEAN
			-- Was the last successfully-parsed expression boolean-typed
			-- (a relation or boolean connective), hence usable as a clause?
		do
			Result := last_type = T_bool
		end

	last_type: INTEGER
			-- Type of the most recently parsed (sub)expression: T_int or T_bool.

	T_int: INTEGER = 1
	T_bool: INTEGER = 2
			-- The two types the fragment tracks (all identifiers are integers;
			-- comparisons and connectives are boolean).

	variable_names: ARRAYED_LIST [STRING]
			-- Names of the integer variables introduced so far (sorted).
		do
			create Result.make (vars.count)
			from vars.start until vars.after loop
				Result.extend (vars.key_for_iteration)
				vars.forth
			end
		ensure
			result_attached: Result /= Void
		end

feature -- Parsing

	parse_clause (a_text: STRING): detachable SMT_EXPR
			-- Parse `a_text' as a boolean clause; Void unless it is in the
			-- decidable fragment AND boolean-typed (usable as require/ensure).
		require
			text_not_empty: not a_text.is_empty
		do
			Result := parse (a_text)
			if Result /= Void and then not produced_boolean then
				last_error := "not a boolean clause: " + a_text
				Result := Void
			end
		end

	parse (a_text: STRING): detachable SMT_EXPR
			-- Parse `a_text' as an expression; Void when outside the fragment.
		require
			text_not_empty: not a_text.is_empty
		do
			last_error := ""
			last_type := 0
			if tokenize (a_text) then
				pos := 1
				Result := parse_or
				if Result /= Void and then pos <= tokens.count then
					last_error := "trailing tokens after position " + pos.out
					Result := Void
				end
			end
			if Result = Void and then last_error.is_empty then
				last_error := "parse failed: " + a_text
			end
		end

feature {NONE} -- Grammar (recursive descent)

	parse_or: detachable SMT_EXPR
			-- or_expr := and_expr ( ("or"|"implies"|"xor") and_expr )*  (boolean operands)
		local
			l_op: STRING
			l_right: detachable SMT_EXPR
		do
			Result := parse_and
			from until Result = Void or else not is_kw ("or") and not is_kw ("implies") and not is_kw ("xor") loop
				if last_type /= T_bool then
					Result := Void; type_fail ("boolean expected left of '" + current_text + "'")
				else
					l_op := current_text
					advance
					l_right := parse_and
					if l_right = Void then
						Result := Void
					elseif last_type /= T_bool then
						Result := Void; type_fail ("boolean expected right of '" + l_op + "'")
					else
						if l_op.same_string ("or") then Result := Result.disjoined (l_right)
						elseif l_op.same_string ("xor") then Result := Result.xored (l_right)
						else Result := Result.entails (l_right) end
						last_type := T_bool
					end
				end
			end
		end

	parse_and: detachable SMT_EXPR
			-- and_expr := not_expr ( "and" not_expr )*  (boolean operands)
		local
			l_right: detachable SMT_EXPR
		do
			Result := parse_not
			from until Result = Void or else not is_kw ("and") loop
				if last_type /= T_bool then
					Result := Void; type_fail ("boolean expected left of 'and'")
				else
					advance
					l_right := parse_not
					if l_right = Void then
						Result := Void
					elseif last_type /= T_bool then
						Result := Void; type_fail ("boolean expected right of 'and'")
					else
						Result := Result.conjoined (l_right)
						last_type := T_bool
					end
				end
			end
		end

	parse_not: detachable SMT_EXPR
			-- not_expr := "not" not_expr | rel_expr  (boolean operand)
		do
			if is_kw ("not") then
				advance
				Result := parse_not
				if Result /= Void then
					if last_type /= T_bool then
						Result := Void; type_fail ("boolean expected after 'not'")
					else
						Result := Result.negated
						last_type := T_bool
					end
				end
			else
				Result := parse_rel
			end
		end

	parse_rel: detachable SMT_EXPR
			-- rel_expr := add_expr ( relop add_expr )?  (int operands; = /= same type)
		local
			l_op: STRING
			l_left_type: INTEGER
			l_right: detachable SMT_EXPR
		do
			Result := parse_add
			if Result /= Void and then is_relop then
				l_op := current_text
				l_left_type := last_type
				advance
				l_right := parse_add
				if l_right = Void then
					Result := Void
				elseif (l_op.same_string ("=") or l_op.same_string ("/=")) then
					if l_left_type = last_type then
						Result := apply_relop (l_op, Result, l_right)
						last_type := T_bool
					else
						Result := Void; type_fail ("'" + l_op + "' needs matching operand types")
					end
				elseif l_left_type = T_int and last_type = T_int then
					Result := apply_relop (l_op, Result, l_right)
					last_type := T_bool
				else
					Result := Void; type_fail ("'" + l_op + "' needs integer operands")
				end
			end
		end

	parse_add: detachable SMT_EXPR
			-- add_expr := mul_expr ( ("+"|"-") mul_expr )*  (int operands)
		local
			l_op: STRING
			l_right: detachable SMT_EXPR
		do
			Result := parse_mul
			from until Result = Void or else not (is_op ("+") or is_op ("-")) loop
				if last_type /= T_int then
					Result := Void; type_fail ("integer expected left of '" + current_text + "'")
				else
					l_op := current_text
					advance
					l_right := parse_mul
					if l_right = Void then
						Result := Void
					elseif last_type /= T_int then
						Result := Void; type_fail ("integer expected right of '" + l_op + "'")
					else
						if l_op.same_string ("+") then Result := Result.plus (l_right)
						else Result := Result.minus (l_right) end
						last_type := T_int
					end
				end
			end
		end

	parse_mul: detachable SMT_EXPR
			-- mul_expr := atom ( "*" atom )*  (int operands)
		local
			l_right: detachable SMT_EXPR
		do
			Result := parse_atom
			from until Result = Void or else not is_op ("*") loop
				if last_type /= T_int then
					Result := Void; type_fail ("integer expected left of '*'")
				else
					advance
					l_right := parse_atom
					if l_right = Void then
						Result := Void
					elseif last_type /= T_int then
						Result := Void; type_fail ("integer expected right of '*'")
					else
						Result := Result.times (l_right)
						last_type := T_int
					end
				end
			end
		end

	parse_atom: detachable SMT_EXPR
			-- atom := integer | identifier | "(" or_expr ")" | "-" atom
		do
			if pos > tokens.count then
				last_error := "unexpected end of expression"
			elseif is_op ("-") then
				advance
				Result := parse_atom
				if Result /= Void then
					if last_type = T_int then
						Result := Result.opposite
						last_type := T_int
					else
						Result := Void; type_fail ("integer expected after unary '-'")
					end
				end
			elseif current_kind.same_string ("int") then
					-- Numerals are read as reals: contract variables are typed
					-- unknown, and linear REAL arithmetic avoids false "dead"
					-- verdicts on real-valued ranges like 0 < p < 1.
				Result := smt.real_value (current_text)
				last_type := T_int
				advance
			elseif current_kind.same_string ("id") then
				Result := variable (current_text)
				last_type := T_int
				advance
			elseif is_lparen then
				advance
				Result := parse_or
				if Result /= Void then
					if is_rparen then
						advance
					else
						last_error := "missing ')'"
						Result := Void
					end
				end
			else
				last_error := "unexpected token '" + current_text + "'"
			end
		end

	type_fail (a_reason: STRING)
			-- Record a type error (clause is out of the sound fragment).
		do
			if last_error.is_empty then
				last_error := "type error: " + a_reason
			end
		end

feature {NONE} -- Semantic helpers

	variable (a_name: STRING): SMT_EXPR
			-- Real variable `a_name', created once and cached. Contract variable
			-- types are unknown, so the sound choice is linear real arithmetic.
		do
			if attached vars.item (a_name) as al then
				Result := al
			else
				Result := smt.real_const (a_name)
				vars.put (Result, a_name)
			end
		end

	apply_relop (a_op: STRING; a_left, a_right: SMT_EXPR): SMT_EXPR
			-- Build the comparison `a_left a_op a_right'.
		do
			if a_op.same_string ("=") then
				Result := a_left.is_equal_to (a_right)
			elseif a_op.same_string ("/=") then
				Result := a_left.is_equal_to (a_right).negated
			elseif a_op.same_string ("<") then
				Result := a_left.less (a_right)
			elseif a_op.same_string ("<=") then
				Result := a_left.at_most (a_right)
			elseif a_op.same_string (">") then
				Result := a_left.greater (a_right)
			else
				Result := a_left.at_least (a_right)
			end
		end

feature {NONE} -- Tokenizer

	tokens: ARRAYED_LIST [TUPLE [kind: STRING; text: STRING]]
			-- Token stream.

	pos: INTEGER
			-- Cursor into `tokens'.

	tokenize (a_text: STRING): BOOLEAN
			-- Fill `tokens' from `a_text'; False (with last_error) on an illegal
			-- character or construct outside the decidable fragment.
		local
			i, n: INTEGER
			c: CHARACTER
			l_start: INTEGER
			l_word: STRING
		do
			tokens.wipe_out
			Result := True
			n := a_text.count
			from i := 1 until i > n or not Result loop
				c := a_text [i]
				if c = ' ' or c = '%T' or c = '%R' or c = '%N' then
					i := i + 1
				elseif c.is_digit then
					l_start := i
					from until i > n or else not a_text [i].is_digit loop i := i + 1 end
					tokens.extend (["int", a_text.substring (l_start, i - 1)])
				elseif c.is_alpha or c = '_' then
					l_start := i
					from until i > n or else not (a_text [i].is_alpha_numeric or a_text [i] = '_') loop i := i + 1 end
					l_word := a_text.substring (l_start, i - 1)
					if is_keyword (l_word) then
						tokens.extend (["kw", l_word])
					else
						tokens.extend (["id", l_word])
					end
				elseif c = '(' then
					tokens.extend (["lparen", "("]); i := i + 1
				elseif c = ')' then
					tokens.extend (["rparen", ")"]); i := i + 1
				elseif c = '+' or c = '*' then
					tokens.extend (["op", create {STRING}.make_filled (c, 1)]); i := i + 1
				elseif c = '-' then
					tokens.extend (["op", "-"]); i := i + 1
				elseif c = '<' or c = '>' then
					if i < n and then a_text [i + 1] = '=' then
						tokens.extend (["op", a_text.substring (i, i + 1)]); i := i + 2
					else
						tokens.extend (["op", create {STRING}.make_filled (c, 1)]); i := i + 1
					end
				elseif c = '=' then
					tokens.extend (["op", "="]); i := i + 1
				elseif c = '/' and then i < n and then a_text [i + 1] = '=' then
					tokens.extend (["op", "/="]); i := i + 2
				else
						-- '.', '"', '%', '{', '[', ',', ''', etc. -- outside the fragment.
					last_error := "unsupported character '" + create {STRING}.make_filled (c, 1) + "' (out of decidable fragment)"
					Result := False
				end
			end
			if Result and tokens.is_empty then
				last_error := "empty expression"
				Result := False
			end
		end

	is_keyword (a_word: STRING): BOOLEAN
			-- Is `a_word' one of the boolean keywords?
		do
			Result := a_word.same_string ("and") or a_word.same_string ("or")
				or a_word.same_string ("not") or a_word.same_string ("implies")
				or a_word.same_string ("xor")
		end

feature {NONE} -- Token cursor

	current_kind: STRING
			-- Kind of the current token ("" past end).
		do
			if pos <= tokens.count then Result := tokens [pos].kind else Result := "" end
		end

	current_text: STRING
			-- Text of the current token ("" past end).
		do
			if pos <= tokens.count then Result := tokens [pos].text else Result := "" end
		end

	advance
			-- Move to the next token.
		do
			pos := pos + 1
		end

	is_kw (a_word: STRING): BOOLEAN
		do
			Result := current_kind.same_string ("kw") and then current_text.same_string (a_word)
		end

	is_op (a_op: STRING): BOOLEAN
		do
			Result := current_kind.same_string ("op") and then current_text.same_string (a_op)
		end

	is_relop: BOOLEAN
		do
			Result := current_kind.same_string ("op") and then
				(current_text.same_string ("=") or current_text.same_string ("/=")
				or current_text.same_string ("<") or current_text.same_string ("<=")
				or current_text.same_string (">") or current_text.same_string (">="))
		end

	is_lparen: BOOLEAN do Result := current_kind.same_string ("lparen") end
	is_rparen: BOOLEAN do Result := current_kind.same_string ("rparen") end

invariant
	smt_attached: smt /= Void

end
