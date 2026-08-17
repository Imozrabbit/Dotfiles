local M = {}

function M.setup()
	local oil_win = vim.api.nvim_get_current_win()

	if not vim.w[oil_win].is_oil_win then
		return
	end

	local preview_win

	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local conf = vim.api.nvim_win_get_config(winid)

		if conf.title and (vim.w[winid].is_oil_win or vim.w[winid].oil_preview) then
			vim.api.nvim_win_set_config(winid, {
				title = conf.title,
				title_pos = "center",
			})
		end

		if vim.w[winid].oil_preview then
			preview_win = winid
		end
	end

	if not preview_win then
		return
	end

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(oil_win),
		once = true,
		desc = "Close Oil preview with Oil float",

		callback = function()
			vim.schedule(function()
				if vim.api.nvim_win_is_valid(preview_win) then
					vim.api.nvim_win_close(preview_win, true)
				end
			end)
		end,
	})
end

return M
