local wezterm = require("wezterm")
local platform = require("utils.platform")

local act = wezterm.action
local nf = wezterm.nerdfonts

local function safe_plugin(url)
	local ok, plugin = pcall(wezterm.plugin.require, url)
	if not ok then
		wezterm.log_warn("plugin load failed (skipped): " .. url .. " -> " .. tostring(plugin))
	end
	return plugin
end

local cmdpicker = safe_plugin("https://github.com/abidibo/wezterm-cmdpicker")
local quick_domains = safe_plugin("https://github.com/DavidRR-F/quick_domains.wezterm")
local resurrect = safe_plugin("https://github.com/MLFlexer/resurrect.wezterm")
local workspace_switcher = safe_plugin("https://github.com/MLFlexer/smart_workspace_switcher.wezterm")
if platform.is_mac then
	workspace_switcher.zoxide_path = "/opt/homebrew/bin/zoxide"
elseif platform.is_linux then
	workspace_switcher.zoxide_path = "/usr/bin/zoxide"
elseif platform.is_win then
	workspace_switcher.zoxide_path = "C:\\Users\\coolk\\AppData\\Local\\UniGetUI\\Chocolatey\\bin\\zoxide.exe"
end
local smart_splits = safe_plugin("https://github.com/mrjones2014/smart-splits.nvim")
local function env(name)
	local value = os.getenv(name)
	if value == "" then
		return nil
	end

	return value
end

local function default_ai_commander_renderer()
	return env("WEZTERM_AI_COMMANDER_RENDERER") or "rich"
end


local function require_plugin_without_host_module(url, module_name)
	local host_module = package.loaded[module_name]
	package.loaded[module_name] = nil
	local ok, plugin = pcall(wezterm.plugin.require, url)
	package.loaded[module_name] = host_module
	if not ok then
		error(plugin)
	end
	return plugin
end
local ai_commander_url = env("WEZTERM_AI_COMMANDER_PLUGIN_URL") or "https://github.com/ooodnakov/ai-commander.wezterm"
local ok_ac, ai_commander = pcall(require_plugin_without_host_module, ai_commander_url, "config")
if not ok_ac then
	wezterm.log_warn("plugin load failed (skipped): " .. ai_commander_url .. " -> " .. tostring(ai_commander))
	ai_commander = nil
end
local M = {}

local mod = {}
if platform.is_mac then
	mod.SUPER = "SUPER"
	mod.SUPER_REV = "SUPER|CTRL"
else
	mod.SUPER = "ALT"
	mod.SUPER_REV = "ALT|CTRL"
end


local function basename(path)
	return (path or ""):gsub("\\", "/"):match("([^/]+)$") or path or ""
end

local function restore_state(id, pane)
	local state_type = id:match("^([^/]+)")
	local state_name = id:match("([^/]+)$") or id
	state_name = state_name:gsub("%.json$", "")

	local opts = {
		relative = true,
		restore_text = true,
		resize_window = false,
		on_pane_restore = resurrect.tab_state.default_on_pane_restore,
	}

	if state_type == "workspace" then
		local state = resurrect.state_manager.load_state(state_name, "workspace")
		resurrect.workspace_state.restore_workspace(state, opts)
	elseif state_type == "window" then
		local state = resurrect.state_manager.load_state(state_name, "window")
		opts.window = pane:window()
		opts.close_open_tabs = true
		resurrect.window_state.restore_window(pane:window(), state, opts)
	elseif state_type == "tab" then
		local state = resurrect.state_manager.load_state(state_name, "tab")
		opts.tab = pane:tab()
		opts.close_open_panes = true
		resurrect.tab_state.restore_tab(pane:tab(), state, opts)
	end
end

local function fuzzy_restore(window, pane)
	if not (resurrect and type(resurrect) == "table" and resurrect.fuzzy_loader) then
		return
	end
	resurrect.fuzzy_loader.fuzzy_load(window, pane, function(id)
		if id then
			restore_state(id, pane)
		end
	end, {
		title = "Restore WezTerm State",
		description = "Select a saved workspace, window, or tab to restore",
		fuzzy_description = "Search saved state: ",
		show_state_with_date = true,
		date_format = "%Y-%m-%d %H:%M",
	})
