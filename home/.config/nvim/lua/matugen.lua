 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#000000',
    base01 = '#191615',
    base02 = '#231f1e',
    base03 = '#76706c',
    base04 = '#ebdbb2',
    base05 = '#fbf1c7',
    base06 = '#fbf1c7',
    base07 = '#fbf1c7',
    base08 = '#fb4934',
    base09 = '#83a598',
    base0A = '#fabd2f',
    base0B = '#b8bb26',
    base0C = '#96e9c9',
    base0D = '#e8e995',
    base0E = '#fcd782',
    base0F = '#fde7b4',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  hi('TelescopeNormal',         { fg = '#fbf1c7',          bg = '#000000' })
  hi('TelescopeBorder',         { fg = '#76706c',             bg = '#000000' })
  hi('TelescopePromptNormal',   { fg = '#fbf1c7',          bg = '#000000' })
  hi('TelescopePromptBorder',   { fg = '#76706c',             bg = '#000000' })
  hi('TelescopePromptPrefix',   { fg = '#b8bb26',             bg = '#000000' })
  hi('TelescopePromptCounter',  { fg = '#ebdbb2',  bg = '#000000' })
  hi('TelescopePromptTitle',    { fg = '#000000',             bg = '#b8bb26' })
  hi('TelescopePreviewTitle',   { fg = '#000000',             bg = '#fabd2f' })
  hi('TelescopeResultsTitle',   { fg = '#000000',             bg = '#83a598' })
  hi('TelescopeSelection',      { fg = '#fbf1c7',          bg = '#231f1e' })
  hi('TelescopeSelectionCaret', { fg = '#b8bb26',             bg = '#231f1e' })
  hi('TelescopeMatching',       { fg = '#b8bb26',             bold = true })
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
