return {
  automatically_reload_config = true,
  audible_bell = "Disabled",
  exit_behavior = "CloseOnCleanExit",
  exit_behavior_messaging = "Verbose",
  status_update_interval = 1000,
  scrollback_lines = 20000,
  initial_cols = 120,
  initial_rows = 30,
  window_close_confirmation = "NeverPrompt",
  use_fancy_tab_bar = false,
  hide_tab_bar_if_only_one_tab = true,
  front_end = "WebGpu",
  color_scheme = "Catppuccin Mocha",
  hyperlink_rules = {
    { regex = "\\((\\w+://\\S+)\\)", format = "$1", highlight = 1 },
    { regex = "\\[(\\w+://\\S+)\\]", format = "$1", highlight = 1 },
    { regex = "\\{(\\w+://\\S+)\\}", format = "$1", highlight = 1 },
    { regex = "<(\\w+://\\S+)>", format = "$1", highlight = 1 },
    { regex = "\\b\\w+://\\S+[)/a-zA-Z0-9-]+", format = "$0" },
    { regex = "\\b\\w+@[\\w-]+(\\.[\\w-]+)+\\b", format = "mailto:$0" },
  },
}

