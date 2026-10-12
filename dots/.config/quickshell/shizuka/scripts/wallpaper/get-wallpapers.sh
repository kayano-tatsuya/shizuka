#!/usr/bin/env bash
# get-wallpapers.sh — emit the local wallpaper library as a JSON object
#   { "<category>": ["/abs/path", ...], ... }
# for the AE-style masonry switcher (services/WallpaperLibrary.qml).
#
# Categories are subdirectories of the library root, named by their path
# relative to it; the root's own files land under the "" key. Images and
# videos are both included (video tiles get first-frame thumbs via
# gen-video-thumbs.sh).
#
# Override the root with WALLPAPER_ROOT (default ~/Pictures/Wallpapers, which
# is Wallpapers.qml's defaultFolder).
set -euo pipefail

root="${WALLPAPER_ROOT:-$HOME/Pictures/Wallpapers}"
[ -d "$root" ] || { printf '{}\n'; exit 0; }

jsonesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

fragments=()
while IFS= read -r -d '' dir; do
    rel="${dir#"$root"}"
    rel="${rel#/}"
    paths=()
    while IFS= read -r -d '' f; do
        paths+=("\"$(jsonesc "$f")\"")
    done < <(find "$dir" -maxdepth 1 -type f \( \
        -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
        -o -iname '*.bmp' -o -iname '*.avif' -o -iname '*.gif' -o -iname '*.svg' \
        -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \
        \) -print0 | sort -z)
    if [ ${#paths[@]} -gt 0 ]; then
        fragments+=("\"$(jsonesc "$rel")\": [$(IFS=,; echo "${paths[*]}")]")
    fi
done < <(find "$root" -type d -print0 | sort -z)

printf '{%s}\n' "$(IFS=,; echo "${fragments[*]}")"
