-- omz.yazi — Oh My Zsh prompt for Yazi.
--
-- Renders the active Oh My Zsh prompt in Yazi's header, the way omp.yazi does
-- for oh-my-posh. Every directory change starts an interactive zsh in the new
-- working directory, asks it to materialize `$PROMPT`, and paints the first
-- non-empty line into the header. The work runs in a Yazi job, so a slow shell
-- startup never blocks the UI.

local save = ya.sync(function(st, cwd, output)
	if cx.active.current.cwd == Url(cwd) then
		st.output = output
		local render = ui.render or ya.render
		render()
	end
end)

local get_shell = ya.sync(function(st)
	return st.shell
end)

-- oh-my-zsh normally applies the theme during startup, but a non-interactive
-- shell or a failed theme initializer can leave `$PROMPT` at zsh's builtin
-- default. Source the configured theme once in that case so the header still
-- shows a faithful prompt.
--
-- The markers keep the prompt separate from anything the shell prints while
-- starting up (version-manager banners, framework notices), so only the prompt
-- line reaches the header.
local render_script = [==[
if (( ${#precmd_functions} )); then
  for __omz_hook in ${precmd_functions[@]}; do
    (( $+functions[$__omz_hook] )) && $__omz_hook >/dev/null 2>&1
  done
  unset __omz_hook
fi
if [[ -z "${PROMPT}" || "${PROMPT}" == *'%m%# '* ]]; then
  [[ -r "${ZSH}/themes/${ZSH_THEME}.zsh-theme" ]] && source "${ZSH}/themes/${ZSH_THEME}.zsh-theme" >/dev/null 2>&1
fi
print -rn -- $'\x01OMZSTART\x01'
print -rn -- ${(%%)PROMPT}
print -rn -- $'\x01OMZEND\x01'
]==]

local function default_shell()
	local shell = os.getenv("SHELL") or ""
	if shell:match("zsh$") then
		return shell
	end
	return "zsh"
end

local function strip_ansi(text)
	return (text:gsub("\27%[[%d;?]*%a", ""))
end

local function prompt_line(stdout)
	local body = stdout:match("\1OMZSTART\1(.-)\1OMZEND\1") or stdout
	for line in body:gsub("\r", ""):gmatch("[^\n]+") do
		if strip_ansi(line):match("%S") then
			return (line:gsub("%s+$", ""))
		end
	end
	return ""
end

return {
	setup = function(st, args)
		Header:children_remove(1, Header.LEFT)
		Header:children_add(function()
			return ui.Line.parse(st.output or "")
		end, 1000, Header.LEFT)

		st.shell = (args and args.shell) or default_shell()
		st.output = ""

		local callback = function()
			local cwd = cx.active.current.cwd
			if st.cwd ~= cwd then
				st.cwd = cwd
				local emit = ya.emit or ya.manager_emit
				emit("plugin", { st._id, ya.quote(tostring(cwd), true) })
			end
		end

		ps.sub("cd", callback)
		ps.sub("tab", callback)
	end,

	entry = function(_, job)
		local cwd = job.args[1]
		if not cwd then
			return
		end

		local ok, output = pcall(function()
			return Command(get_shell()):arg({ "-i", "-c", render_script }):cwd(cwd):output()
		end)
		if not ok or not output then
			return
		end

		local text = prompt_line(output.stdout)
		if text ~= "" then
			save(cwd, text)
		end
	end,
}
