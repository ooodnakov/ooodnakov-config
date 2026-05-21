-- csvview.nvim: CSV/TSV file viewer
return {
	"hat0uma/csvview.nvim",
	---@module "csvview"
	---@type CsvView.Options
	ft = { "csv", "tsv" }, -- 1. Load the plugin automatically for these filetypes
	opts = {
		display_mode = "border",
		parser = { comments = { "#", "//" } },
		keymaps = {
			-- Text objects for selecting fields
			textobject_field_inner = { "if", mode = { "o", "x" } },
			textobject_field_outer = { "af", mode = { "o", "x" } },
			-- Excel-like navigation:
			jump_next_field_end = { "<Tab>", mode = { "n", "v" } },
			jump_prev_field_end = { "<S-Tab>", mode = { "n", "v" } },
			jump_next_row = { "<Enter>", mode = { "n", "v" } },
			jump_prev_row = { "<S-Enter>", mode = { "n", "v" } },
		},
	},
	config = function(_, opts)
		-- 2. Run the normal setup with your choices
		require("csvview").setup(opts)

		-- 3. Automatically turn on the columnar view when a CSV/TSV file is loaded
		vim.api.nvim_create_autocmd("FileType", {
			pattern = { "csv", "tsv" },
			desc = "Auto-enable csvview",
			callback = function()
				require("csvview").enable()
			end,
		})
	end,
}
