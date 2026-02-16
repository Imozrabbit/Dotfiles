return {
	"neovim/nvim-lspconfig",
	dependencies = { "saghen/blink.cmp" },

	-- Add lsp servers here
	opts = {
		servers = {
			qmlls = {},
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
