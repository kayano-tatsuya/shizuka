#!/bin/bash
# Path to cache directory
CACHE_DIR="$HOME/.config/fastfetch/cache"

# Pick the most recently pinned file from the cache directory
IMAGE_PATH=$(find "$CACHE_DIR" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-)

if [ -z "$IMAGE_PATH" ]; then
    # Fetch system information without logo
    fastfetch
    exit 0
fi

# Fetch system information with fixed logo size
fastfetch --logo-type kitty --logo-cache regen --logo-height 32 --logo "$IMAGE_PATH"
