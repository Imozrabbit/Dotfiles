hl.window_rule({
	name = "make battle.net opaque and appear on its own special workspace",
	match = {
		class = "^steam_app_default$",
		title = "^Battle\\.net( Login)?$",
	},
	opaque = true,
	no_blur = true,
	xray = false,
	workspace = "special:battlenet",
	border_color = "rgba(00000000)", -- Transparent
	border_size = 0,
	animation = "none",
})
