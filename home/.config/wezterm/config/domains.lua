local platform = require("utils.platform")

local options = {
  ssh_domains = {
    { name = "site", remote_address = "site" },
    { name = "sitealex", remote_address = "sitealex" },
    { name = "orange", remote_address = "orange" },
    { name = "router", remote_address = "router" },
  },
  unix_domains = {},
  wsl_domains = {},
}

if platform.is_windows then
  options.wsl_domains = {
    {
      name = "wsl:ubuntu-zsh",
      distribution = "Ubuntu",
      username = "user",
      default_cwd = "/home/user",
      default_prog = { "zsh", "-l" },
    },
    {
      name = "wsl:ubuntu-bash",
      distribution = "Ubuntu",
      username = "user",
      default_cwd = "/home/user",
      default_prog = { "bash", "-l" },
    },
  }
end

return options
