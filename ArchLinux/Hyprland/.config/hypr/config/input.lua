hl.config({
	input = {
		kb_layout = "us_qwerty-fr",
		numlock_by_default = true,
		follow_mouse = 1,
		-- -1.0 -> 1.0, 0 means no modification.
		sensitivity = 0,
		-- Focus will shift to the window under the cursor when a window is closed
		focus_on_close = 1,
		touchpad = {
			tap_and_drag = false,
			natural_scroll = true,
			scroll_factor = 0.4,
		},
	},
	gestures = {
		workspace_swipe_touch = true,
		workspace_swipe_create_new = true,
	},
})

hl.device({
	tags = "thinkpad-touchpad",
	name = TOUCHPAD,
	enabled = true,
})

hl.device({
	tags = "thinkpad-touchscreen",
	name = TOUCHSCREEN,
	enabled = true,
})

hl.device({
	tags = "thinkpad-trackpoint",
	name = TRACKPOINT,
	enabled = true,
})
