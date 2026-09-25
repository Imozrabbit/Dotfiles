-- Variables
require("config.variables")

-- Monitors
require("config.monitors")

-- Autostart
require("config.autostart")

-- Environment Variables
require("config.env_variables")

-- Permissions
require("config.permissions")

-- Look and feel
require("config.aesthetics")

-- Misc
require("config.misc")

-- Input
require("config.input")

-- Keybindings
require("config.binds")

-- Workspace rules
require("config.workspaceRules")

-- App-specific window rules
require("config.windowRules")

-- Layout rules
require("config.layoutRules")

-- Layout
require("config.layouts")

-- smart gap setup
require("config.smartGaps")

-- Gaming specific settings
require("config.gaming.general")
require("config.gaming.misc")
require("config.gaming.poe_related")
require("config.gaming.steam")
require("config.gaming.battlenet")
-- Game specific settings
local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local dir = config_home .. "/hypr/config/gaming/games"
local p = assert(io.popen(("find %q -maxdepth 1 -type f -name '*.lua' -printf '%%f\\n' | sort"):format(dir), "r"))
for file in p:lines() do
	local name = file:gsub("%.lua$", "")
	require("config.gaming.games." .. name)
end
p:close()
