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
      colorscheme = "catppuccin-mocha",
    },
  },
}
