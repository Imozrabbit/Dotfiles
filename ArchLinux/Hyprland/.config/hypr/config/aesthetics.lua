hl.config({
	-----------------------------------------------------------------------
	-- General
	-----------------------------------------------------------------------
	general = {
		gaps_in = 7,
		gaps_out = 7,
		7,
		1,
		7,
		border_size = 1,
		float_gaps = -1,
		col = {
			active_border = "rgba(3b2f8699)",
			inactive_border = "rgba(070a1080)",
		},
		-- Set to true enable resizing windows by clicking and dragging on borders and gaps
		resize_on_border = true,
		-- Parent windows of modals will be blocked for interaction
		modal_parent_blocking = true,
		layout = "dwindle",
		-- Set up floating window snapping
		snap = {
			enabled = true,
			monitor_gap = 15,
			window_gap = 15,
			respect_gaps = true,
			border_overlap = true,
		},
	},

	-----------------------------------------------------------------------
	-- Decoration
	-----------------------------------------------------------------------
	decoration = {
		dim_special = 0.4,
		dim_around = 0.6,
		rounding = 9,
		rounding_power = 5,
		active_opacity = 0.9,
		inactive_opacity = 0.8,
		fullscreen_opacity = 0.9,
		shadow = {
			enabled = true,
			range = 33,
			render_power = 3,
			color = "rgba(00000050)",
		},
		blur = {
			enabled = true,
			size = 3,
			passes = 2,
			-- Weird setting, being on makes blurs better but somehow consumes a lot more GPU usage
			new_optimizations = true,
			xray = true,
			ignore_opacity = true,
			vibrancy = 0.1696,
			-- Whether to blur behind the special workspace (expensive)
			special = true,
		},
	},

	-----------------------------------------------------------------------
	-- Animations
	-----------------------------------------------------------------------
	animations = {
		enabled = true,
		workspace_wraparound = true,
	},
})

-----------------------------------------------------------------------
-- Curve
-----------------------------------------------------------------------
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("md3_standard", { type = "bezier", points = { { 0.2, 0 }, { 0, 1 } } })
hl.curve("md3_decel", { type = "bezier", points = { { 0.05, 0.7 }, { 0.1, 1 } } })
hl.curve("md3_accel", { type = "bezier", points = { { 0.3, 0 }, { 0.8, 0.15 } } })
hl.curve("overshot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.1 } } })
hl.curve("crazyshot", { type = "bezier", points = { { 0.1, 1.5 }, { 0.76, 0.92 } } })
hl.curve("hyprnostretch", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })
hl.curve("fluent_decel", { type = "bezier", points = { { 0.1, 1 }, { 0, 1 } } })
hl.curve("easeInOutCirc", { type = "bezier", points = { { 0.85, 0 }, { 0.15, 1 } } })
hl.curve("easeOutCirc", { type = "bezier", points = { { 0, 0.55 }, { 0.45, 1 } } })
hl.curve("easeOutExpo", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })

-----------------------------------------------------------------------
-- Animation Specific
-----------------------------------------------------------------------
hl.animation({
	leaf = "windows",
	enabled = true,
	speed = 3,
	bezier = "md3_decel",
	style = "popin 60%",
})

hl.animation({
	leaf = "border",
	enabled = true,
	speed = 10,
	bezier = "default",
})

hl.animation({
	leaf = "fade",
	enabled = true,
	speed = 3.5,
	bezier = "md3_decel",
})

hl.animation({
	leaf = "workspaces",
	enabled = true,
	speed = 3.5,
	bezier = "easeOutExpo",
	style = "slide",
})

hl.animation({
	leaf = "specialWorkspace",
	enabled = true,
	speed = 4,
	bezier = "md3_decel",
	style = "slidefadevert",
})
