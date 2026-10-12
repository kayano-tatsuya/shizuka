#!/usr/bin/env bash
# fast-color.sh — cwal-only palette generation for shizuka.
#
# Replaces matugen on the everyday wallpaper path. cwal is a C reimplementation
# of pywal: it extracts a 16-color scheme in ~10-20ms, then this script maps the
# palette into the Material-You role JSON that MaterialThemeLoader.qml watches
# (~/.local/state/quickshell/user/generated/colors.json), so the running shell
# re-tints almost instantly -- no venv, no matugen, no restart.
#
# The cwal cache (~/.cache/cwal) additionally feeds pywalfox so Firefox/Floorp
# follow the wallpaper live.
#
# Usage: fast-color.sh <image|video> [dark|light]
# Runs best-effort; callers background it and ignore failures.

set -u

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
QUICKSHELL_CONFIG_NAME="shizuka"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
STATE_DIR="$XDG_STATE_HOME/quickshell"
GENERATED_DIR="$STATE_DIR/user/generated"
OUT_JSON="$GENERATED_DIR/colors.json"
CWAL_CACHE="$XDG_CACHE_HOME/cwal"
WAL_CACHE="$XDG_CACHE_HOME/wal"            # pywalfox default palette location

image="${1:-}"
mode="${2:-}"
accent="${3:-}"

[[ -z "$image" || ! -f "$image" ]] && exit 0
command -v cwal >/dev/null 2>&1 || exit 0

# ---- Accent base setting: neutral base + wallpaper accents -----------------
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/shizuka/config.json"
accent_base="false"
base_tint="0"
if [[ -f "$SHELL_CONFIG_FILE" ]]; then
    accent_base="$(jq -r '.appearance.wallpaperTheming.accentBase // false' "$SHELL_CONFIG_FILE" 2>/dev/null)"
    base_tint="$(jq -r '.appearance.wallpaperTheming.baseTint // 0' "$SHELL_CONFIG_FILE" 2>/dev/null)"
fi

# ---- resolve dark/light the same way switchwall.sh does -------------------
if [[ -z "$mode" ]]; then
    current_mode="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")"
    if [[ "$current_mode" == "prefer-light" ]]; then
        mode="light"
    else
        mode="dark"
    fi
fi
[[ "$mode" == "dark" || "$mode" == "light" ]] || mode="dark"

# ---- video wallpapers: theme from a still frame ---------------------------
src="$image"
case "${image##*.}" in
    mp4|webm|mkv|avi|mov)
        thumb="$HOME/.config/hypr/custom/scripts/mpvpaper_thumbnails/$(basename "$image").jpg"
        if [[ -f "$thumb" ]]; then
            src="$thumb"
        else
            tmp_dir="$(mktemp -d)"
            trap 'rm -rf "$tmp_dir"' EXIT
            if ! ffmpeg -y -i "$image" -vframes 1 "$tmp_dir/frame.jpg" >/dev/null 2>&1; then
                exit 0
            fi
            src="$tmp_dir/frame.jpg"
        fi
        ;;
esac

# ---- cwal: fast C palette extraction --------------------------------------
mkdir -p "$CWAL_CACHE"
if ! cwal -i "$src" --mode "$mode" --no-reload -o "$CWAL_CACHE" -q >/dev/null 2>&1; then
    exit 0
fi

# ---- map the pywal 16-color scheme into the M3 role JSON ------------------
mkdir -p "$GENERATED_DIR"
if python3 - "$CWAL_CACHE/colors.json" "$accent" > "$OUT_JSON.tmp.$$" <<'PYEOF'
import json, sys

src = sys.argv[1]
accent = sys.argv[2].strip() if len(sys.argv) > 2 else ""
with open(src) as fh:
    scheme = json.load(fh)


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgb2hex(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)


def mix(a, b, t):
    return tuple(round(ai + (bi - ai) * t) for ai, bi in zip(a, b))


def shade(c, k, dark):
    """k: 0..1; mix toward white (dark scheme) or black (light scheme)."""
    target = (255, 255, 255) if dark else (0, 0, 0)
    return mix(c, target, k)


