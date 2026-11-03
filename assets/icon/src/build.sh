#!/usr/bin/env bash
# Regenerates the Midas icon: the master SVG and the 1024 px PNG that install_app.sh uses.
# The fur is hundreds of seeded strokes, so change the generator, not the SVG.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON="$(dirname "$SRC")"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

python3 "$SRC/generate.py" "$ICON/Midas.svg"
# Chrome renders the SVG's filters and masks faithfully; QuickLook (qlmanage -t) is close.
"$CHROME" --headless --hide-scrollbars --force-device-scale-factor=1 --force-color-profile=srgb \
  --default-background-color=00000000 --window-size=1024,1024 \
  --screenshot="$ICON/Midas-1024.png" "file://$ICON/Midas.svg" 2>/dev/null
sips -e "/System/Library/ColorSync/Profiles/sRGB Profile.icc" "$ICON/Midas-1024.png" >/dev/null
echo "Wrote $ICON/Midas.svg and $ICON/Midas-1024.png"
