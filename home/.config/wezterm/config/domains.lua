local wezterm = require("wezterm")
local platform = require("utils.platform")

local options = {
	-- Personal SSH domains are loaded from the optional local/private overlay
	-- ({DATA_HOME}/ooodnakov-config/wezterm-domains.lua or
	-- ~/.config/ooodnakov/local/wezterm-domains.lua).
	ssh_domains = {},
	unix_domains = {},
	wsl_domains = {},
}

if platform.is_win then
	options.wsl_domains = {
		{
			name = "WSL",
			distribution = "Ubuntu-24.04",
			username = "user",
			default_cwd = "/home/user",
			default_prog = { "zsh", "-l" },
		},
	}
end

local function merge_domains(base, overlay)
	if type(overlay) ~= "table" then
		return base
	end
	local by_name = {}
	for idx, entry in ipairs(base) do
		if type(entry) == "table" and entry.name then
			by_name[entry.name] = idx
		end
	end
	for _, entry in ipairs(overlay) do
		if type(entry) == "table" then
			local existing_idx = entry.name and by_name[entry.name]
			if existing_idx then
				base[existing_idx] = entry
			else
				table.insert(base, entry)
				if entry.name then
					by_name[entry.name] = #base
				end
			end
		end
	end
	return base
end

local env_domains = os.getenv("OOOCONF_WEZTERM_DOMAINS")
local xdg_data = os.getenv("XDG_DATA_HOME")
local default_data_home = wezterm.home_dir .. "/.local/share"
local data_home = (xdg_data and xdg_data ~= "") and xdg_data or default_data_home

local candidates = {}
if env_domains and env_domains ~= "" then
	table.insert(candidates, env_domains)
end
table.insert(candidates, data_home .. "/ooodnakov-config/wezterm-domains.lua")
if platform.is_win and data_home ~= default_data_home then
	table.insert(candidates, default_data_home .. "/ooodnakov-config/wezterm-domains.lua")
end
table.insert(candidates, wezterm.home_dir .. "/.config/ooodnakov/local/wezterm-domains.lua")

for _, path in ipairs(candidates) do
	local handle = io.open(path, "r")
	if handle then
		handle:close()
		local ok, overlay = pcall(dofile, path)
		if ok and type(overlay) == "table" then
			merge_domains(options.ssh_domains, overlay.ssh_domains)
			merge_domains(options.unix_domains, overlay.unix_domains)
			merge_domains(options.wsl_domains, overlay.wsl_domains)
			break
		end
	end
end

return options
