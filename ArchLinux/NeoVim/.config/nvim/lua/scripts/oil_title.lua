local M = {}
function M.setup(winid)
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local dir = require("oil").get_current_dir(bufnr)
	if not dir then
		return "Files"
	end
	dir = dir:gsub("[/\\]+$", "")
	local parts = {}
	for part in dir:gmatch("[^/\\]+") do
		parts[#parts + 1] = part
	end
	if #parts == 0 then
		return "/"
	end
	local first = math.max(1, #parts - 2)
	local title = table.concat(parts, "/", first) .. "/"
	return first > 1 and ".../" .. title or title
end
return M
