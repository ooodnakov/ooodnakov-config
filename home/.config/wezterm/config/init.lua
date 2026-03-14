local wezterm = require("wezterm")
local platform = require("utils.platform")

local config = wezterm.config_builder()

config.automatically_reload_config = true
config.audible_bell = "Disabled"
config.exit_behavior = "CloseOnCleanExit"
config.exit_behavior_messaging = "Verbose"
config.scrollback_lines = 20000
config.initial_cols = 120
config.initial_rows = 30
config.window_close_confirmation = "NeverPrompt"
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true
config.front_end = "WebGpu"

if platform.is_windows then
  config.default_prog = { "pwsh", "-NoLogo" }
  config.launch_menu = {
    { label = "PowerShell Core", args = { "pwsh", "-NoLogo" } },
    { label = "PowerShell Desktop", args = { "powershell" } },
    { label = "Command Prompt", args = { "cmd" } }
  }
elseif platform.is_macos then
  config.default_prog = { "zsh", "-l" }
  config.launch_menu = {
    { label = "Zsh", args = { "zsh", "-l" } },
    { label = "Bash", args = { "bash", "-l" } }
  }
else
  config.default_prog = { "zsh", "-l" }
  config.launch_menu = {
    { label = "Zsh", args = { "zsh", "-l" } },
    { label = "Bash", args = { "bash", "-l" } }
  }
end

config.font = wezterm.font({
  family = "MesloLGS NF",
  weight = "Medium"
})
config.font_size = platform.is_macos and 12 or 9.75
config.color_scheme = "Catppuccin Mocha"

require("events.right-status").setup()

return config

