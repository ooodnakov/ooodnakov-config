local theme_map = {
  default = "catppuccin-mocha",
  catppuccin = "catppuccin-mocha",
  gruvbox = "gruvbox",
  nord = "nord",
  tokyonight = "tokyonight-night",
  noctalia = "catppuccin-mocha",
}

local selected_theme = (vim.env.OOOCONF_THEME or "default"):lower()
local selected_colorscheme = theme_map[selected_theme] or theme_map.default

return {
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
  { "ellisonleao/gruvbox.nvim", name = "gruvbox", priority = 1000 },
  { "shaunsingh/nord.nvim", name = "nord", priority = 1000 },
  { "folke/tokyonight.nvim", name = "tokyonight", priority = 1000 },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = selected_colorscheme,
    },
  },
}
