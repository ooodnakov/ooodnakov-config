-- ~/.config/sketchybar/items/scratchpad_dot.lua

local colors = require("colors")

local display = 1

local scratchpad_dot = sbar.add("item", "scratchpad_dot", {
  -- "e" = right of notch
  position = "q",
  display = display,

  drawing = false,
  width = 24,
  y_offset = -3,

  icon = {
    drawing = true,
    string = "󰏗", -- small pin / marker-like glyph
    font = "MesloLGSDZ Nerd Font Mono:Regular:20.0",
    color = colors.TEXT_ORANGE,
    padding_left = 6,
    padding_right = 6,
  },

  label = {
    drawing = false,
  },

  background = {
    drawing = true,
    color = colors.BACKGROUND,
    border_color = colors.TEXT_ORANGE,
    border_width = 1,
    corner_radius = 12,
    height = 24,
  },
})

scratchpad_dot:subscribe("scratchpad_dot_on", function()
  scratchpad_dot:set({
    display = display,
    drawing = true,
  })
end)

scratchpad_dot:subscribe("scratchpad_dot_off", function()
  scratchpad_dot:set({
    display = display,
    drawing = false,
  })
end)
