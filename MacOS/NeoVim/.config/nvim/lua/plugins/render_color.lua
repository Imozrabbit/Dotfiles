return {
	"norcalli/nvim-colorizer.lua",
	config = function()
		require("colorizer").setup({
			"*",
			hyprlang = { css = true },
			lua = { css = true },
			jsonc = { css = true },
			css = { css = true },
			html = { css = true },
		})
	end,
}
