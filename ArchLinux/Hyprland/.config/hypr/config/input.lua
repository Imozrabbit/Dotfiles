hl.config({
	input = {
		kb_layout = "us_qwerty-fr",
		numlock_by_default = true,
		follow_mouse = 1,
		-- -1.0 -> 1.0, 0 means no modification.
		sensitivity = -1.0,
		-- Focus will shift to the window under the cursor when a window is closed
		focus_on_close = 1,
	},
})

hl.device({
	name = "wl-wlmouse-beastx-1k-receiver",
	sensitivity = -0.3,
})
