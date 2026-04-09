local platform = require('utils.platform')

local msys2_root = 'C:/msys64'
local msys2_shell = msys2_root .. '/msys2_shell.cmd'

local options = {
   default_prog = {},
   launch_menu = {},
}

if platform.is_win then
   options.default_prog = {'pwsh', '-NoLogo'}
   options.launch_menu = {
      {
         label = 'MSYS2 UCRT64 Zsh',
         args = { msys2_shell, '-defterm', '-here', '-no-start', '-ucrt64', '-shell', 'zsh' },
      },
      { label = 'PowerShell Core', args = { 'pwsh', '-NoLogo' } },
      { label = 'PowerShell Desktop', args = { 'powershell' } },
      { label = 'Command Prompt', args = { 'cmd' } },
      { label = 'Nushell', args = { 'nu' } },
   }
elseif platform.is_mac then
   options.default_prog = { 'zsh', '-l' }
   options.launch_menu = {
      { label = 'Zsh', args = { 'zsh', '-l' } },
      { label = 'Bash', args = { 'bash', '-l' } },
      { label = 'Fish', args = { 'fish', '-l' } },
   }
elseif platform.is_linux then
   options.default_prog = { 'zsh', '-l' }
   options.launch_menu = {
      { label = 'Zsh', args = { 'zsh', '-l' } },
      { label = 'Bash', args = { 'bash', '-l' } },
      { label = 'Fish', args = { 'fish', '-l' } },
   }
end

return options
