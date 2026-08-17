return {
	"catgoose/nvim-colorizer.lua",
	event = "BufReadPre",
	opts = {},
	config = function()
		require("colorizer").setup({
			filetypes = { "*" },
			lazy_load = true,
			options = {
				parsers = {
					names = {
						uppercase = true,
						strip_digits = true,
					},
					hex = {
						rrggbbaa = true,
						hash_aarrggbb = true,
					},
				},
				display = {},
			},
		})
	end,
}
