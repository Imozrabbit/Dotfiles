-----------------------------------------------------------------------
-- Make sure games appear on workspace 7
-----------------------------------------------------------------------
local GAME_WORKSPACE = 7

hl.window_rule({
	name = "Make games launched with gamescope opaque and appear on the workspace 7",
	match = {
		initial_class = "gamescope",
		class = "gamescope",
	},
	content = "game",
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
	--immediate = true, -- Force window to allow tearing for competitive games
	--confine_pointer = true, -- Confine cursur in the game window frame
})

hl.window_rule({
	name = "Force steam games to be opaque and to appear on workspace 7",
	match = {
		class = "^(steam_app_.*|valheim[.]x86_64)$",
	},
	content = "game",
	workspace = GAME_WORKSPACE,
	opaque = true,
	no_blur = true,
	xray = false,
	no_shadow = true,
})

-----------------------------------------------------------------------
-- Make sure workspace 7 is only for games and in-game utility programs
-----------------------------------------------------------------------
local EJECT_WORKSPACE = 1
local ALLOWED_CLASSES = {
	["awakened-poe-trade"] = true,
}

local function is_allowed_on_game_workspace(window)
	if window.content_type == "game" then
		return true
	end
	if ALLOWED_CLASSES[window.class] == true then
		return true
	end
	-- Allow Steam notification toasts, but now normal Steam windows
	local is_steam_notification = window.class == "steam"
		and window.title ~= nil
		and window.title:match("^notificationtoasts_.*_desktop$") ~= nil
	return is_steam_notification
end

local function enforce_game_workspace(window, workspace)
	if window == nil or workspace == nil then
		return
	end
	if workspace.id ~= GAME_WORKSPACE then
		return
	end
	if is_allowed_on_game_workspace(window) then
		return
	end
	-- Defer the move until the current window event has completed
	hl.timer(function()
		hl.dispatch(hl.dsp.window.move({
			window = window,
			workspace = EJECT_WORKSPACE,
			follow = true,
		}))
	end, {
		timeout = 1,
		type = "oneshot",
	})
end

-- Catches programs launched while the game workspace is active
hl.on("window.open", function(window)
	enforce_game_workspace(window, window.workspace)
end)

-- Catches windows manually moved into the game workspace
hl.on("window.move_to_workspace", function(window, workspace)
	enforce_game_workspace(window, workspace)
end)
