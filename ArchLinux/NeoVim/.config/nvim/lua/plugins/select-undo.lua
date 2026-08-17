return {
	"SunnyTamang/select-undo.nvim",
	opts = {},
	config = function()
		require("select-undo").setup({
			mapping = false, -- Disables default keybindings and bind the commands myself
		})
	end,
}
