#!/bin/sh
# Copy the addon into the WoW: Forever beta AddOns folder.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WOW="${WOW_DIR:-/Applications/World of Warcraft/_classic_beta_}"
DEST="$WOW/Interface/AddOns/ForeverLoot"
mkdir -p "$DEST"
cp "$HERE"/ForeverLoot/*.toc "$HERE"/ForeverLoot/*.lua "$DEST"/
echo "Installed to $DEST"
