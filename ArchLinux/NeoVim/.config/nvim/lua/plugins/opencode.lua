return {
	"NickvanDyke/opencode.nvim",
	version = "*",
	dependencies = {},
	config = function()
		---@type opencode.Opts
		vim.g.opencode_opts = {
			-- port = ,
		}

		-- Required for `opts.events.reload`.
		vim.o.autoread = true
	end,
}
