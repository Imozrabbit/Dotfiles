-- Set up R2modman
hl.window_rule({
	name = "make gale mod manager window float and opaque",
	match = {
		class = "gale",
	},
	float = true,
	persistent_size = true,
	opaque = true,
	xray = false,
	workspace = "special:steam",
})

hl.window_rule({
	name = "make WOW mod manager window float and opaque",
	match = {
		class = "wowupcf",
		title = "WowUp.io",
	},
	float = true,
	persistent_size = true,
	opaque = true,
	xray = false,
	workspace = "special:battlenet",
})
