----------------------------------------------------------
------------------------- HELPERS ------------------------
----------------------------------------------------------
-- Later property tables override earlier ones.
local function merge(...)
	local result = {}
	for index = 1, select("#", ...) do
		local source = select(index, ...)

		if source then
			for key, value in pairs(source) do
				result[key] = value
			end
		end
	end
	return result
end

local function window_rule(name, match, ...)
	local properties = merge(...)
	properties.name = name
	properties.match = match
	hl.window_rule(properties)
end

local STYLE = {
	floating = {
		float = true,
	},
	persistent_floating = {
		float = true,
		persistent_size = true,
	},
	opaque = {
		opaque = true,
		no_blur = true,
	},
}

----------------------------------------------------------
--------------------- GLOBAL BEHAVIOR --------------------
----------------------------------------------------------
window_rule("Suppress maximize requests", {
	class = ".*",
}, {
	suppress_event = "maximize",
})

window_rule("Fix XWayland dragging", {
	class = "^$",
	title = "^$",
	xwayland = true,
	float = true,
	fullscreen = false,
	pin = false,
}, {
	no_focus = true,
})

----------------------------------------------------------
------------------------- BROWSERS -----------------------
----------------------------------------------------------
window_rule("Brave: opaque", {
	class = "brave-origin-nightly",
}, STYLE.opaque)

window_rule("Zen: opaque", {
	class = BROWSER,
}, {
	opaque = true,
})

window_rule("Zen: floating secondary windows", {
	class = BROWSER,
	title = "^(Picture-in-Picture|Library)$",
}, STYLE.floating)

----------------------------------------------------------
-------------------- RESEARCH AND NOTES ------------------
----------------------------------------------------------
window_rule("Zotero dialogs: floating", {
	class = "Zotero",
	title = "^(Zotero Settings|Select a File|Zotero - Document Preferences|Citation Dialog)$",
}, STYLE.persistent_floating)

----------------------------------------------------------
--------------------- MEDIA AND IMAGES -------------------
----------------------------------------------------------
window_rule("feh: floating opaque window", {
	class = "feh",
}, STYLE.floating, STYLE.opaque)

window_rule(
	"mpv: centered floating window",
	{
		class = "mpv",
	},
	STYLE.floating,
	STYLE.opaque,
	{
		size = "1582 890",
		center = true,
		border_color = "rgba(00000000)",
	}
)

window_rule(
	"Stremio: fullscreen on workspace 4",
	{
		class = "com.stremio.stremio",
		title = "Stremio - Freedom to Stream",
	},
	STYLE.opaque,
	{
		fullscreen = true,
		workspace = 4,
	}
)

window_rule("Swappy: opaque", {
	class = "swappy",
	title = "swappy",
}, STYLE.opaque)

----------------------------------------------------------
---------------------- COMMUNICATION ---------------------
----------------------------------------------------------
window_rule(
	"LocalSend: floating window",
	{
		class = "org.localsend.localsend_app",
		title = "LocalSend",
	},
	STYLE.floating,
	{
		size = "970 635",
	}
)

----------------------------------------------------------
-------------------- ENGINEERING AND CAD -----------------
----------------------------------------------------------
window_rule("CubeMX: floating", {
	class = "com-st-microxplorer-maingui-STM32CubeMX",
}, STYLE.persistent_floating)

window_rule(
	"OrcaSlicer and FreeCAD: workspace 5",
	{
		class = "^(orca-slicer|org[.]freecad[.]FreeCAD)$",
	},
	STYLE.opaque,
	{
		workspace = 5,
	}
)

window_rule("FreeCAD Addon Manager: floating", {
	class = "org.freecad.FreeCAD",
	title = "^Addon Manager version .*$",
}, STYLE.persistent_floating)

window_rule("GTKWave: floating opaque window", {
	class = "gtkwave",
}, STYLE.persistent_floating, STYLE.opaque)

window_rule("hex: floating", {
	class = "hex",
	title = "Hex",
}, STYLE.persistent_floating)

window_rule("KiCad: opaque", {
	class = "kicad",
}, STYLE.opaque)

