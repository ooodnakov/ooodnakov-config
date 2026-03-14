local wezterm = require("wezterm")

local M = {}

function M.setup()
  wezterm.on("update-right-status", function(window, _)
    local text = wezterm.strftime("%a %H:%M:%S")
    window:set_right_status(wezterm.format({
      { Background = { Color = "#2f2f2f" } },
      { Foreground = { Color = "#fafafa" } },
      { Text = " " .. text .. " " }
    }))
  end)
end

return M

