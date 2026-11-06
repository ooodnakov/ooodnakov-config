-- Plugins are optional: a missing plugin directory or a plugin that throws
-- during setup must never abort Yazi startup. A fresh install used to leave
-- plugins/omp.yazi empty and `require("omp")` killed Yazi with
-- "Error: Lua runtime failed" before the first frame was drawn.
local function notify(content)
	if not ya or not ya.notify then
		return
	end
	pcall(ya.notify, { title = "yazi plugin", content = content, level = "warn", timeout = 5 })
end

local function setup_plugin(name, args)
	local loaded, plugin = pcall(require, name)
	if not loaded then
		notify(string.format("%s unavailable: %s", name, tostring(plugin)))
		return
	end
	local configured, err = pcall(plugin.setup, plugin, args)
	if not configured then
		notify(string.format("%s setup failed: %s", name, tostring(err)))
	end
end

local function home_dir()
	return os.getenv("HOME") or os.getenv("USERPROFILE") or ""
end

local function config_home()
	local xdg = os.getenv("XDG_CONFIG_HOME")
	if xdg and xdg ~= "" then
		return xdg
	end
	return home_dir() .. "/.config"
end

local function file_exists(path)
	local handle = io.open(path, "r")
	if handle then
		handle:close()
		return true
	end
	return false
end

-- The header mirrors the prompt of the shell the terminal runs: PowerShell and
-- the oh-my-posh zsh mode use the oh-my-posh plugin, every other zsh setup
-- (Oh My Zsh themes, Powerlevel10k, plain $PROMPT) uses the omz plugin.
local function is_windows()
	return os.getenv("OS") == "Windows_NT"
end

local shell_prompt = os.getenv("OOOCONF_ZSH_PROMPT") or "p10k"
if is_windows() or shell_prompt == "ohmyposh" then
	-- Render the same oh-my-posh theme the shell prompt uses, then fall back to
	-- the tracked canonical theme so an install without a synced color theme
	-- still gets a prompt line instead of the plugin's remote default config.
	local omp_config = os.getenv("OOOCONF_OMP_CONFIG")
	if not omp_config or omp_config == "" or not file_exists(omp_config) then
		omp_config = config_home() .. "/ohmyposh/ooodnakov.omp.json"
	end
	if file_exists(omp_config) then
		setup_plugin("omp", { config = omp_config })
	else
		notify("omp skipped: no oh-my-posh config found (run 'oooconf color <theme>')")
	end
else
	setup_plugin("omz")
end

setup_plugin("full-border")
setup_plugin("git", {
	-- Order of status signs showing in the linemode
	order = 1500,
})
setup_plugin("folder-rules")
