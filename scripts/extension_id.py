"""Prints the IDs Chrome gives Midas for Chrome, one per line: the one from the public key
in its manifest (Load unpacked), then the Chrome Web Store's, once extension/store-id.txt
holds it. The native messaging host lets only these start it (allowed_origins)."""

import base64
import hashlib
import json
import sys
from pathlib import Path

manifest = Path(sys.argv[1])
key = json.loads(manifest.read_text())["key"]
digest = hashlib.sha256(base64.b64decode(key)).hexdigest()[:32]
print("".join(chr(ord("a") + int(c, 16)) for c in digest))
store = manifest.with_name("store-id.txt")
if store.exists() and (store_id := store.read_text().strip()):
    print(store_id)
