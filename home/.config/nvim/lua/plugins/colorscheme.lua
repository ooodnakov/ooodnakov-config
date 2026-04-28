local theme_map = {
  default = "catppuccin-mocha",
  catppuccin = "catppuccin-mocha",
  gruvbox = "catppuccin-mocha",
  nord = "catppuccin-mocha",
  tokyonight = "tokyonight",
  noctalia = "catppuccin-mocha",
}

local selected_theme = (vim.env.OOOCONF_THEME or "default"):lower()
local selected_colorscheme = theme_map[selected_theme] or theme_map.default

return {
  -- 1. Install the colorscheme plugin
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
--   {
--     "catppuccin/nvim",
--     opts = {
--       transparent_background = true,
--       float = {
--         transparent = true,
--         solid = true,
--       },
--     },
--   },
  -- 2. Configure LazyVim to use it
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = selected_colorscheme,
    },
  },
}
