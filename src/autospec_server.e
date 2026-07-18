note
	description: "[
		Ensures there is always a llama.cpp server to run against. Reuses one
		already answering /health on the port; otherwise spawns one, preferring
		a Vulkan (GPU) build and falling back to a CPU build if the GPU server
		does not come up. Generic: takes the binary and model paths as arguments,
		so it depends on no particular model project -- point it at whatever
		llama-server + GGUF you have.
	]"
	author: "Larry Rix"

class
	AUTOSPEC_SERVER

create
	make

feature {NONE} -- Initialization

	make (a_gpu_exe, a_cpu_exe, a_model_path: STRING; a_port: INTEGER)
			-- Server manager for `a_model_path', preferring `a_gpu_exe' (Vulkan)
			-- and falling back to `a_cpu_exe', on 127.0.0.1:`a_port'.
		require
			model_not_empty: not a_model_path.is_empty
			port_in_range: a_port >= 1024 and a_port <= 65535
		do
			gpu_exe := a_gpu_exe
			cpu_exe := a_cpu_exe
			model_path := a_model_path
			port := a_port
			backend := "none"
			last_error := ""
			startup_timeout_seconds := 240
		ensure
			model_set: model_path = a_model_path
			port_set: port = a_port
		end

feature -- Access

	gpu_exe, cpu_exe, model_path: STRING
	port: INTEGER
	backend: STRING
			-- "reused" / "GPU (Vulkan)" / "CPU" / "none".
	last_error: STRING
	startup_timeout_seconds: INTEGER

	base_url: STRING
			-- e.g. http://127.0.0.1:8080
		do
			Result := "http://127.0.0.1:" + port.out
		end

	is_up: BOOLEAN
			-- Does a server answer /health on the port? Checks the response body
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
			-- Guarantee a server is listening; True on success. Sets `backend'.
		do
			last_error := ""
			if is_up then
				backend := "reused"
				Result := True
			elseif not gpu_exe.is_empty and then spawn_and_wait (gpu_exe, 99) then
				backend := "GPU (Vulkan)"
				Result := True
			elseif not cpu_exe.is_empty and then spawn_and_wait (cpu_exe, 0) then
				backend := "CPU"
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
			-- Terminate the server this manager spawned (leaves a reused one alone).
		do
			if attached server_process as al and then al.is_running then
				kill (al)
			end
		end

feature {NONE} -- Implementation

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
