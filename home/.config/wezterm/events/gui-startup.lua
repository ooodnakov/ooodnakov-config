local wezterm = require('wezterm')
local mux = wezterm.mux
local launch = require('config.launch')

local M = {}
local get_env = wezterm.getenv or os.getenv

M.setup = function()
   wezterm.on('gui-startup', function(cmd)
      local spawn = cmd or {}
      local workspace = get_env('OOODNAKOV_WEZTERM_WORKSPACE') or 'default'
      local startup_cwd = get_env('OOODNAKOV_WEZTERM_CWD')

      if spawn.workspace == nil then
         spawn.workspace = workspace
      end

      if startup_cwd and spawn.cwd == nil then
         spawn.cwd = startup_cwd
      end

      if spawn.args == nil and launch.default_prog and #launch.default_prog > 0 then
         spawn.args = launch.default_prog
      end

      mux.spawn_window(spawn)
      mux.set_active_workspace(spawn.workspace)
   end)
end

return M
