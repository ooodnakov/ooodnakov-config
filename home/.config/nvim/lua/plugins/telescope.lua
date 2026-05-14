return {
  "nvim-telescope/telescope.nvim",
  opts = function(_, opts)
    -- 1. Modify vimgrep to find hidden files during live_grep
    if opts.defaults and opts.defaults.vimgrep_arguments then
      table.insert(opts.defaults.vimgrep_arguments, "--hidden")
    else
      opts.defaults = opts.defaults or {}
      opts.defaults.vimgrep_arguments = {
        "rg",
        "--color=never",
        "--no-heading",
        "--with-filename",
        "--line-number",
        "--column",
        "--smart-case",
        "--hidden",
      }
    end

    -- 2. Ignore the .git folder so it does not clutter search results
    opts.defaults.file_ignore_patterns = opts.defaults.file_ignore_patterns or {}
    table.insert(opts.defaults.file_ignore_patterns, ".git/")

    -- 3. Modify pickers to find hidden files during find_files
    opts.pickers = opts.pickers or {}
    opts.pickers.find_files = opts.pickers.find_files or {}
    opts.pickers.find_files.hidden = true

    return opts
  end,
}
