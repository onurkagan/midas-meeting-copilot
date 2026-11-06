"""Native messaging host for Midas for Chrome (extension/): passes a tab's audio to the daemon.

Chrome starts it (`midas` with the extension's origin as its argument) and talks to it over
stdio, each message a 4-byte length and JSON. It passes each message on as one JSON line
over a Unix socket that only this user may open (logs/tab.sock), so the HTTP API stays
closed to browsers and no web page can reach Midas this way. Chrome lets only the Midas
extension start it (allowed_origins in the host manifest, written by ./midas install).
"""

import json
import socket
import struct
import sys

from .config import TAB_SOCKET


def receive(stream) -> dict | None:
    header = stream.read(4)
    if len(header) < 4:
        return None
    (length,) = struct.unpack("=I", header)
    return json.loads(stream.read(length))


def send(message: dict):
    data = json.dumps(message).encode()
    sys.stdout.buffer.write(struct.pack("=I", len(data)) + data)
    sys.stdout.buffer.flush()


def main():
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        connection.connect(str(TAB_SOCKET))
    except OSError:
        send({"type": "error", "message": "Midas isn't running. Open Midas, then click the button again."})
        return
    send({"type": "connected"})
    with connection:
        while (message := receive(sys.stdin.buffer)) is not None:
            try:
                connection.sendall(json.dumps(message).encode() + b"\n")
            except OSError:
                send({"type": "error", "message": "Midas stopped."})
                return