def luminance(c):
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])


def on_color(c):
    return (0, 0, 0) if luminance(c) > 0.45 else (255, 255, 255)


def seed_ramp(c, dark):
    """Soft 'container' + fixed variants around a hue."""
    container = mix(c, bg, 0.68) if dark else mix(c, (255, 255, 255), 0.70)
    on_container = mix(c, fg, 0.30) if dark else mix(c, (0, 0, 0), 0.30)
    fixed = shade(c, 0.35, True)
    fixed_dim = mix(c, fixed, 0.5)
    on_fixed_variant = mix(fixed, (0, 0, 0) if not dark else (255, 255, 255), 0.35)
    return container, on_container, fixed, fixed_dim, on_fixed_variant


bg = hex2rgb(scheme["special"]["background"])
fg = hex2rgb(scheme["special"]["foreground"])
cols = [hex2rgb(scheme["colors"]["color%d" % i]) for i in range(16)]
dark = luminance(bg) < 0.5

# Vivid seed = highest-chroma of the base hues (color1..color6).
base = cols[1:7]
seeds = sorted(range(6), key=lambda i: (max(base[i]) - min(base[i])), reverse=True)
primary, secondary, tertiary = base[seeds[0]], base[seeds[1]], base[seeds[2]]

# A user-picked accent color overrides the primary seed.
if accent:
    try:
        primary = hex2rgb(accent)
    except Exception:
        pass

# ---- surfaces -------------------------------------------------------------
k_lowest, k_low, k_mid, k_high, k_highest, k_dim = (
    (0.05, 0.08, 0.12, 0.17, 0.24, 0.10) if dark else (0.03, 0.05, 0.08, 0.12, 0.16, 0.06))
surface_dim = shade(bg, k_dim, dark)
surface_bright = shade(bg, k_high, dark)
surface_container_lowest = shade(bg, k_lowest, dark)
surface_container_low = shade(bg, k_low, dark)
surface_container = shade(bg, k_mid, dark)
surface_container_high = shade(bg, k_high, dark)
surface_container_highest = shade(bg, k_highest, dark)
surface_variant = shade(bg, 0.22 if dark else 0.14, dark)

on_surface = fg
on_background = fg
on_surface_variant = mix(fg, bg, 0.45)
outline = mix(fg, bg, 0.55)
outline_variant = shade(bg, 0.22 if dark else 0.14, dark)

inverse_surface = fg
inverse_on_surface = bg
inverse_primary = mix(primary, bg, 0.4) if dark else mix(primary, (255, 255, 255), 0.55)

# ---- M3 error ramp (standard Material red per mode) ------------------------
if dark:
    error, on_error = (255, 180, 171), (105, 0, 5)
    error_container, on_error_container = (147, 0, 10), (255, 218, 214)
else:
    error, on_error = (186, 26, 26), (255, 255, 255)
    error_container, on_error_container = (255, 218, 214), (65, 0, 2)

# ---- hue seeds -------------------------------------------------------------
on_primary, on_secondary, on_tertiary = on_color(primary), on_color(secondary), on_color(tertiary)
(primary_container, on_primary_container, primary_fixed, primary_fixed_dim,
 on_primary_fixed_variant) = seed_ramp(primary, dark)
(secondary_container, on_secondary_container, secondary_fixed, secondary_fixed_dim,
 on_secondary_fixed_variant) = seed_ramp(secondary, dark)
(tertiary_container, on_tertiary_container, tertiary_fixed, tertiary_fixed_dim,
 on_tertiary_fixed_variant) = seed_ramp(tertiary, dark)

on_primary_fixed = on_color(primary_fixed)
on_secondary_fixed = on_color(secondary_fixed)
on_tertiary_fixed = on_color(tertiary_fixed)

