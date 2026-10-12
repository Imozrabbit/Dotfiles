hl.window_rule({
	name = "Force OSRS/RuneLite to be opaque and to appear on workspace 7",
	match = {
		class = "net-runelite-launcher-Launcher",
		title = "RuneLite - Zhabbit",
	},
	content = "game",
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
})
