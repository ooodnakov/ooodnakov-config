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
              args = {
                "--ignore", "F821",
                "--ignore", "E402",
                "--ignore", "E722",
                "--ignore", "E712",
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