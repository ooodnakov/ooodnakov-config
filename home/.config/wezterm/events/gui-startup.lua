local wezterm = require('wezterm')
local mux = wezterm.mux

local M = {}

M.setup = function()
   wezterm.on('gui-startup', function(cmd)
      local spawn = cmd or {}
      local workspace = wezterm.getenv('OOODNAKOV_WEZTERM_WORKSPACE') or 'default'
      local startup_cwd = wezterm.getenv('OOODNAKOV_WEZTERM_CWD')

      if spawn.workspace == nil then
         spawn.workspace = workspace
      end

      if startup_cwd and spawn.cwd == nil then
         spawn.cwd = startup_cwd
      end

      mux.spawn_window(spawn)
      mux.set_active_workspace(spawn.workspace)
   end)
end

return M
