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
})

hl.window_rule({
	name = "make WOW mod manager window float and opaque",
	match = {
		class = "WowUpCf",
		title = "WowUp.io",
	},
	float = true,
	persistent_size = true,
	opaque = true,
	xray = false,
})
