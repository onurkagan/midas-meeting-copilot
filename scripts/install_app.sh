#!/usr/bin/env bash
# Installs Midas as an app: a runtime copy in ~/Library/Application Support/Midas (apps may
# not run code from the protected Desktop/Documents folders) and Midas.app in /Applications.
# Opening the app starts listening, the hidden panel and a headless Claude Code copilot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${MIDAS_HOME:-$HOME/Library/Application Support/Midas}"
DEST="${MIDAS_APP_DIR:-/Applications}/Midas.app"
BUILD="$ROOT/build"
APP="$BUILD/Midas.app"

if [[ ! -x "$ROOT/bin/midas-audio" || ! -x "$ROOT/.venv/bin/python" ]]; then
  echo "Run ./midas setup first."
  exit 1
fi
VERSION="$(PYTHONPATH="$ROOT/src" "$ROOT/.venv/bin/python" -c 'import midas; print(midas.__version__)')"

echo "→ Runtime copy: $RUNTIME"
mkdir -p "$RUNTIME/logs" "$RUNTIME/sessions"
# Code and the Python environment are replaced on every install; user data is kept.
rsync -a --delete --exclude __pycache__ "$ROOT/src/" "$RUNTIME/src/"
rsync -a --delete "$ROOT/bin/" "$RUNTIME/bin/"
rsync -a --delete "$ROOT/.claude/" "$RUNTIME/.claude/"
rsync -a --delete --exclude __pycache__ "$ROOT/.venv/" "$RUNTIME/.venv/"
cp "$ROOT/midas" "$ROOT/requirements.txt" "$ROOT/README.md" "$ROOT/context.example.md" "$RUNTIME/"
for file in config.toml context.md; do
  [[ -e "$RUNTIME/$file" ]] || cp "$ROOT/$file" "$RUNTIME/$file"
done
cat >"$RUNTIME/.mcp.json" <<EOF
{
  "mcpServers": {
    "midas": {
      "command": "$RUNTIME/midas",
      "args": ["mcp"]
    }
  }
}
EOF
# Midas for Chrome: the extension to load (Developer mode › Load unpacked), and the native
# messaging host it reaches Midas through. Chrome lets only that extension start the host.
rsync -a --delete "$ROOT/extension/" "$RUNTIME/extension/"
CHROME="$HOME/Library/Application Support/Google/Chrome"
if [[ -d "$CHROME" ]]; then
  # The unpacked extension's ID, and the Chrome Web Store's once extension/store-id.txt has it.
  ORIGINS="$("$ROOT/.venv/bin/python" "$ROOT/scripts/extension_id.py" "$ROOT/extension/manifest.json" \
    | sed 's|.*|"chrome-extension://&/"|' | paste -sd, - | sed 's/,/, /g')"
  mkdir -p "$CHROME/NativeMessagingHosts"
  cat >"$CHROME/NativeMessagingHosts/dev.midas.tab.json" <<EOF
{
  "name": "dev.midas.tab",
  "description": "Midas: a call tab's audio from Midas for Chrome",
  "path": "$RUNTIME/midas",
  "type": "stdio",
  "allowed_origins": [$ORIGINS]
}
EOF
fi
# Files written by another app carry its access markers (com.apple.macl); drop them.
xattr -rc "$RUNTIME" 2>/dev/null || true

echo "→ Building Midas.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# The panel is the app's main program; it starts the daemon from MidasRoot and shows
# itself again when the app is reopened.
cp "$ROOT/bin/midas-overlay" "$APP/Contents/MacOS/Midas"
# The panel's typeface, Plus Jakarta Sans (SIL Open Font License, see OFL.txt).
mkdir -p "$APP/Contents/Resources/fonts"
cp "$ROOT/assets/fonts/PlusJakartaSans-Variable.ttf" "$ROOT/assets/fonts/OFL.txt" "$APP/Contents/Resources/fonts/"

cat >"$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Midas</string>
	<key>CFBundleIconFile</key>
	<string>Midas</string>
	<key>CFBundleIdentifier</key>
	<string>dev.midas.app</string>
	<key>CFBundleName</key>
	<string>Midas</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.4</string>
	<key>LSUIElement</key>
	<true/>
	<key>MidasRoot</key>
	<string>$RUNTIME</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
</dict>
</plist>
EOF

echo "→ Icon"
ICONSET="$BUILD/Midas.iconset"
# Rendered from the master artwork, assets/icon/Midas.svg.
ICON="$ROOT/assets/icon/Midas-1024.png"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$ICON" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Midas.icns"

codesign -s - -f "$APP" 2>/dev/null

echo "→ Installing: $DEST"
rm -rf "$DEST"
ditto "$APP" "$DEST"
xattr -rc "$DEST" 2>/dev/null || true
echo "Installed. Open it from Launchpad or Spotlight (⌘Space → Midas)."
