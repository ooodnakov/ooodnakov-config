return {
	"mrjones2014/smart-splits.nvim",
	lazy = false,
	dependencies = {
		{
			"smart-splits-nvim/backend-wezterm",
			main = "smart-splits-backend-wezterm",
			opts = { cli_path = "wezterm" },
		},
	},
	opts = {
		ignored_filetypes = { "nofile", "quickfix", "qf", "lazy", "mason" },
		-- v3 moved multiplexer support out of core. The backend's detect()
		-- stays false outside WezTerm, so Neovim-internal movement still works
		-- everywhere (and in Ghostty, which has no smart-splits backend).
		mux = {
			backend = "smart-splits-backend-wezterm",
			-- Ghostty has no backend; don't warn on every startup there.
			-- :checkhealth smart-splits still reports the skipped backend.
			warn_if_unusable = false,
		},
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
