-- omz.yazi — Oh My Zsh prompt for Yazi.
--
-- Renders the active Oh My Zsh (or Powerlevel10k / oh-my-posh) prompt in Yazi's
-- header using a single persistent non-interactive zsh worker per session.
-- Directory changes flow over a tokenized stdin/stdout pipe, so prompt updates
-- do not fork zsh on every `cd`, and rapid navigation coalesces cleanly.

local DEFAULT_TIMEOUT_MS = 5000
local INITIAL_TIMEOUT_FLOOR_MS = 10000
local MAX_CONSECUTIVE_FAILURES = 5
local TOKEN_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

local DEFAULT_IGNORE_HOOKS = {
	"direnv",
	"auto_uv_env",
	"nvm",
	"fnm",
	"pyenv",
	"rbenv",
	"conda",
	"zoxide",
}

local seeded = false

-- The worker runs as a *non-interactive* `zsh -c` process: interactive startup
-- attaches zsh/zle to a tty and triggers terminal capability probes whose
-- replies leak into the parent shell's input buffer.
--
-- Protocol stdout is duplicated to a private FD before sourcing `.zshrc`, and
-- FD 1/2 are redirected to `/dev/null` so banners or plugin notices cannot
-- corrupt replies. Each reply is framed as `<token>:<seq>:<payload>`.
local worker_script = [==[
exec {__omz_out}>&1 1>/dev/null 2>/dev/null
__omz_rc="${ZDOTDIR:-$HOME}/.zshrc"
[[ -r "$__omz_rc" ]] && source "$__omz_rc"
unset __omz_rc
if [[ -z "${PROMPT:-}" || "${PROMPT:-}" == *'%m%# '* ]]; then
  [[ -n "${ZSH:-}" && -n "${ZSH_THEME:-}" && -r "${ZSH}/themes/${ZSH_THEME}.zsh-theme" ]] && source "${ZSH}/themes/${ZSH_THEME}.zsh-theme"
fi
chpwd_functions=()
typeset -a __omz_ignore
__omz_ignore=()
for __omz_pat in "${(@s.:.)${OMZ_YAZI_IGNORE_HOOKS:-}}"; do
  [[ -n "$__omz_pat" ]] && __omz_ignore+=("${__omz_pat:l}")
done
unset __omz_pat
__omz_bs='\'

while IFS= read -r __omz_req; do
  __omz_req="${__omz_req%$'\r'}"
  [[ -z "$__omz_req" ]] && continue
  __omz_seq="${__omz_req%% *}"
  __omz_enc="${__omz_req#* }"
  __omz_dir="${(g::)__omz_enc}"
  if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
    if [[ "$__omz_dir" == [A-Za-z]:['\/']* ]]; then
      __omz_dir="/${__omz_dir[1]:l}/${${__omz_dir[4,-1]}//${~${(q)__omz_bs}}//}"
    fi
  fi
  if builtin cd -q -- "$__omz_dir" 2>/dev/null; then
    if (( ${+precmd_functions} && ${#precmd_functions} )); then
      for __omz_hook in "${precmd_functions[@]}"; do
        (( $+functions[$__omz_hook] )) || continue
        __omz_skip=0
        for __omz_pat in "${__omz_ignore[@]}"; do
          if [[ "${__omz_hook:l}" == *"$__omz_pat"* ]]; then
            __omz_skip=1
            break
          fi
        done
        if (( __omz_skip )); then
          continue
        fi
        true
        "$__omz_hook"
      done
    fi
    true
    __omz_raw=${(%%)${PROMPT:-}}
    __omz_raw=${__omz_raw//$'\r'/}
    __omz_payload=${__omz_raw//$'\n'/$'\x1e'}
    print -u $__omz_out -r -- "${OMZ_YAZI_TOKEN}:${__omz_seq}:${__omz_payload}"
  else
    print -u $__omz_out -r -- "${OMZ_YAZI_TOKEN}:${__omz_seq}:"
  fi
done
]==]

local save = ya.sync(function(st, cwd, output)
	if tostring(cx.active.current.cwd) == tostring(cwd) then
		st.output = output
		local render = ui.render or ya.render
		render()
	end
end)

local get_state = ya.sync(function(st)
	return {
		pending_seq = st.pending_seq,
		pending_cwd = st.pending_cwd,
		shell = st.shell,
		timeout = st.timeout,
		ignore_hooks = st.ignore_hooks,
	}
end)

local run_worker

local mark_worker_stopped = ya.sync(function(st, last_seq, consecutive_failures)
	st.worker_running = false
	if
		ya
		and type(ya.async) == "function"
		and (consecutive_failures or 0) < MAX_CONSECUTIVE_FAILURES
		and (st.pending_seq or 0) > (last_seq or 0)
	then
		st.worker_running = true
		ya.async(run_worker)
	end
end)

local function now()
	return (ya and ya.time and ya.time()) or os.time()
end

local function default_shell()
	local shell = os.getenv("SHELL") or ""
	if shell:match("zsh$") then
		return shell
	end
	return "zsh"
end

local function normalize_ignore_hooks(list)
	local out = {}
	for _, entry in ipairs(list) do
		out[#out + 1] = tostring(entry)
	end
	return out
end

local function make_token()
	if not seeded then
		seeded = true
		local addr = tonumber((tostring({}):match("0x(%x+)") or "0"), 16) or 0
		local seed = os.time() + math.floor(os.clock() * 1e6) + (addr % 0x7fffffff)
		pcall(math.randomseed, seed)
	end
	local parts = {
		string.format("%x%x", os.time(), math.floor(os.clock() * 1e6)),
		(tostring({}):gsub("[^%w]", "")),
	}
	for _ = 1, 16 do
		local idx = math.random(1, #TOKEN_CHARS)
		parts[#parts + 1] = TOKEN_CHARS:sub(idx, idx)
	end
	return table.concat(parts)
end

local function hex_encode(s)
	return (s:gsub(".", function(c)
		return string.format("\\x%02x", c:byte())
	end))
end

local function strip_sgr(text)
	return (text:gsub("\27%[[0-9:;]*m", ""))
end

local function sanitize_prompt(line)
	local out = {}
	local i = 1
	local len = #line

	while i <= len do
		local esc = line:find("\27", i, true)
		if not esc then
			out[#out + 1] = line:sub(i):gsub("[%z\1-\31\127]", "")
			break
		end

		if esc > i then
			out[#out + 1] = line:sub(i, esc - 1):gsub("[%z\1-\31\127]", "")
		end

		local nxt = line:sub(esc + 1, esc + 1)
		if nxt == "[" then
			-- CSI: ESC [ params (0x30-0x3F) intermediates (0x20-0x2F) final (0x40-0x7E)
			local _, fin_end, params, final = line:find("^%[([\48-\63]*[\32-\47]*)([\64-\126])", esc + 1)
			if fin_end then
				if final == "m" and params:match("^[0-9:;]*$") then
					out[#out + 1] = line:sub(esc, fin_end)
				end
				i = fin_end + 1
			else
				i = esc + 1
			end
		elseif nxt == "]" then
			-- OSC: terminated by ST (ESC \) or BEL (\7)
			local st_pos = line:find("\27\\", esc + 2, true)
			local bel_pos = line:find("\7", esc + 2, true)
			if st_pos and (not bel_pos or st_pos < bel_pos) then
				i = st_pos + 2
			elseif bel_pos then
				i = bel_pos + 1
			else
				break
			end
		elseif nxt == "P" or nxt == "X" or nxt == "^" or nxt == "_" then
			-- DCS (P), SOS (X), PM (^), APC (_): terminated by ST (ESC \)
			local st_pos = line:find("\27\\", esc + 2, true)
			if st_pos then
				i = st_pos + 2
			else
				break
			end
		else
			-- Other 2-byte / nF ESC sequence: ESC intermediates (0x20-0x2F) final (0x30-0x7E)
			local _, fin_end = line:find("^[\32-\47]*[\48-\126]", esc + 1)
			if fin_end then
				i = fin_end + 1
			else
				i = esc + 1
			end
		end
	end

	return table.concat(out)
end

local function prompt_line(payload)
	for line in payload:gsub("\r", ""):gmatch("[^\30]+") do
		local clean = sanitize_prompt(line)
		if strip_sgr(clean):match("%S") then
			return (clean:gsub("%s+$", ""))
		end
	end
	return ""
end

local function spawn_worker(shell, ignore_hooks, token)
	local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "."
	return Command(shell)
		:arg({ "-c", worker_script })
		:cwd(home)
		:env("OMZ_YAZI", "1")
		:env("OMZ_YAZI_TOKEN", token)
		:env("OMZ_YAZI_IGNORE_HOOKS", table.concat(ignore_hooks or {}, ":"))
		:env("POWERLEVEL9K_INSTANT_PROMPT", "off")
		:stdin(Command.PIPED)
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:spawn()
end

local function query_worker(child, token, seq, cwd, timeout_ms)
	local req = string.format("%d %s\n", seq, hex_encode(cwd))
	local ok = child:write_all(req)
	if not ok then
		return false
	end
	local fok = child:flush()
	if not fok then
		return false
	end

	local line, event
	if child.read_line_with then
		line, event = child:read_line_with({ timeout = timeout_ms })
	else
		line, event = child:read_line()
	end

	if event ~= 0 or type(line) ~= "string" then
		return false
	end

	local prefix = token .. ":" .. tostring(seq) .. ":"
	if line:sub(1, #prefix) ~= prefix then
		return false
	end

	return true, (line:sub(#prefix + 1):gsub("[\r\n]+$", ""))
end

local function kill_child(child)
	if child then
		pcall(function()
			child:start_kill()
		end)
	end
end

run_worker = function()
	local child = nil
	local token = nil
	local last_seq = 0
	local consecutive_failures = 0
	local last_active_at = now()

	pcall(function()
		while true do
			local state = get_state()
			if not state or not state.pending_cwd or (state.pending_seq or 0) <= last_seq then
				local idle_for = now() - last_active_at
				ya.sleep(idle_for < 2 and 0.03 or 0.08)
			else
				local target_seq = state.pending_seq
				local target_cwd = state.pending_cwd
				last_active_at = now()

				local just_spawned = false
				if not child then
					token = make_token()
					local ok, spawned = pcall(spawn_worker, state.shell, state.ignore_hooks, token)
					if ok and spawned then
						child = spawned
						just_spawned = true
					else
						token = nil
						consecutive_failures = consecutive_failures + 1
						if consecutive_failures >= MAX_CONSECUTIVE_FAILURES then
							break
						end
						ya.sleep(math.min(0.2 * consecutive_failures, 1.0))
					end
				end

				if child then
					local timeout_ms = just_spawned
							and math.max(state.timeout or DEFAULT_TIMEOUT_MS, INITIAL_TIMEOUT_FLOOR_MS)
						or (state.timeout or DEFAULT_TIMEOUT_MS)
					local q_ok, ok_reply, payload = pcall(query_worker, child, token, target_seq, target_cwd, timeout_ms)
					if q_ok and ok_reply then
						consecutive_failures = 0
						last_seq = target_seq
						last_active_at = now()
						local text = prompt_line(payload)
						if text ~= "" then
							save(target_cwd, text)
						end
					else
						kill_child(child)
						child = nil
						token = nil
						consecutive_failures = consecutive_failures + 1
						if consecutive_failures >= MAX_CONSECUTIVE_FAILURES then
							break
						end
						ya.sleep(math.min(0.2 * consecutive_failures, 1.0))
					end
				end
			end
		end
	end)

	kill_child(child)
	mark_worker_stopped(last_seq, consecutive_failures)
end

return {
	setup = function(st, args)
		Header:children_remove(1, Header.LEFT)
		Header:children_add(function()
			return ui.Line.parse(st.output or "")
		end, 1000, Header.LEFT)

		local timeout = tonumber(args and args.timeout) or DEFAULT_TIMEOUT_MS
		if timeout <= 0 then
			timeout = DEFAULT_TIMEOUT_MS
		end

		st.shell = (args and args.shell) or default_shell()
		st.timeout = timeout
		st.ignore_hooks = normalize_ignore_hooks((args and args.ignore_hooks) or DEFAULT_IGNORE_HOOKS)
		st.output = ""
		st.cwd = nil
		st.seq = 0
		st.pending_seq = 0
		st.pending_cwd = nil
		st.worker_running = false

		local callback = function()
			local cwd = cx.active.current.cwd
			if cwd and st.cwd ~= cwd then
				st.cwd = cwd
				if ya and type(ya.async) == "function" then
					st.seq = st.seq + 1
					st.pending_seq = st.seq
					st.pending_cwd = tostring(cwd)
					if not st.worker_running then
						st.worker_running = true
						ya.async(run_worker)
					end
				else
					local emit = ya.emit or ya.manager_emit
					emit("plugin", { st._id, tostring(cwd) })
				end
			end
		end

		ps.sub("cd", callback)
		ps.sub("tab", callback)
	end,

	entry = function(_, job)
		local cwd = job and job.args and job.args[1]
		if not cwd or cwd == "" then
			return
		end
		local state = get_state()
		if not state then
			return
		end

		local token = make_token()
		local ok, child = pcall(spawn_worker, state.shell, state.ignore_hooks, token)
		if not ok or not child then
			return
		end

		local timeout_ms = math.max(state.timeout or DEFAULT_TIMEOUT_MS, INITIAL_TIMEOUT_FLOOR_MS)
		local q_ok, ok_reply, payload = pcall(query_worker, child, token, 1, cwd, timeout_ms)
		kill_child(child)
		if q_ok and ok_reply then
			local text = prompt_line(payload)
			if text ~= "" then
				save(cwd, text)
			end
		end
	end,
}
