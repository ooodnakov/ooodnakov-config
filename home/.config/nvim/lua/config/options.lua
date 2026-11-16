vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.api.nvim_set_hl(0, "FloatBorder", { link = "DiagnosticInfo" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "#1e1e2e" }) -- change if needed
vim.opt.clipboard = "unnamedplus"

-- No Neovim::Ext cpan module or usable perl here; silence the provider warning.
vim.g.loaded_perl_provider = 0
