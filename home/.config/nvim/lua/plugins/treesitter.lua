return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if vim.fn.executable("zig") == 1 then
        require("nvim-treesitter.install").compilers = { "zig" }
      end
      return opts
    end,
  },
}
