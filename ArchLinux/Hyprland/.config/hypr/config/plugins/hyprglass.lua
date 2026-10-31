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
		layers = {
			enabled = true,
			live_resample_fps = 60,
			force_live_resample = true,
		},
	})

	-----------------------------------------------------------------------------
	-- Layer surfaces: each call whitelists the namespace and configures it
	-----------------------------------------------------------------------------
	local layer_minor = {
		"rofi",
		"quickshell-calendar",
		"swaync-notification-window",
		"level-osd",
	}

	local layer_master = {
		"calendar-menu",
		"swaync-control-center",
		"battery-menu",
		"bluetooth-menu",
		"wifi-menu",
		"proton-manager",
	}

	local layer_disable = {
		"quickshell-bottom-bar",
		"quickshell-top-media",
		"quickshell-wallpaper-preview",
		"quickshell:expose",
		"wallpaper-switcher-contour",
		"quickshell-lock-preview",
		"selection",
	}

	for _, namespace in ipairs(layer_minor) do
		hg.layer(namespace, {
			preset = "minor",
			mask_threshold = 0.05,
			mask_feather = 0.45,
		})
	end

	for _, namespace in ipairs(layer_master) do
		hg.layer(namespace, {
			preset = "master-pick-glass",
			mask_threshold = 0.05,
			mask_feather = 0.45,
		})
	end

	for _, namespace in ipairs(layer_disable) do
		hg.layer(namespace, {
			exclude = true,
		})
	end

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
		blur_strength = 1.3,
		edge_thickness = 0.01,
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
