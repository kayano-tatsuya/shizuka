#!/usr/bin/env bash
# pywalfox-sync-matugen.sh — feed matugen's palette to pywalfox.
#
# In the cwal engine, fast-color.sh hands pywalfox cwal's native pywal palette.
# The full-matugen engine has no pywal output, so this converts matugen's M3
# role JSON (~/.local/state/quickshell/user/generated/colors.json) into a
# pywal-style ~/.cache/wal/colors.json and pushes it to open Firefox/Floorp
# sessions. Best-effort; callers background it and ignore failures.

set -u

XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
M3_JSON="$XDG_STATE_HOME/quickshell/user/generated/colors.json"
WAL_CACHE="$XDG_CACHE_HOME/wal"

command -v pywalfox >/dev/null 2>&1 || exit 0
[[ -f "$M3_JSON" ]] || exit 0

mkdir -p "$WAL_CACHE"
if python3 - "$M3_JSON" > "$WAL_CACHE/colors.json.tmp.$$" <<'PYEOF'
import json, sys

m = json.load(open(sys.argv[1]))


def g(key, fallback):
    return m.get(key, fallback)


# Map M3 roles onto the 16 pywal slots pywalfox expects.
colors = {
    "color0": g("surface_container_lowest", g("surface", "#1c1b1f")),
    "color1": g("error", "#ffb4ab"),
    "color2": g("secondary", "#cac4d0"),
    "color3": g("tertiary", "#e8def8"),
    "color4": g("primary", "#d0bcff"),
    "color5": g("primary_fixed", g("primary", "#d0bcff")),
    "color6": g("secondary_fixed", g("secondary", "#cac4d0")),
    "color7": g("on_surface_variant", g("on_surface", "#e6e1e5")),
    "color8": g("outline", "#938f99"),
    "color9": g("error_container", "#93000a"),
    "color10": g("secondary_container", "#4a4458"),
    "color11": g("tertiary_container", "#633b48"),
    "color12": g("primary_container", "#4f378b"),
    "color13": g("primary_fixed_dim", g("primary", "#d0bcff")),
    "color14": g("secondary_fixed_dim", g("secondary", "#cac4d0")),
    "color15": g("on_surface", g("on_background", "#e6e1e5")),
}
out = {
    "colors": colors,
    "special": {
        "background": g("background", "#1c1b1f"),
        "foreground": g("on_background", g("on_surface", "#e6e1e5")),
        "cursor": g("on_background", g("on_surface", "#e6e1e5")),
    },
    "wallpaper": "",
}
json.dump(out, sys.stdout, indent=2)
sys.stdout.write("\n")
PYEOF
then
    mv -f "$WAL_CACHE/colors.json.tmp.$$" "$WAL_CACHE/colors.json"
else
    rm -f "$WAL_CACHE/colors.json.tmp.$$"
    exit 0
fi

pywalfox update >/dev/null 2>&1 || true