end

local function fuzzy_delete(window, pane)
	if not (resurrect and type(resurrect) == "table" and resurrect.fuzzy_loader and resurrect.state_manager) then
		return
	end
	resurrect.fuzzy_loader.fuzzy_load(window, pane, function(id)
		if id then
			resurrect.state_manager.delete_state(id)
		end
	end, {
		title = "Delete WezTerm State",
		description = "Select a saved workspace, window, or tab to delete",
		fuzzy_description = "Delete saved state: ",
		show_state_with_date = true,
		date_format = "%Y-%m-%d %H:%M",
	})
end

local function ai_action(method)
	return wezterm.action_callback(function(window, pane)
		if ai_commander and type(ai_commander) == "table" and type(ai_commander[method]) == "function" then
			ai_commander[method](window, pane)
		end
	end)
end

local plugin_keys = {
	{
		key = "X",
		mods = "ALT|SHIFT",
		action = ai_action("show_prompt"),
		desc = "Ask AI Commander to generate shell commands",
	},
	{
		key = "X",
		mods = "CTRL|SHIFT",
		action = ai_action("show_last_results"),
		desc = "Show last AI Commander command results",
	},
	{
		key = "H",
		mods = "ALT|SHIFT",
		action = ai_action("show_history"),
		desc = "Show AI Commander prompt history",
	},
	{
		key = "A",
		mods = "CTRL|SHIFT",
		action = ai_action("show_ask_inline"),
		desc = "Ask AI Commander in a split pane",
	},
	{
		key = "E",
		mods = "CTRL|SHIFT",
		action = ai_action("complete_current_command"),
		desc = "Complete current shell command with AI Commander",
	},
	{
		key = "R",
		mods = "ALT|SHIFT",
		action = ai_action("repeat_last_prompt"),
		desc = "Repeat last AI Commander command prompt with current context",
	},
	{
		key = "P",
		mods = "CTRL|SHIFT",
		action = ai_action("check_provider"),
		desc = "Check AI Commander provider and backend",
	},
	{
		key = "B",
		mods = "CTRL|SHIFT",
		action = ai_action("setup_backend"),
		desc = "Set up AI Commander backend dependencies",
	},
	{
		key = "s",
		mods = "LEADER",
		action = wezterm.action_callback(function(window, pane)
			if workspace_switcher and type(workspace_switcher) == "table" and workspace_switcher.switch_workspace then
				window:perform_action(workspace_switcher.switch_workspace(), pane)
			end
		end),
		desc = "Switch workspace or zoxide project",
	},
	{
		key = "S",
		mods = "LEADER",
		action = wezterm.action_callback(function(window, pane)
			if workspace_switcher and type(workspace_switcher) == "table" and workspace_switcher.switch_to_prev_workspace then
				window:perform_action(workspace_switcher.switch_to_prev_workspace(), pane)
			end
		end),
		desc = "Switch to previous workspace",
	},
	{
		key = "r",
		mods = "LEADER",
		action = wezterm.action_callback(fuzzy_restore),
		desc = "Restore saved WezTerm workspace/window/tab",
	},
	{
		key = "R",
		mods = "LEADER",
		action = wezterm.action_callback(function(_window, _pane)
			if resurrect and type(resurrect) == "table" and resurrect.state_manager and resurrect.workspace_state then
				resurrect.state_manager.save_state(resurrect.workspace_state.get_workspace_state())
			end
		end),
		desc = "Save current WezTerm workspace state",
	},
	{
		key = "D",
		mods = "LEADER",
		action = wezterm.action_callback(fuzzy_delete),
		desc = "Delete saved WezTerm state",
	},
}
for _, key in ipairs(plugin_keys) do
	if type(key.action) == "table" and key.action ~= wezterm.action_callback then
		-- ok
	end
end

