-- Plugins are optional: a missing plugin directory or a plugin that throws
-- during setup must never abort Yazi startup. A fresh install used to leave a
-- plugin directory empty and `require()` killed Yazi with
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

-- The header mirrors the zsh prompt (Oh My Zsh themes, Powerlevel10k, and the
-- oh-my-posh zsh mode). Windows hosts run PowerShell prompts and skip it.
local function is_windows()
	return os.getenv("OS") == "Windows_NT"
end

if not is_windows() then
	setup_plugin("omz")
end

setup_plugin("full-border")
setup_plugin("git", {
	-- Order of status signs showing in the linemode
	order = 1500,
})
setup_plugin("folder-rules")
