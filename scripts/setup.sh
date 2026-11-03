#!/usr/bin/env bash
# Builds the native helpers, the Python environment and the Claude Code MCP config.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export HF_HUB_DISABLE_XET=1

echo "→ Building the Swift components"
mkdir -p bin logs sessions
# build <binary> <Info.plist> <sources...>
build() {
  local binary=$1 plist=$2
  shift 2
  swiftc -O -swift-version 5 -o "bin/$binary" "$@" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "native/$plist"
}
build midas-audio AudioInfo.plist native/AudioCapture.swift
build midas-overlay OverlayInfo.plist native/Overlay/*.swift
# A stable identity with the Info.plist bound, so macOS can show the permission prompt.
codesign -s - -f --identifier dev.midas.audio bin/midas-audio 2>/dev/null

echo "→ Python environment (.venv)"
[[ -d .venv ]] || python3 -m venv .venv
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r requirements.txt

MODEL="$(PYTHONPATH=src .venv/bin/python -c 'from midas.config import load_config; print(load_config().model)')"
echo "→ Whisper model: $MODEL (~1.6 GB download the first time)"
.venv/bin/python -c "from huggingface_hub import snapshot_download; snapshot_download('$MODEL')" >/dev/null

echo "→ Claude Code MCP config (.mcp.json)"
cat >.mcp.json <<EOF
{
  "mcpServers": {
    "midas": {
      "command": "$ROOT/midas",
      "args": ["mcp"]
    }
  }
}
EOF

[[ -f context.md ]] || cp context.example.md context.md

cat <<EOF

Setup complete. To start:

  ./midas start      (or ./midas install for the Midas.app)

On first run macOS asks for "System Audio Recording" permission for midas-audio; allow it.
If you denied it: System Settings → Privacy & Security → Screen & System Audio Recording →
"System Audio Recording Only" → midas-audio.
EOF
