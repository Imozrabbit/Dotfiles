local M = {}

function M.setup()
	local group = vim.api.nvim_create_augroup("OilConfirmationPosition", {
		clear = true,
	})

	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "oil_preview",

		callback = function(event)
			local win = vim.fn.bufwinid(event.buf)

			if win == -1 then
				return
			end

			local config = vim.api.nvim_win_get_config(win)

			if config.zindex == 152 then
				config.row = 6
				vim.api.nvim_win_set_config(win, config)
			end
		end,
	})
end

return M
