note
	description: "[
		A self-contained local-LLM oracle: POSTs a completion request to a
		running llama.cpp server (any GGUF model; build the server with the
		Vulkan backend to use whatever GPU is present) over HTTP via the system
		curl, and returns the completion text. No dependency on any private
		model project -- it reuses only the well-known llama.cpp-server + curl
		integration pattern.

		Point it at a server you started, e.g.:
		  llama-server -m qwen3-coder-30b-a3b-q4_k_m.gguf --host 127.0.0.1 --port 8080
		(add -ngl 99 with a Vulkan build to offload layers to the GPU).
	]"
	author: "Larry Rix"

class
	AUTOSPEC_LLM_CLIENT

inherit
	AUTOSPEC_ORACLE

create
	make, make_at

feature {NONE} -- Initialization

	make
			-- Client for a llama.cpp server on 127.0.0.1:8080.
		do
			make_at ("127.0.0.1", 8080)
		end

	make_at (a_host: STRING; a_port: INTEGER)
			-- Client for a llama.cpp server at `a_host':`a_port'.
		require
			host_not_empty: not a_host.is_empty
			port_positive: a_port > 0
		do
			host := a_host
			port := a_port
			max_tokens := 128
			temperature := "0.2"
			last_error := ""
		ensure
			host_set: host = a_host
			port_set: port = a_port
		end

feature -- Settings

	host: STRING
	port: INTEGER
	max_tokens: INTEGER
	temperature: STRING
	last_error: STRING

	set_max_tokens (a_n: INTEGER)
		require positive: a_n > 0
		do max_tokens := a_n ensure set: max_tokens = a_n end

	set_temperature (a_t: STRING)
		require not_empty: not a_t.is_empty
		do temperature := a_t ensure set: temperature = a_t end

	base_url: STRING
			-- e.g. http://127.0.0.1:8080
		do
			Result := "http://" + host + ":" + port.out
		end

feature -- Proposal

	is_available: BOOLEAN
			-- Does the server answer its health endpoint?
		local
			l_proc: SIMPLE_PROCESS
		do
			create l_proc.make
			l_proc.set_show_window (False)
			l_proc.launch ("curl -s -o NUL -w %"%%{http_code}%" " + base_url + "/health")
			if attached l_proc.captured_output as al then
				Result := al.has_substring ("200")
			end
		end

	propose (a_prompt: STRING): STRING
			-- POST `a_prompt' to /v1/chat/completions (OpenAI-compatible, so the
			-- model's chat template is applied) and return the message content.
		local
			l_proc: SIMPLE_PROCESS
			l_file: SIMPLE_FILE
			l_body, l_body_path, l_json: STRING
			l_out: STRING_32
			l_u: UTF_CONVERTER
		do
			create Result.make_empty
			last_error := ""
			l_body := request_body (a_prompt)
			l_body_path := temp_path
			create l_file.make (l_body_path)
			if l_file.set_content (l_body) then
				create l_proc.make
				l_proc.set_show_window (False)
				l_out := l_proc.command_output ("curl -s --max-time 120 -X POST " + base_url + "/v1/chat/completions "
					+ "-H %"Content-Type: application/json%" --data-binary @%"" + l_body_path + "%"")
				if l_proc.was_successful and then not l_out.is_empty then
					l_json := l_u.utf_32_string_to_utf_8_string_8 (l_out)
					if attached message_content (l_json) as al_c then
						Result := al_c
						Result.left_adjust
						Result.right_adjust
					else
						last_error := "no choices[0].message.content in response: " + l_json
					end
				else
					last_error := "curl produced no output"
				end
			else
				last_error := "cannot write request body to " + l_body_path
			end
		end

feature {NONE} -- Implementation

	request_body (a_prompt: STRING): STRING
			-- /v1/chat/completions JSON body for `a_prompt'.
		do
			create Result.make (a_prompt.count + 160)
			Result.append ("{%"messages%": [{%"role%": %"user%", %"content%": %"")
			Result.append (json_escaped (a_prompt))
			Result.append ("%"}], %"max_tokens%": " + max_tokens.out)
			Result.append (", %"temperature%": " + temperature + "}")
		end

	message_content (a_json: STRING): detachable STRING
			-- Extract choices[0].message.content from a chat-completion response.
		local
			l_quick: SIMPLE_JSON_QUICK
		do
			create l_quick.make
			if attached l_quick.parse_object (a_json) as al_root then
				if attached al_root.array_item ({STRING_32} "choices") as al_choices then
					if al_choices.count >= 1 and then attached al_choices.object_item (1) as al_first then
						if attached al_first.object_item ({STRING_32} "message") as al_msg then
							if attached al_msg.string_item ({STRING_32} "content") as al_c then
								Result := al_c.to_string_8
							end
						end
					end
				end
			end
		end

	json_escaped (a_text: STRING): STRING
			-- `a_text' with JSON string escaping.
		local
			i: INTEGER
			c: CHARACTER
		do
			create Result.make (a_text.count + 8)
			from i := 1 until i > a_text.count loop
				c := a_text [i]
				if c = '"' then Result.append ("\%"")
				elseif c = '\' then Result.append ("\\")
				elseif c = '%N' then Result.append ("\n")
				elseif c = '%R' then Result.append ("\r")
				elseif c = '%T' then Result.append ("\t")
				else Result.append_character (c) end
				i := i + 1
			end
		end

	temp_path: STRING
			-- A scratch file path for the request body.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			if attached l_env.temporary_directory_path as al then
				Result := al.name.to_string_8 + "/autospec_llm_req.json"
			else
				Result := "autospec_llm_req.json"
			end
		end

end