local function safe_call(plugin, method, ...)
	if plugin == nil then
		return
	end
	local args = { ... }
	local n = select("#", ...)
	local ok, err = pcall(function()
		local fn
		if type(plugin) == "table" then
			fn = plugin[method]
		end
		if type(fn) ~= "function" then
			return
		end
		fn(table.unpack(args, 1, n))
	end)
	if not ok then
		wezterm.log_warn("plugin " .. tostring(method) .. " failed: " .. tostring(err))
	end
end

local function safe_set(plugin, key, value)
	if plugin == nil or type(plugin) ~= "table" then
		return
	end
	local ok, err = pcall(function()
		plugin[key] = value
	end)
	if not ok then
		wezterm.log_warn("plugin set " .. tostring(key) .. " failed: " .. tostring(err))
	end
end

function M.apply_to_config(config)
	safe_call(ai_commander, "apply_to_config", config, {
		provider = "openai",
		auth_type = {
			openai = "oauth",
		},
		renderer = default_ai_commander_renderer(),
		max_chat_context_chars = 120000,
		max_chat_history_messages = 12,
		max_chat_history_chars = 120000,
		command_context_output_lines = 40,
		command_context_output_chars = 6000,
	})

	safe_set(workspace_switcher, "workspace_formatter", function(label)
		return wezterm.format({
			{ Foreground = { Color = "#74c7ec" } },
			{ Text = nf.md_folder_star .. "  " },
			{ Attribute = { Intensity = "Bold" } },
			{ Text = basename(label) },
			{ Attribute = { Intensity = "Normal" } },
			{ Foreground = { Color = "#6c7086" } },
			{ Text = "  " .. label },
		})
	end)

	if resurrect and type(resurrect) == "table" and type(resurrect.state_manager) == "table" then
		local ok1, err1 = pcall(function()
			resurrect.state_manager.set_max_nlines(5000)
			resurrect.state_manager.periodic_save({
				interval_seconds = 900,
				save_workspaces = true,
				save_windows = false,
				save_tabs = false,
			})
		end)
		if not ok1 then
			wezterm.log_warn("resurrect state_manager setup failed: " .. tostring(err1))
		end

		local ok2, err2 = pcall(function()
			wezterm.on("smart_workspace_switcher.workspace_switcher.created", function(window, _path, label)
				resurrect.workspace_state.restore_workspace(resurrect.state_manager.load_state(label, "workspace"), {
					window = window,
					relative = true,
					restore_text = true,
					resize_window = false,
					on_pane_restore = resurrect.tab_state.default_on_pane_restore,
				})
			end)

			wezterm.on("smart_workspace_switcher.workspace_switcher.selected", function()
				resurrect.state_manager.save_state(resurrect.workspace_state.get_workspace_state())
			end)
		end)
		if not ok2 then
			wezterm.log_warn("resurrect event wiring failed: " .. tostring(err2))
		end
	end

	config.keys = config.keys or {}
	for _, key in ipairs(plugin_keys) do
		table.insert(config.keys, key)
	end
	safe_call(cmdpicker, "register", plugin_keys)

	safe_call(smart_splits, "apply_to_config", config, {
		direction_keys = { "h", "j", "k", "l" },
		modifiers = {
			move = mod.SUPER,
			resize = mod.SUPER_REV,
		},
		default_amount = 3,
		log_level = "warn",
	})

	safe_call(quick_domains, "apply_to_config", config, {
		keys = {
			{ vsplit = { key = "v", mods = "LEADER", tbl = "" } },
			{ hsplit = { key = "h", mods = "LEADER", tbl = "" } },
			{ attach = { key = "d", mods = "LEADER", tbl = "" } },
		},
		auto = {
			ssh_ignore = true,
			exec_ignore = {
				ssh = true,
				docker = true,
				kubernetes = true,
			},
		},
	})

	safe_call(cmdpicker, "apply_to_config", config, {
		key = " ",
		mods = "LEADER",
		title = "WezTerm Command Picker",
		fuzzy_description = "Search command: ",
		include_defaults = false,
		include_key_tables = true,
	})
end

return M
