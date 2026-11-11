hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

hl.unbind("SUPER + W")
hl.bind("SUPER + W", hl.dsp.exec_cmd("~/.local/opt/floorp/floorp"), { description = "App: Browser" })

hl.unbind("SUPER + B")
hl.bind("SUPER + B", hl.dsp.exec_cmd("kitty -e btop"), { description = "App: btop" })

hl.bind("SUPER + escape", hl.dsp.global("quickshell:settingsToggle"), {description = "Toggle settings"})

-- Alarm: GUI prompt. Rings even after the machine has been suspended, because the
-- trigger is a systemd wall-clock timer (plus the hardware RTC alarm when enabled).
hl.bind("CTRL + SUPER + A", hl.dsp.exec_cmd("~/.local/bin/alarm-prompt"), { description = "Alarm: Set an alarm" })