out = {
    "background": rgb2hex(bg),
    "error": rgb2hex(error),
    "error_container": rgb2hex(error_container),
    "inverse_on_surface": rgb2hex(inverse_on_surface),
    "inverse_primary": rgb2hex(inverse_primary),
    "inverse_surface": rgb2hex(inverse_surface),
    "on_background": rgb2hex(on_background),
    "on_error": rgb2hex(on_error),
    "on_error_container": rgb2hex(on_error_container),
    "on_primary": rgb2hex(on_primary),
    "on_primary_container": rgb2hex(on_primary_container),
    "on_primary_fixed": rgb2hex(on_primary_fixed),
    "on_primary_fixed_variant": rgb2hex(on_primary_fixed_variant),
    "on_secondary": rgb2hex(on_secondary),
    "on_secondary_container": rgb2hex(on_secondary_container),
    "on_secondary_fixed": rgb2hex(on_secondary_fixed),
    "on_secondary_fixed_variant": rgb2hex(on_secondary_fixed_variant),
    "on_surface": rgb2hex(on_surface),
    "on_surface_variant": rgb2hex(on_surface_variant),
    "on_tertiary": rgb2hex(on_tertiary),
    "on_tertiary_container": rgb2hex(on_tertiary_container),
    "on_tertiary_fixed": rgb2hex(on_tertiary_fixed),
    "on_tertiary_fixed_variant": rgb2hex(on_tertiary_fixed_variant),
    "outline": rgb2hex(outline),
    "outline_variant": rgb2hex(outline_variant),
    "primary": rgb2hex(primary),
    "primary_container": rgb2hex(primary_container),
    "primary_fixed": rgb2hex(primary_fixed),
    "primary_fixed_dim": rgb2hex(primary_fixed_dim),
    "scrim": "#000000",
    "secondary": rgb2hex(secondary),
    "secondary_container": rgb2hex(secondary_container),
    "secondary_fixed": rgb2hex(secondary_fixed),
    "secondary_fixed_dim": rgb2hex(secondary_fixed_dim),
    "shadow": "#000000",
    "surface": rgb2hex(bg),
    "surface_bright": rgb2hex(surface_bright),
    "surface_container": rgb2hex(surface_container),
    "surface_container_high": rgb2hex(surface_container_high),
    "surface_container_highest": rgb2hex(surface_container_highest),
    "surface_container_low": rgb2hex(surface_container_low),
    "surface_container_lowest": rgb2hex(surface_container_lowest),
    "surface_dim": rgb2hex(surface_dim),
    "surface_tint": rgb2hex(primary),
    "surface_variant": rgb2hex(surface_variant),
    "tertiary": rgb2hex(tertiary),
    "tertiary_container": rgb2hex(tertiary_container),
    "tertiary_fixed": rgb2hex(tertiary_fixed),
    "tertiary_fixed_dim": rgb2hex(tertiary_fixed_dim),
}
json.dump(out, sys.stdout, indent=2)
sys.stdout.write("\n")
PYEOF
then
    # Accent base (cwal path): rewrite the neutral family to the fixed
    # light/dark base, keeping the wallpaper hues as accents. Stays one
    # atomic write so the instant shell tint is preserved.
    if [[ "$accent_base" == "true" ]] && [[ -s "$OUT_JSON.tmp.$$" ]]; then
        if python3 "$CONFIG_DIR/scripts/colors/accent-base.py" "$mode" "$base_tint" \
            < "$OUT_JSON.tmp.$$" > "$OUT_JSON.tmp2.$$"; then
            mv -f "$OUT_JSON.tmp2.$$" "$OUT_JSON"
        else
            rm -f "$OUT_JSON.tmp2.$$"
            mv -f "$OUT_JSON.tmp.$$" "$OUT_JSON"
        fi
    else
        mv -f "$OUT_JSON.tmp.$$" "$OUT_JSON"
    fi
else
    rm -f "$OUT_JSON.tmp.$$"
    exit 0
fi

# ---- pywalfox: push the fresh palette to Firefox / Floorp ------------------
if command -v pywalfox >/dev/null 2>&1; then
    mkdir -p "$WAL_CACHE"
    cp -f "$CWAL_CACHE/colors.json" "$WAL_CACHE/colors.json" 2>/dev/null || true
    pywalfox update >/dev/null 2>&1 || true
fi

echo "fast-color: wrote $OUT_JSON (mode=$mode)"