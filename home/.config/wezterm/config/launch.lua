local platform = require("utils.platform")

local options = {
  default_prog = {},
  launch_menu = {},
}

if platform.is_windows then
  options.default_prog = { "pwsh", "-NoLogo" }
  options.launch_menu = {
    { label = "PowerShell Core", args = { "pwsh", "-NoLogo" } },
    { label = "PowerShell Desktop", args = { "powershell" } },
    { label = "Command Prompt", args = { "cmd" } },
    { label = "Nushell", args = { "nu" } },
  }
elseif platform.is_macos then
  options.default_prog = { "zsh", "-l" }
  options.launch_menu = {
    { label = "Zsh", args = { "zsh", "-l" } },
    { label = "Bash", args = { "bash", "-l" } },
    { label = "Fish", args = { "fish", "-l" } },
  }
else
  options.default_prog = { "zsh", "-l" }
  options.launch_menu = {
    { label = "Zsh", args = { "zsh", "-l" } },
    { label = "Bash", args = { "bash", "-l" } },
    { label = "Fish", args = { "fish", "-l" } },
  }
end

return options

