#!/usr/bin/env bash
# Renders the images of the project site (docs/, served by GitHub Pages) and the README:
# icon sizes, panel screenshots from sample data, and the 1280×640 social preview card.
# Needs bin/midas-overlay (./midas setup) and Google Chrome.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/docs/assets"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
SRGB="/System/Library/ColorSync/Profiles/sRGB Profile.icc"
mkdir -p "$OUT"

# Icon: page logo, favicons and the iOS/macOS home-screen icon.
for size in 512 256 180 64 32; do
  sips -z "$size" "$size" "$ROOT/assets/icon/Midas-1024.png" --out "$OUT/icon-$size.png" >/dev/null
done

# The live panel is hidden from screenshots, so render it with sample data instead.
PREVIEW="$(mktemp -d)"
trap 'rm -rf "$PREVIEW"' EXIT
"$ROOT/bin/midas-overlay" --render-preview "$PREVIEW"
cp "$PREVIEW/meeting.png" "$OUT/panel.png"
cp "$PREVIEW/drafting-settings.png" "$OUT/panel-settings.png"

# Social preview card (GitHub "Social preview" and the site's og:image).
"$CHROME" --headless --hide-scrollbars --force-device-scale-factor=1 --force-color-profile=srgb \
  --allow-file-access-from-files --window-size=1280,640 \
  --screenshot="$OUT/og.png" "file://$ROOT/assets/social/card.html" 2>/dev/null

for image in "$OUT"/*.png; do sips -e "$SRGB" "$image" >/dev/null; done
echo "Wrote $(ls "$OUT" | wc -l | tr -d ' ') images to $OUT"
