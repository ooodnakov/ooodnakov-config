local wezterm = require("wezterm")
local config = require("config")
local local_override_path = wezterm.home_dir .. "/.config/ooodnakov/local/wezterm.lua"

local handle = io.open(local_override_path, "r")
if handle then
  handle:close()
  local ok, local_override = pcall(dofile, local_override_path)
  if ok and type(local_override) == "table" then
    for key, value in pairs(local_override) do
      config[key] = value
    end
  end
end

return config
