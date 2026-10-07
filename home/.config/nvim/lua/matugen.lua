 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#000000',
    base01 = '#090925',
    base02 = '#111136',
    base03 = '#51589b',
    base04 = '#7c80b4',
    base05 = '#f3edf7',
    base06 = '#f3edf7',
    base07 = '#f3edf7',
    base08 = '#fd4663',
    base09 = '#9bfece',
    base0A = '#a9aefe',
    base0B = '#fff59b',
    base0C = '#81fec1',
    base0D = '#fff280',
    base0E = '#8188fe',
    base0F = '#b3b8fe',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- telescope.nvim
  hi('TelescopeNormal',         { fg = '#f3edf7',          bg = '#000000' })
  hi('TelescopeBorder',         { fg = '#51589b',             bg = '#000000' })
  hi('TelescopePromptNormal',   { fg = '#f3edf7',          bg = '#000000' })
  hi('TelescopePromptBorder',   { fg = '#51589b',             bg = '#000000' })
  hi('TelescopePromptPrefix',   { fg = '#fff59b',             bg = '#000000' })
  hi('TelescopePromptCounter',  { fg = '#7c80b4',  bg = '#000000' })
  hi('TelescopePromptTitle',    { fg = '#000000',             bg = '#fff59b' })
  hi('TelescopePreviewTitle',   { fg = '#000000',             bg = '#a9aefe' })
  hi('TelescopeResultsTitle',   { fg = '#000000',             bg = '#9bfece' })
  hi('TelescopeSelection',      { fg = '#f3edf7',          bg = '#111136' })
  hi('TelescopeSelectionCaret', { fg = '#fff59b',             bg = '#111136' })
  hi('TelescopeMatching',       { fg = '#fff59b',             bold = true })

  -- mini.pick
  hi('MiniPickNormal',         { fg = '#f3edf7',          bg = '#000000' })
  hi('MiniPickBorder',         { fg = '#51589b',             bg = '#000000' })
  hi('MiniPickPrompt',   { fg = '#f3edf7',          bg = '#000000' })
  hi('MiniPickPromptPrefix',   { fg = '#fff59b',             bg = '#000000' })
  hi('MiniPickBorderText',    { fg = '#000000',             bg = '#fff59b' })
  hi('MiniPickMatchCurrent',      { fg = '#f3edf7',          bg = '#111136' })
  hi('MiniPickPromptCaret', { fg = '#fff59b',             bg = '#111136' })
  hi('MiniPickMatchRanges',       { fg = '#fff59b',             bold = true })
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
