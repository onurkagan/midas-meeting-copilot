"""Prints the ID Chrome gives Midas for Chrome, from the public key in its manifest.

The native messaging host lets only this extension start it (allowed_origins)."""

import base64
import hashlib
import json
import sys

key = json.load(open(sys.argv[1]))["key"]
digest = hashlib.sha256(base64.b64decode(key)).hexdigest()[:32]
print("".join(chr(ord("a") + int(c, 16)) for c in digest))
