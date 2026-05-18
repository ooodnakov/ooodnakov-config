return {
	"neovim/nvim-lspconfig",
	opts = {
		servers = {
			-- Example: Disable specific Lua diagnostics
			markdownlint = {
				settings = {
					Lua = {
						diagnostics = {
							disable = { "missing-", "undefined-global" },
						},
					},
				},
			},
		},
	},
}
