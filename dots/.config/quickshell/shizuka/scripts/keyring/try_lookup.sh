#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer the new "shizuka" application label; fall back to the legacy
# "illogical-impulse" label so existing stored secrets keep working after
# the rename (they are migrated to "shizuka" on the next save).
data=$(secret-tool lookup 'application' 'shizuka')
if [[ -z "$data" ]]; then
    data=$(secret-tool lookup 'application' 'illogical-impulse')
fi

if [[ -z "$data" ]]; then
    if "${SCRIPT_DIR}/is_unlocked.sh"; then
        echo 'not found'
        exit 1
    else 
        echo 'locked'
        exit 2
    fi
fi
echo "$data"
