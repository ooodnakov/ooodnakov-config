local wezterm = require("wezterm")

local config = wezterm.config_builder()

for key, value in pairs(require("config.general")) do
  config[key] = value
end

for key, value in pairs(require("config.fonts")) do
  config[key] = value
end

for key, value in pairs(require("config.launch")) do
  config[key] = value
end

for key, value in pairs(require("config.domains")) do
  config[key] = value
end

require("events.right-status").setup()

return config
