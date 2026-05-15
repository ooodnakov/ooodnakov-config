-- NeoCodeium: free AI completion powered by Windsurf (Codeium)
-- Integration with blink.cmp
return {
  "monkoose/neocodeium",
  event = "VeryLazy",
  opts = {
    -- Auto-suggestions (not manual mode)
    manual = false,
    show_label = true,
    debounce = false,
    max_lines = 10000,
    silent = false,
    disable_in_special_buftypes = true,
    -- Disable in filetypes where AI completion is noise
    filetypes = {
      help = false,
      gitcommit = false,
      gitrebase = false,
      TelescopePrompt = false,
      ["dap-repl"] = false,
      ["."] = false,
    },
  },
  config = function(_, opts)
    local neocodeium = require("neocodeium")
    neocodeium.setup(opts)

    local ok, blink = pcall(require, "blink.cmp")
    if ok then
      -- Clear neocodeium suggestions when blink.cmp menu opens
      vim.api.nvim_create_autocmd("User", {
        pattern = "BlinkCmpMenuOpen",
        callback = function()
          neocodeium.clear()
        end,
      })

      -- Don't show neocodeium suggestions when blink menu is visible
      neocodeium.setup({
        filter = function()
          return not blink.is_visible()
        end,
      })
    end

    -- Keymaps for accepting/cycling suggestions
    vim.keymap.set("i", "<M-f>", function()
      if ok and blink.is_visible() then
        -- Let blink handle it
      else
        neocodeium.cycle(1)
      end
    end, { desc = "NeoCodeium: cycle suggestions" })

    vim.keymap.set("i", "<M-s>", neocodeium.accept, { desc = "NeoCodeium: accept suggestion" })
    vim.keymap.set("i", "<C-g>", neocodeium.accept_word, { desc = "NeoCodeium: accept word" })
    vim.keymap.set("i", "<C-l>", neocodeium.clear, { desc = "NeoCodeium: clear suggestion" })
  end,
}
