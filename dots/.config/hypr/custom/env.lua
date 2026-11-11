-- Custom environment variables (user overrides)
-- Cursor theme: Hyprland's own cursor uses hyprcursor (HYPRCURSOR_*), set at
-- compositor launch. XCURSOR_* covers XWayland / legacy apps. Without these,
-- Hyprland boots with the fallback default cursor until (and despite)
-- `hyprctl setcursor` in execs.lua.
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")
