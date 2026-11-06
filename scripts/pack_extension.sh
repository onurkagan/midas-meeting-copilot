#!/usr/bin/env bash
# Packs Midas for Chrome for the Chrome Web Store: the extension without the "key" field
# (the store gives it its own ID; put that ID in extension/store-id.txt so ./midas install
# lets it reach Midas) and without the files only for this repository.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/chrome-web-store"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/extension/manifest.json")"
ZIP="$ROOT/build/midas-for-chrome-$VERSION.zip"

rm -rf "${OUT:?}" "$ZIP"
mkdir -p "$OUT"
rsync -a --exclude STORE.md --exclude store-id.txt "$ROOT/extension/" "$OUT/"
python3 - "$OUT/manifest.json" <<'EOF'
import json, sys
path = sys.argv[1]
manifest = json.load(open(path))
manifest.pop("key", None)
json.dump(manifest, open(path, "w"), indent=2, ensure_ascii=False)
EOF
(cd "$OUT" && zip -qr "$ZIP" .)
echo "Packed: $ZIP"
