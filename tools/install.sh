#!/bin/sh
# Copy the addon into the WoW: Forever AddOns folder.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WOW="${WOW_DIR:-/Applications/World of Warcraft/_forever_}"
DEST="$WOW/Interface/AddOns/ForeverLoot"
mkdir -p "$DEST"
cp "$HERE"/ForeverLoot/*.toc "$HERE"/ForeverLoot/*.lua "$DEST"/
echo "Installed to $DEST"
