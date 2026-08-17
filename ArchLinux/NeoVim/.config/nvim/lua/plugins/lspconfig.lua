return {
	"neovim/nvim-lspconfig",
	dependencies = { "saghen/blink.cmp" },

	-- Add lsp servers here
	opts = {
		servers = {
			neocmake = {},
			qmlls = {
				cmd = { "qmlls", "-E" },
				on_init = function(client)
					client.server_capabilities.semanticTokensProvider = nil
				end,
			},
			cssls = {},
			lua_ls = {},
			arduino_language_server = {
				cmd = {
					"arduino-language-server",
					"-cli-config",
					vim.fn.expand("$HOME/.config/arduino/arduino-cli.yaml"),
				},
			},
			jsonls = {},
			bashls = {},
			hyprls = {},
			clangd = {},
			verible = {
				cmd = {
					"verible-verilog-ls",
					"--rules_config_search",
					"--lsp_enable_hover",
				},
			},
		},
	},
	-- Merge blink's capabilities with lsp's
	config = function(_, opts)
		for server, config in pairs(opts.servers) do
			config.capabilities = require("blink.cmp").get_lsp_capabilities(config.capabilities)
			vim.lsp.config(server, config)
		end
	end,
}