window_rule("LTspice: opaque", {
	class = "ltspice.exe",
}, STYLE.opaque)

window_rule(
	"MATLAB: workspace 6",
	{
		class = "MATLAB R2026a Update 4",
	},
	STYLE.opaque,
	{
		workspace = 6,
	}
)

----------------------------------------------------------
--------------------- VIRTUALIZATION ---------------------
----------------------------------------------------------
window_rule("Windows VM: opaque", {
	class = "virt-manager",
	title = "Windows 11 on QEMU/KVM",
}, STYLE.opaque)

window_rule(
	"virt-manager: floating management dialogs",
	{
		class = "virt-manager",
		title = "^(Virtual Machine Manager|QEMU/KVM - Connection Details)$",
	},
	STYLE.persistent_floating,
	{
		xray = false,
	}
)

----------------------------------------------------------
---------------------- DESKTOP SHELL ---------------------
----------------------------------------------------------
window_rule("Authentication Agent: non xray window", {
	class = "hyprpolkitagent",
}, { xray = false })

window_rule("Screenshare menu: floating", {
	class = "hyprland-share-picker",
}, STYLE.persistent_floating)

window_rule(
	"Wallpaper Switcher: floating opaque window",
	{
		title = "wallpaper-switcher",
	},
	STYLE.floating,
	STYLE.opaque,
	{
		no_blur = false,
		xray = false,
	}
)

----------------------------------------------------------
-------------------- DESKTOP UTILITIES -------------------
----------------------------------------------------------
window_rule("EnteAuth: floating", {
	class = "io.ente.auth",
	title = "Ente Auth",
}, STYLE.persistent_floating)

window_rule("Fcitx Configuration Tool: floating opaque dialog", {
	class = "org.fcitx.fcitx5-config-qt",
}, STYLE.persistent_floating, STYLE.opaque)

window_rule(
	"File Manager: centered floating window",
	{
		class = FILEMANAGER,
	},
	STYLE.persistent_floating,
	{
		size = "970 635",
		center = true,
		xray = false,
	}
)

window_rule("LACT: floating", {
	class = "io.github.ilya_zlobintsev.LACT",
	title = "LACT",
}, STYLE.persistent_floating)

window_rule(
	"nm-connection-editor: floating window",
	{
		class = "nm-connection-editor",
	},
	STYLE.floating,
	{
		center = true,
	}
)

window_rule("nwg-look: floating", {
	title = "nwg-look",
}, STYLE.persistent_floating)

window_rule(
	"OpenRGB: centered floating window",
	{
		class = "org.openrgb.OpenRGB",
	},
	STYLE.floating,
	{
		size = "1000 750",
		center = true,
	}
)

window_rule(
	"Pavucontrol: positioned floating dialog",
	{
		class = "pavucontrol-qt",
		title = "Volume Control",
	},
	STYLE.floating,
	{
		move = "1303 644",
	}
)

window_rule("Qt5 Configuration Tool: floating", {
	class = "qt5ct",
}, STYLE.persistent_floating)

window_rule("Qt6 Configuration Tool: floating", {
	class = "qt6ct",
}, STYLE.persistent_floating)

window_rule(
	"Bluetui: centered floating window",
	{
		class = "bluetui",
	},
	STYLE.floating,
	{
		size = "900 650",
		center = true,
	}
)

----------------------------------------------------------
-------------------- LAUNCHERS AND OSD -------------------
----------------------------------------------------------
window_rule(
	"Rofi Screenshot: bottom sliding dialog",
	{
		title = "rofi - screenshot",
	},
	STYLE.persistent_floating,
	{
		dim_around = true,
		animation = "slide",
		xray = false,
	}
)

window_rule(
	"Rofi Confirmation: centered dimmed dialog",
	{
		title = "rofi - confirmbox",
	},
	STYLE.persistent_floating,
	{
		center = true,
		dim_around = true,
		border_color = "rgba(00000000)",
		animation = "gnomed",
		xray = false,
	}
)

window_rule(
	"hyprland-run: bottom floating window",
	{
		class = "hyprland-run",
	},
	STYLE.floating,
	{
		move = "(20) (monitor_h-120)",
	}
)
