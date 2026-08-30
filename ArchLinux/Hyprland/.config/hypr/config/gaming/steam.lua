hl.window_rule({
	name = "make steam popup windows float",
	match = {
		class = "steam",
		title = "^(Friends List|Steam Settings|Path of Exile|Path of Exile 2|Valheim|Gothic 1 Remake|Abiotic Factor|Project Zomboid|Stoneshard)$",
	},
	float = true,
	persistent_size = true,
	xray = false,
})

hl.window_rule({
	name = "make steam opaque and appear on its own special workspace",
	match = {
		class = "steam",
		title = "^(Sign in to Steam|Steam)$",
	},
	opaque = true,
	no_blur = true,
	xray = false,
	workspace = "special:steam",
	border_color = "rgba(00000000)", -- Transparent
	border_size = 0,
	animation = "none",
})

hl.window_rule({
	name = "make steam Big Picture Mode opaque and appear on its own special workspace",
	match = {
		class = "gamescope",
		title = "Steam Big Picture Mode",
	},
	opaque = true,
	no_blur = true,
	xray = false,
	workspace = "special:steam",
	border_color = "rgba(00000000)", -- Transparent
	border_size = 0,
	animation = "none",
})
