return {
	{
		"mfussenegger/nvim-lint",
		opts = {
			linters = {
				["markdownlint-cli2"] = {
					prepend_args = {
						"--config",
						-- nvim-lint passes args straight to the binary (no shell),
						-- so `~` must be expanded here. The trailing `--` used to
						-- follow the path made the linter treat `-` (stdin) as a
						-- literal filename, silently linting nothing.
						vim.fs.joinpath(vim.fn.stdpath("config"), "lua", "config", ".markdownlin.json"),
					},
				},
			},
		},
	},
}
