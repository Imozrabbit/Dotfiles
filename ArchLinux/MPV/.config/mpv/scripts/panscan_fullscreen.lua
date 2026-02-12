local mp = require("mp")

local function sync_panscan(_, fs)
	if fs then
		mp.set_property_number("panscan", 1)
	else
		mp.set_property_number("panscan", 0)
	end
end

mp.observe_property("fullscreen", "bool", sync_panscan)
