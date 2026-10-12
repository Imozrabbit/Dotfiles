hl.window_rule({
	name = "make the jagex launcher opaque",
	match = {
		class = "jagex-launcher",
		title = [[Jagex Launcher \(Beta\)]],
	},
	workspace = "special:steam",
	opaque = true,
	no_blur = true,
	xray = true,
})

hl.window_rule({
	name = "make the runelite launcher float and opaque",
	match = {
		class = "net-runelite-launcher-Launcher",
		title = "RuneLite Launcher Configuration",
	},
	float = true,
	opaque = true,
	no_blur = true,
	xray = true,
})
