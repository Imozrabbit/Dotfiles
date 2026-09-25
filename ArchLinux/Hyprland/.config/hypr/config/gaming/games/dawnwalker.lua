-- The blood of dawnwalker
hl.window_rule({
	name = "The blood of dawnwalker follow the general gaming window rule",
	match = {
		class = "steam_app_3751260",
		title = "Dawnwalker",
	},
	content = "game",
	confine_pointer = true,
	fullscreen = true,
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
})
