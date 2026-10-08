 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#000000',
    base01 = '#232120',
    base02 = '#2d2b2a',
    base03 = '#69625d',
    base04 = '#d5c4a1',
    base05 = '#ebdbb2',
    base06 = '#ebdbb2',
    base07 = '#ebdbb2',
    base08 = '#fb4934',
    base09 = '#83a598',
    base0A = '#b8bb26',
    base0B = '#fe8019',
    base0C = '#96e9c9',
    base0D = '#feb980',
    base0E = '#e8e995',
    base0F = '#f2f4be',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- telescope.nvim
  hi('TelescopeNormal',         { fg = '#ebdbb2',          bg = '#000000' })
  hi('TelescopeBorder',         { fg = '#69625d',             bg = '#000000' })
  hi('TelescopePromptNormal',   { fg = '#ebdbb2',          bg = '#000000' })
  hi('TelescopePromptBorder',   { fg = '#69625d',             bg = '#000000' })
  hi('TelescopePromptPrefix',   { fg = '#fe8019',             bg = '#000000' })
  hi('TelescopePromptCounter',  { fg = '#d5c4a1',  bg = '#000000' })
  hi('TelescopePromptTitle',    { fg = '#000000',             bg = '#fe8019' })
  hi('TelescopePreviewTitle',   { fg = '#000000',             bg = '#b8bb26' })
  hi('TelescopeResultsTitle',   { fg = '#000000',             bg = '#83a598' })
  hi('TelescopeSelection',      { fg = '#ebdbb2',          bg = '#2d2b2a' })
  hi('TelescopeSelectionCaret', { fg = '#fe8019',             bg = '#2d2b2a' })
  hi('TelescopeMatching',       { fg = '#fe8019',             bold = true })

  -- mini.pick
  hi('MiniPickNormal',         { fg = '#ebdbb2',          bg = '#000000' })
  hi('MiniPickBorder',         { fg = '#69625d',             bg = '#000000' })
  hi('MiniPickPrompt',   { fg = '#ebdbb2',          bg = '#000000' })
  hi('MiniPickPromptPrefix',   { fg = '#fe8019',             bg = '#000000' })
  hi('MiniPickBorderText',    { fg = '#000000',             bg = '#fe8019' })
  hi('MiniPickMatchCurrent',      { fg = '#ebdbb2',          bg = '#2d2b2a' })
  hi('MiniPickPromptCaret', { fg = '#fe8019',             bg = '#2d2b2a' })
  hi('MiniPickMatchRanges',       { fg = '#fe8019',             bold = true })
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
