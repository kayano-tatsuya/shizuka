#!/usr/bin/env python3
"""accent-base.py — rewrite the neutral family of an M3 role JSON.

Used by the "Accent base" setting: the wallpaper's generated colors are kept
as accents (primary/secondary/tertiary/...), while background, the surface
ramp, outline and on-* text are replaced by a fixed neutral base for the
chosen light/dark mode, optionally tinted toward the generated accent.

Usage: accent-base.py <dark|light> <tint 0..1>   (reads JSON on stdin, writes stdout)
"""
import json
import sys

# Stock-ish Material 3 neutrals.
NEUTRAL = {
    "dark": {
        "background": "#141218",
        "surface": "#141218",
        "surface_dim": "#141218",
        "surface_bright": "#3b383e",
        "surface_container_lowest": "#0f0d13",
        "surface_container_low": "#1d1b20",
        "surface_container": "#211f26",
        "surface_container_high": "#2b2930",
        "surface_container_highest": "#36343b",
        "surface_variant": "#49454f",
        "on_background": "#e6e1e5",
        "on_surface": "#e6e1e5",
        "on_surface_variant": "#cac4d0",
        "outline": "#938f99",
        "outline_variant": "#49454f",
    },
    "light": {
        "background": "#fef7ff",
        "surface": "#fef7ff",
        "surface_dim": "#ded8e1",
        "surface_bright": "#fef7ff",
        "surface_container_lowest": "#ffffff",
        "surface_container_low": "#f7f2fa",
        "surface_container": "#f3edf7",
        "surface_container_high": "#ece6f0",
        "surface_container_highest": "#e6e0e9",
        "surface_variant": "#e7e0ec",
        "on_background": "#1d1b20",
        "on_surface": "#1d1b20",
        "on_surface_variant": "#49454f",
        "outline": "#79747e",
        "outline_variant": "#cac4d0",
    },
}

# Surface-family roles that receive the accent tint; on_*/outline stay neutral.
TINT_KEYS = (
    "background", "surface", "surface_dim", "surface_bright",
    "surface_container_lowest", "surface_container_low", "surface_container",
    "surface_container_high", "surface_container_highest", "surface_variant",
)


def from_hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def to_hex(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)


def mix(a, b, t):
    return tuple(round(ai + (bi - ai) * t) for ai, bi in zip(a, b))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "dark"
    try:
        tint = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    except ValueError:
        tint = 0.0
    tint = max(0.0, min(1.0, tint))

    data = json.load(sys.stdin)
    neutral = NEUTRAL["light" if mode == "light" else "dark"]
    primary = from_hex(data.get("primary", "#6750a4"))

    for key, value in neutral.items():
        if tint > 0 and key in TINT_KEYS:
            data[key] = to_hex(mix(from_hex(value), primary, tint))
        else:
            data[key] = value

    # Inverted surfaces follow the neutral base as well.
    data["inverse_surface"] = neutral["on_surface"]
    data["inverse_on_surface"] = neutral["background"]

    json.dump(data, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
