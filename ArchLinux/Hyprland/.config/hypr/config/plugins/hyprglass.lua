if hl.plugin.hyprglass then
	local hg = hl.plugin.hyprglass

	-----------------------------------------------------------------------------
	-- Global configuration
	-----------------------------------------------------------------------------
	hg.config({
		enabled = false,
		default_theme = "dark",
		default_preset = "liquid-glass-minus",
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
	local layer_minus = {
		"rofi",
		"level-osd",
		"swaync-notification-window",
		"quickshell-top-media",
		"quickshell-calendar",
	}

	local layer_default = {
		"quickshell-command-center",
	}

	local layer_plus = {
		"wifi-menu",
		"battery-menu",
		"calendar-menu",
		"bluetooth-menu",
		"proton-manager",
		"quickshell-bottom-bar",
		"swaync-control-center",
		"quickshell-bar-tooltip",
	}

	local layer_disable = {
		"selection",
		"quickshell:expose",
		"quickshell-lock-preview",
		"wallpaper-switcher-contour",
		"quickshell-wallpaper-preview",
	}

	for _, namespace in ipairs(layer_minus) do
		hg.layer(namespace, {
			preset = "liquid-glass-minus",
			mask_threshold = 0.05,
			mask_feather = 0.45,
		})
	end

	for _, namespace in ipairs(layer_default) do
		hg.layer(namespace, {
			preset = "liquid-glass",
			mask_threshold = 0.05,
			mask_feather = 0.45,
		})
	end

	for _, namespace in ipairs(layer_plus) do
		hg.layer(namespace, {
			preset = "liquid-glass-plus",
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
	hg.preset("liquid-glass-minus", {
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

	hg.preset("liquid-glass", {
		inherits = "liquid-glass-minus",
		blur_strength = 1.4,
		edge_thickness = 0.01,
		refraction_strength = 6,
		chromatic_aberration = 0.45,
		lens_distortion = 0.45,
		fresnel_strength = 0.85,
		dark = {
			tint_color = 0x8C6AA808,
		},
	})

	hg.preset("liquid-glass-plus", {
		inherits = "liquid-glass-minus",
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
