-- General settings
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Firefox settings
hl.env("MOZ_CRASHREPORTER_DISABLE", "1")
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- QT application themes
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct") -- Tells QT based apps to pick themes from qt6ct
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1") -- Enables auto scaling
