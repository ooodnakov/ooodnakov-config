local platform = require("utils.platform")

local options = {
	ssh_domains = {
		{ name = "site",   remote_address = "dnakov.ooo",  username = "fr" },
		{ name = "orange", remote_address = "orangepi",    username = "rem" },
		{ name = "router", remote_address = "openwrt.lan", username = "root" },
		{ name = "think",  remote_address = "tc",          username = "th" },
	},
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

return options
