-- Ensure Awakened PoE Trade keybinds only work in POE1
local POE_CLASS = "steam_app_238960"
local APT_CLASS = "awakened-poe-trade"

local function pass_to_apt_in_poe()
	local window = hl.get_active_window()
	if window ~= nil and window.class == POE_CLASS then
		hl.dispatch(hl.dsp.pass({
			window = "class:^(" .. APT_CLASS .. ")$",
		}))
	end
end
hl.bind("SHIFT + Space", pass_to_apt_in_poe, {
	non_consuming = true,
})
hl.bind("CTRL + D", pass_to_apt_in_poe, {
	non_consuming = true,
})
hl.bind("CTRL + ALT + D", pass_to_apt_in_poe, {
	non_consuming = true,
})
hl.bind("F4", pass_to_apt_in_poe, {
	non_consuming = true,
})

-- LOGOUT MACRO: TCP disconnect
local function hard_logout_poe()
	local window = hl.get_active_window()
	if window == nil then
		return
	end
	local is_poe_context = window.class == POE_CLASS or window.class == APT_CLASS
	if is_poe_context then
		hl.dispatch(hl.dsp.exec_cmd("sudo -n /usr/local/bin/poe-hard-logout"))
	end
	-- In non gaming situation, this mouse key work as drag function
	if window.content_type ~= "game" then
		hl.dispatch(hl.dsp.window.drag())
	end
end
hl.bind("mouse:276", hard_logout_poe, {
	mouse = true,
	dont_inhibit = true,
	description = "TCP disconnect PoE session = Hardcore logout macro",
})

-- Set up Awakened PoE Trade window
hl.window_rule({
	name = "make Awakened PoE Trade actually visible in game",
	match = { class = "awakened-poe-trade" },
	content = "game",
	float = true,
	no_blur = true,
	no_shadow = true,
	opaque = true,
	border_size = 0,
})

-- Set up POB
hl.window_rule({
	name = "make POB 1 and 2 opaque",
	match = {
		class = "rusty-path-of-building-[12]",
	},
	no_blur = true,
	opaque = true,
})
