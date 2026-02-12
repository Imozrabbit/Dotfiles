return {
	"neovim/nvim-lspconfig",
	dependencies = { "saghen/blink.cmp" },

	-- Add lsp servers here
	opts = {
		servers = {
			qmlls = {},
			cssls = {},
			lua_ls = {},
			arduino_language_server = {},
			jsonls = {},
			bashls = {},
			hyprls = {},
			clangd = {},
			shellcheck = {},
			stylua = {},
			["clang-format"] = {},
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
