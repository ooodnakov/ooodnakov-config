local wezterm = require("wezterm")
local platform = require("utils.platform")

return {
  font = wezterm.font({
    family = "MesloLGS NF",
    weight = "Medium",
  }),
  font_size = platform.is_macos and 12 or 9.75,
  freetype_load_target = "Normal",
  freetype_render_target = "Normal",
}

