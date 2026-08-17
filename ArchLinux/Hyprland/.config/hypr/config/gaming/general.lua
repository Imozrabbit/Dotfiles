hl.config({
	general = {
		allow_tearing = true,
	},
	render = {
		direct_scanout = 2,
		cm_auto_hdr = 1,
		cm_sdr_eotf = "gamma22",
	},
	quirks = {
		prefer_hdr = 2,
	},
})
