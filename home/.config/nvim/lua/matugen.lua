 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#000000',
    base01 = '#161a22',
    base02 = '#1f242d',
    base03 = '#595f6a',
    base04 = '#8e959e',
    base05 = '#d1d1c7',
    base06 = '#d1d1c7',
    base07 = '#d1d1c7',
    base08 = '#d95757',
    base09 = '#39bae6',
    base0A = '#aad94c',
    base0B = '#e6b450',
    base0C = '#8ed8f1',
    base0D = '#efcf8f',
    base0E = '#cde996',
    base0F = '#e2f4be',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  hi('TelescopeNormal',         { fg = '#d1d1c7',          bg = '#000000' })
  hi('TelescopeBorder',         { fg = '#595f6a',             bg = '#000000' })
  hi('TelescopePromptNormal',   { fg = '#d1d1c7',          bg = '#000000' })
  hi('TelescopePromptBorder',   { fg = '#595f6a',             bg = '#000000' })
  hi('TelescopePromptPrefix',   { fg = '#e6b450',             bg = '#000000' })
  hi('TelescopePromptCounter',  { fg = '#8e959e',  bg = '#000000' })
  hi('TelescopePromptTitle',    { fg = '#000000',             bg = '#e6b450' })
  hi('TelescopePreviewTitle',   { fg = '#000000',             bg = '#aad94c' })
  hi('TelescopeResultsTitle',   { fg = '#000000',             bg = '#39bae6' })
  hi('TelescopeSelection',      { fg = '#d1d1c7',          bg = '#1f242d' })
  hi('TelescopeSelectionCaret', { fg = '#e6b450',             bg = '#1f242d' })
  hi('TelescopeMatching',       { fg = '#e6b450',             bold = true })
end

-- Register a signal handler for SIGUSR1 (matugen updates).
-- The handler re-requires this module, which re-runs the code below, so the
-- previous handle is stopped first; otherwise handlers double on every signal.
if _G.__matugen_signal then
  _G.__matugen_signal:stop()
  _G.__matugen_signal:close()
end

local signal = vim.uv.new_signal()
_G.__matugen_signal = signal
signal:start(
  'sigusr1',
  vim.schedule_wrap(function()
    package.loaded['matugen'] = nil
    require('matugen').setup()
  end)
)

return M
