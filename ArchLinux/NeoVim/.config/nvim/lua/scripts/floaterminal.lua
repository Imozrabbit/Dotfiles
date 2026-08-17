local state = {
	floating = {
		buf = -1,
		win = -1,
	},
}

----------------------------------------------------------
------------------------- WINDOW -------------------------
----------------------------------------------------------
local function create_floating_window(opts)
	opts = opts or {}
	local ratio = 0.8
	local width = opts.width or math.floor(vim.o.columns * ratio)
	local height = opts.height or math.floor(vim.o.lines * ratio)

	-- Calculate the position to center the window
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	-- Create a buffer
	local buf = nil
	if vim.api.nvim_buf_is_valid(opts.buf) then
		buf = opts.buf
	else
		buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer
	end

	-- Define window config
	local win_config = {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		border = "rounded",
		style = "minimal",
	}

	-- Create the floating window
	local win = vim.api.nvim_open_win(buf, true, win_config)

	return { buf = buf, win = win }
end

local function start_terminal(buf)
	vim.api.nvim_buf_call(buf, function()
		local job_id = vim.fn.jobstart({ vim.o.shell }, {
			term = true,
		})

		if job_id <= 0 then
			error("Failed to start terminal")
		end
	end)
end

----------------------------------------------------------
------------------------- TOGGLE -------------------------
----------------------------------------------------------
local function toggle_terminal()
	if not vim.api.nvim_win_is_valid(state.floating.win) then
		state.floating = create_floating_window({
			buf = state.floating.buf,
		})

		if vim.bo[state.floating.buf].buftype ~= "terminal" then
			start_terminal(state.floating.buf)
		end

		vim.cmd.startinsert()
	else
		vim.api.nvim_win_hide(state.floating.win)
	end
end

----------------------------------------------------------
-------------------------- MAIN --------------------------
----------------------------------------------------------
-- Create a togglable floating window with default dimensions
vim.api.nvim_create_user_command("Floaterminal", toggle_terminal, {})
vim.keymap.set({ "n", "t" }, "gt", toggle_terminal, { desc = "Toggle floating terminal" })
