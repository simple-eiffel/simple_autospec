note
	description: "[
		Ensures there is a llama.cpp server to run against, and makes that server
		a SHARED resource that unrelated projects can reuse without depending on
		one another. The rendezvous is a URL, not a library:

		  1. If the LLAMA_SERVER_URL environment variable is set, that endpoint is
		     used -- reuse only (this manager never spawns or kills a server it was
		     merely told about).
		  2. Otherwise, if a registry file written by a previous spawn is present
		     and still names a healthy server, that endpoint is reused.
		  3. Otherwise the passed-in port is used: a server is spawned locally
		     (Vulkan/GPU build preferred, CPU build as fallback) and its endpoint is
		     recorded in the registry file so the NEXT project -- including private
		     ones that only speak HTTP -- finds it by URL and shares the one model
		     already resident in memory.

		Generic: binary and model paths are arguments, so this depends on no
		particular model project. The decoupling boundary is HTTP.
	]"
	author: "Larry Rix"

class
	AUTOSPEC_SERVER

create
	make

feature {NONE} -- Initialization

	make (a_gpu_exe, a_cpu_exe, a_model_path: STRING; a_port: INTEGER)
			-- Server manager for `a_model_path', preferring `a_gpu_exe' (Vulkan)
			-- and falling back to `a_cpu_exe'. The endpoint defaults to
			-- 127.0.0.1:`a_port' but is overridden by a shared rendezvous
			-- (LLAMA_SERVER_URL, then the registry file) when one is present.
		require
			model_not_empty: not a_model_path.is_empty
			port_in_range: a_port >= 1024 and a_port <= 65535
		do
			gpu_exe := a_gpu_exe
			cpu_exe := a_cpu_exe
			model_path := a_model_path
			host := "127.0.0.1"
			port := a_port
			default_port := a_port
			backend := "none"
			last_error := ""
			endpoint_source := "default"
			startup_timeout_seconds := 240
			discover_endpoint
		ensure
			model_set: model_path = a_model_path
			port_valid: port >= 1024 and port <= 65535
		end

