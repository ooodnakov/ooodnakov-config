return {
	"mrjones2014/smart-splits.nvim",
	lazy = false,
	opts = {
		ignored_filetypes = { "nofile", "quickfix", "qf", "lazy", "mason" },
		-- Links smart-splits directly to WezTerm multiplexer CLI
		multiplexer_integration = "wezterm",
	},
    keys = {
      -- move
      {
        "<M-h>",
        function()
          require("smart-splits").move_cursor_left()
        end,
        desc = "Move left",
      },
      {
        "<M-j>",
        function()
          require("smart-splits").move_cursor_down()
        end,
        desc = "Move down",
      },
      {
        "<M-k>",
        function()
          require("smart-splits").move_cursor_up()
        end,
        desc = "Move up",
      },
      {
        "<M-l>",
        function()
          require("smart-splits").move_cursor_right()
        end,
        desc = "Move right",
      },

      -- resize
      {
        "<C-M-h>",
        function()
          require("smart-splits").resize_left()
        end,
        desc = "Resize left",
      },
      {
        "<C-M-j>",
        function()
          require("smart-splits").resize_down()
        end,
        desc = "Resize down",
      },
      {
        "<C-M-k>",
        function()
          require("smart-splits").resize_up()
        end,
        desc = "Resize up",
      },
      {
        "<C-M-l>",
        function()
          require("smart-splits").resize_right()
        end,
        desc = "Resize right",
      },
    },
}
