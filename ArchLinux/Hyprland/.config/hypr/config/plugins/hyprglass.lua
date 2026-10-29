if hl.plugin.hyprglass then
	local hg = hl.plugin.hyprglass

	-----------------------------------------------------------------------------
	-- Global configuration
	-----------------------------------------------------------------------------
	hg.config({
		enabled = false,
		default_theme = "dark",
		default_preset = "minor",
		manage_window_blur = true,
		layers = { enabled = false },
	})

	-----------------------------------------------------------------------------
	-- Layer surfaces: each call whitelists the namespace and configures it
	-----------------------------------------------------------------------------
	hg.layer("swaync-control-center", {
		preset = "master-pick-glass",
		mask_threshold = 0.05,
		mask_feather = 0.45,
	})

	hg.layer("rofi", {
		preset = "minor",
		mask_threshold = 0.05,
		mask_feather = 0.45,
	})

	hg.layer("system-osd", {
		preset = "minor",
		mask_threshold = 0.05,
		mask_feather = 0.45,
	})

	-----------------------------------------------------------------------------
	-- Presets
	-----------------------------------------------------------------------------
	hg.preset("minor", {
		blur_strength = 1.5,
		blur_iterations = 2,
		edge_thickness = 0.06,
		refraction_strength = 4.0,
		chromatic_aberration = 0.25,
		lens_distortion = 0.4,
		fresnel_strength = 0.7,
		specular_strength = 1.0,
		dark = {
			tint_color = 0x8C6AA818,
			brightness = 0.95,
			contrast = 1.10,
			saturation = 0.95,
			vibrancy = 0.40,
			adaptive_dim = 0.0,
		},
	})

	hg.preset("master-pick-glass", {
		inherits = "minor",
		blur_strength = 1.1,
		edge_thickness = 0.15,
		refraction_strength = 8.0,
		chromatic_aberration = 0.85,
		lens_distortion = 0.5,
		fresnel_strength = 1.0,
		glass_opacity = 0.95,
		dark = {
			tint_color = 0x8C6AA808,
		},
	})
end