feature -- Access

	gpu_exe, cpu_exe, model_path: STRING
	host: STRING
	port: INTEGER
	default_port: INTEGER
			-- The port passed to `make', preserved so a stale registry entry can
			-- be discarded in favour of it.
	backend: STRING
			-- "reused" / "GPU (Vulkan)" / "CPU" / "none".
	endpoint_source: STRING
			-- Where the endpoint came from: "env" / "registry" / "default".
	last_error: STRING
	startup_timeout_seconds: INTEGER

	from_shared_rendezvous: BOOLEAN
			-- Was the endpoint dictated by an external rendezvous (env var)?
			-- If so, this manager reuses only and never spawns or kills.
		do
			Result := endpoint_source ~ "env"
		end

	base_url: STRING
			-- e.g. http://127.0.0.1:8080
		do
			Result := "http://" + host + ":" + port.out
		end

	is_local: BOOLEAN
			-- Is the endpoint on this machine (so we may spawn a server there)?
		do
			Result := host ~ "127.0.0.1" or host ~ "localhost" or host ~ "0.0.0.0"
		end

	is_up: BOOLEAN
			-- Does a server answer /health at `base_url'? Checks the response body
			-- for the llama.cpp "ok" status (avoids `-w %{http_code}', whose `%'
			-- is mangled by Windows cmd, and `-o NUL').
		local
			l_proc: SIMPLE_PROCESS
			l_out: STRING_32
		do
			create l_proc.make
			l_proc.set_show_window (False)
			l_out := l_proc.command_output ("curl -s --max-time 5 %"" + base_url + "/health%"")
			Result := l_proc.was_successful and then l_out.has_substring ({STRING_32} "ok")
		end

feature -- Lifecycle

	ensure_up: BOOLEAN
			-- Guarantee a server is listening; True on success. Reuses a healthy
			-- server at `base_url' if one is there (the shared case); otherwise, if
			-- the endpoint is local and not an externally-dictated rendezvous,
			-- spawns one and records it for others to reuse.
		do
			last_error := ""
			if is_up then
				backend := "reused"
				Result := True
			elseif from_shared_rendezvous then
				backend := "none"
				last_error := "no server at the shared endpoint " + base_url
					+ " (LLAMA_SERVER_URL); this manager reuses only and will not spawn there"
			elseif not is_local then
				backend := "none"
				last_error := "endpoint " + base_url + " is remote; cannot spawn a server there"
			elseif not gpu_exe.is_empty and then spawn_and_wait (gpu_exe, 99) then
				backend := "GPU (Vulkan)"
				write_registry
				Result := True
			elseif not cpu_exe.is_empty and then spawn_and_wait (cpu_exe, 0) then
				backend := "CPU"
				write_registry
				Result := True
			else
				backend := "none"
				if last_error.is_empty then
					last_error := "no server came up within " + startup_timeout_seconds.out + "s"
				end
			end
		ensure
			up_on_success: Result implies is_up
		end

	stop
			-- Terminate the server this manager spawned (leaves a reused one, or a
			-- shared-rendezvous one, alone).
		do
			if attached server_process as al and then al.is_running then
				kill (al)
			end
		end

feature -- Discovery

	registry_path: STRING
			-- Well-known file where a spawned server records its endpoint so other
			-- processes can discover and reuse it.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			if attached l_env.temporary_directory_path as al then
				Result := al.name.to_string_8 + "/llama_server_registry.json"
			else
				Result := "llama_server_registry.json"
			end
		end

feature {NONE} -- Discovery implementation

	discover_endpoint
			-- Resolve the endpoint from the shared rendezvous, in priority order:
			-- LLAMA_SERVER_URL, then a healthy registry entry, else the default.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			if attached l_env.item ("LLAMA_SERVER_URL") as al_url and then not al_url.is_empty then
				if parse_endpoint (al_url.to_string_8) then
					endpoint_source := "env"
				end
			elseif attached registry_endpoint as al_reg and then parse_endpoint (al_reg) then
					-- Only adopt the registry endpoint if it is actually alive;
					-- a stale file must not stop us spawning a fresh server.
				if is_up then
					endpoint_source := "registry"
				else
					host := "127.0.0.1"
					port := default_port
					endpoint_source := "default"
				end
			end
		end

	registry_endpoint: detachable STRING
			-- The `url' recorded in the registry file, if any.
		local
			l_file: SIMPLE_FILE
			l_quick: SIMPLE_JSON_QUICK
		do
			create l_file.make (registry_path)
			if l_file.exists and then attached l_file.content as al_c and then not al_c.is_empty then
				create l_quick.make
				if attached l_quick.parse_object (al_c.to_string_8) as al_root
					and then attached al_root.string_item ({STRING_32} "url") as al_u
				then
					Result := al_u.to_string_8
				end
			end
		end

	parse_endpoint (a_url: STRING): BOOLEAN
			-- Set `host' and `port' from "http://host:port" (or "host:port").
			-- True if a valid host:port was extracted (state unchanged otherwise).
		local
			l_s, l_port_text: STRING
			l_colon, l_slash: INTEGER
		do
			l_s := a_url.twin
			l_s.left_adjust
			l_s.right_adjust
			if l_s.starts_with ("http://") then
				l_s := l_s.substring (8, l_s.count)
			elseif l_s.starts_with ("https://") then
				l_s := l_s.substring (9, l_s.count)
			end
			l_slash := l_s.index_of ('/', 1)
			if l_slash > 0 then
				l_s := l_s.substring (1, l_slash - 1)
			end
			l_colon := l_s.last_index_of (':', l_s.count)
			if l_colon > 1 and then l_colon < l_s.count then
				l_port_text := l_s.substring (l_colon + 1, l_s.count)
				if l_port_text.is_integer
					and then l_port_text.to_integer >= 1024
					and then l_port_text.to_integer <= 65535
				then
					host := l_s.substring (1, l_colon - 1)
					port := l_port_text.to_integer
					Result := True
				end
			end
		end

	write_registry
			-- Record this server's endpoint so other projects discover it by URL.
			-- Best-effort: a write failure is not fatal (sharing is an optimisation).
		local
			l_file: SIMPLE_FILE
			l_json, l_model, l_pid: STRING
		do
			l_model := model_path.twin
			l_model.replace_substring_all ("\", "/")
			if attached server_process as al then
				l_pid := al.process_id.out
			else
				l_pid := "0"
			end
			create l_json.make (160)
			l_json.append ("{%"url%": %"" + base_url + "%", ")
			l_json.append ("%"pid%": " + l_pid + ", ")
			l_json.append ("%"backend%": %"" + backend + "%", ")
			l_json.append ("%"model%": %"" + l_model + "%"}")
			create l_file.make (registry_path)
			if not l_file.set_content (l_json) then
					-- Ignore: registry is a convenience, not a requirement.
			end
		end

feature {NONE} -- Spawn implementation

	server_process: detachable SIMPLE_ASYNC_PROCESS
			-- The child we spawned (Void if reusing an external one).

	spawn_and_wait (a_exe: STRING; a_ngl: INTEGER): BOOLEAN
			-- Start `a_exe' offloading `a_ngl' layers, then poll /health until up
			-- or the timeout elapses.
		local
			l_proc: SIMPLE_ASYNC_PROCESS
			l_cmd: STRING
		do
			create l_proc.make
			l_proc.set_show_window (False)
			l_cmd := "%"" + a_exe + "%" -m %"" + model_path + "%""
				+ " --host 127.0.0.1 --port " + port.out
				+ " -ngl " + a_ngl.out + " -c 4096"
			l_proc.start (l_cmd)
			if l_proc.was_started_successfully then
				server_process := l_proc
				Result := poll_health
				if not Result then
					kill (l_proc)
					server_process := Void
				end
			else
				last_error := "could not launch " + a_exe
			end
		end

	kill (a_proc: SIMPLE_ASYNC_PROCESS)
			-- Terminate `a_proc' and its children via taskkill.
		local
			l_p: SIMPLE_PROCESS
		do
			if a_proc.is_started and then a_proc.process_id > 0 then
				create l_p.make
				l_p.set_show_window (False)
				l_p.launch ("taskkill /F /T /PID " + a_proc.process_id.out)
			end
		end

	poll_health: BOOLEAN
			-- Wait for /health, up to `startup_timeout_seconds' (model load is slow).
		local
			l_env: EXECUTION_ENVIRONMENT
			l_waited: INTEGER
		do
			create l_env
			from l_waited := 0 until Result or l_waited >= startup_timeout_seconds loop
				l_env.sleep (2_000_000_000) -- 2s in nanoseconds
				l_waited := l_waited + 2
				Result := is_up
			end
		end

end
