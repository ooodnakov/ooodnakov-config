-- lua/plugins/python-lsp.lua
return {
  {
    "mason-org/mason.nvim",
    opts = {},
  },

  {
    "mason-org/mason-lspconfig.nvim",
    opts = {
      ensure_installed = {
        "pyright",
        "ruff",
      },
    },
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        pyright = {
          settings = {
            python = {
              analysis = {
                useLibraryCodeForTypes = true,
                typeCheckingMode = "off",
                diagnosticMode = "off",
                diagnosticSeverityOverrides = {
                  reportUnusedVariable = "warning",
                },
              },
            },
          },
          on_attach = function(client, _)
            client.server_capabilities.hoverProvider = true
          end,
        },

        ruff = {
          init_options = {
            settings = {
              -- `settings.args` is not a ruff option; the old `--ignore`
              -- flags were silently dropped and F821 et al. still fired.
              lint = {
                ignore = { "F821", "E402", "E722", "E712" },
              },
            },
          },
          on_attach = function(client, _)
            client.server_capabilities.hoverProvider = false
          end,
        },
      },
    },
  },
}
