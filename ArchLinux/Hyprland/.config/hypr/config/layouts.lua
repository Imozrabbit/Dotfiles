---------------------------------------------
---             Master Layout             ---
---------------------------------------------
hl.config({
	master = {
		allow_small_split = true,
		new_status = "slave",
		-- Master window size
		mfact = 0.7,
	},
})

---------------------------------------------
---             dwindle Layout            ---
---------------------------------------------
hl.config({
	dwindle = {
		-- Force split to right
		force_split = 2,
		-- You probably want this
		preserve_split = true,
		-- Determine split ratio for windows
		default_split_ratio = 1.2,
	},
})

---------------------------------------------
---            Scrolling Layout           ---
---------------------------------------------
hl.config({
	scrolling = {
		fullscreen_on_one_column = true,
		focus_fit_method = 1,
		follow_focus = true,
		direction = "right",
		column_width = 0.5,
		follow_min_visible = 0.4,
		explicit_column_widths = "0.4,0.5,0.7,1.0",
	},
})
