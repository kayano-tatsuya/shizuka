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
# Sort order of files within each category is controlled by WALLPAPER_SORT:
#   name (default) | name_rev | time | time_rev | size | size_rev
# Directories (categories) are always sorted alphabetically by relative path.
#
# Override the root with WALLPAPER_ROOT (default ~/Pictures/Wallpapers, which
# is Wallpapers.qml's defaultFolder).
set -euo pipefail

root="${WALLPAPER_ROOT:-$HOME/Pictures/Wallpapers}"
[ -d "$root" ] || { printf '{}\n'; exit 0; }

sort_mode="${WALLPAPER_SORT:-name}"

jsonesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

fragments=()
while IFS= read -r -d '' dir; do
    rel="${dir#"$root"}"
    rel="${rel#/}"
    paths=()
    # Collect files with the sort key prepended, then sort, then strip key.
    case "$sort_mode" in
        time|time_rev)
            # key = mtime epoch (integer seconds) for stable numeric sort
            while IFS= read -r -d '' f; do
                mtime=$(stat -c '%Y' "$f" 2>/dev/null || echo 0)
                paths+=("$mtime"$'\t'"$f")
            done < <(find "$dir" -maxdepth 1 -type f \( \
                -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
                -o -iname '*.bmp' -o -iname '*.avif' -o -iname '*.gif' -o -iname '*.svg' \
                -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \
                \) -print0)
            ;;
        size|size_rev)
            while IFS= read -r -d '' f; do
                sz=$(stat -c '%s' "$f" 2>/dev/null || echo 0)
                paths+=("$sz"$'\t'"$f")
            done < <(find "$dir" -maxdepth 1 -type f \( \
                -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
                -o -iname '*.bmp' -o -iname '*.avif' -o -iname '*.gif' -o -iname '*.svg' \
                -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \
                \) -print0)
            ;;
        *)
            # name / name_rev / custom: sort by basename (paths already absolute;
            # sort by full path is equivalent within a single dir).
            while IFS= read -r -d '' f; do
                paths+=("$f")
            done < <(find "$dir" -maxdepth 1 -type f \( \
                -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
                -o -iname '*.bmp' -o -iname '*.avif' -o -iname '*.gif' -o -iname '*.svg' \
                -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \
                \) -print0 | sort -z)
            ;;
    esac

    # Apply numeric sort for keyed modes.
    if [ ${#paths[@]} -gt 0 ]; then
        case "$sort_mode" in
            time)      sorted=$(printf '%s\n' "${paths[@]}" | sort -t$'\t' -k1,1rn | cut -f2-) ;;
            time_rev)  sorted=$(printf '%s\n' "${paths[@]}" | sort -t$'\t' -k1,1n  | cut -f2-) ;;
            size)      sorted=$(printf '%s\n' "${paths[@]}" | sort -t$'\t' -k1,1rn | cut -f2-) ;;
            size_rev)  sorted=$(printf '%s\n' "${paths[@]}" | sort -t$'\t' -k1,1n  | cut -f2-) ;;
            name_rev)  sorted=$(printf '%s\n' "${paths[@]}" | sort -r) ;;
            *)         sorted=$(printf '%s\n' "${paths[@]}") ;;
        esac
        # Rebuild JSON array from sorted lines (paths may contain spaces; one per line is safe
        # because paths are absolute and we split on newline — paths cannot contain newlines).
        json_paths=()
        while IFS= read -r p; do
            [ -z "$p" ] && continue
            json_paths+=("\"$(jsonesc "$p")\"")
        done <<< "$sorted"
        if [ ${#json_paths[@]} -gt 0 ]; then
            fragments+=("\"$(jsonesc "$rel")\": [$(IFS=,; echo "${json_paths[*]}")]")
        fi
    fi
done < <(find "$root" -type d -print0 | sort -z)

printf '{%s}\n' "$(IFS=,; echo "${fragments[*]}")"
