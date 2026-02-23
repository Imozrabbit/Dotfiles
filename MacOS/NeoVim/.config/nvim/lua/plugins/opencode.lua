return {
	"NickvanDyke/opencode.nvim",
	dependencies = {},
	config = function()
		--@type opencode.Opts
		vim.g.opencode_opts = {
			provider = {
				enabled = "tmux",
				terminal = {},
			},
		}

		-- Required for `opts.events.reload`.
		vim.o.autoread = true
	end,
}
