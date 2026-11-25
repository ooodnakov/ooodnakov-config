-- Taskwarrior has no native Windows build; without the `task` CLI the plugin
-- only emits startup errors and a failing :checkhealth taskwarrior section.
-- Load it only when the binary exists (Linux/macOS, or a task.cmd shim on
-- Windows). Run `:Lazy load taskwarrior.nvim` after installing task later.
local has_task = vim.fn.executable("task") == 1

return {
	"matthandzel/taskwarrior.nvim",
	enabled = has_task,
	config = function()
		require("taskwarrior").setup()
	end,
}
