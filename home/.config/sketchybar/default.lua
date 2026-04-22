local colors = require("colors")

-- Equivalent to the --default domain
sbar.default({
  padding_left = 3,
  padding_right = 3,
  icon = {
    font = "MesloLGSDZ Nerd Font Mono:Bold:17.0",
    color = colors.TEXT_GREY,
    padding_left = 2,
    padding_right = 2,
  },
  label = {
    font = "MesloLGSDZ Nerd Font Mono:Bold:17.0",
    color = colors.TEXT_GREY,
    padding_left = 2,
    padding_right = 2,
  },
  updates = "on",
  y_offset = -3,
})
