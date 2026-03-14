local wezterm = require('wezterm')
local Config = require('config')

require('utils.backdrops')
   -- :set_focus('#000000')
   -- :set_images_dir(require('wezterm').home_dir .. '/Pictures/Wallpapers/')
   :set_images()
   :random()

require('events.left-status').setup()
require('events.right-status').setup({ date_format = '%a %H:%M:%S' })
require('events.tab-title').setup({ hide_active_tab_unseen = false, unseen_icon = 'numbered_box' })
require('events.new-tab-button').setup()
require('events.gui-startup').setup()

local config = Config:init()
   :append(require('config.appearance'))
   :append(require('config.bindings'))
   :append(require('config.domains'))
   :append(require('config.fonts'))
   :append(require('config.general'))
   :append(require('config.launch')).options

local local_override_path = wezterm.home_dir .. '/.config/ooodnakov/local/wezterm.lua'
local handle = io.open(local_override_path, 'r')
if handle then
   handle:close()
   local ok, local_override = pcall(dofile, local_override_path)
   if ok and type(local_override) == 'table' then
      config:append(local_override)
   end
end

return config.options
