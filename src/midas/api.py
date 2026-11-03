"""Local HTTP API (127.0.0.1 only) used by the MCP bridge and the overlay."""

import json
import logging
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from . import __version__
from .config import CONTEXT_FILE
from .store import ANSWER, REQUEST, TRANSCRIPT, Store

log = logging.getLogger("midas.api")


def serve(store: Store, host: str, port: int, on_quit, on_copilot, auto_answer: bool) -> ThreadingHTTPServer:
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def _send(self, payload: dict, status: int = 200):
            body = json.dumps(payload, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _body(self) -> dict:
            length = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(length) or b"{}")

        def do_GET(self):
            url = urlparse(self.path)
            query = {k: v[-1] for k, v in parse_qs(url.query).items()}
            if url.path == "/api/health":
                self._send(
                    {
                        "ok": True,
                        "version": __version__,
                        "status": store.status,
                        "paused": store.paused,
                        "session_file": str(store.session_file),
                        "context_file": str(CONTEXT_FILE),
                        "context_exists": CONTEXT_FILE.exists(),
                    }
                )
            elif url.path == "/api/snapshot":
                self._send(store.snapshot())
            elif url.path == "/api/wait":
                cursor = int(query.get("cursor", 0))
                timeout = min(float(query.get("timeout", 30)), 3600.0)
                cursor, events, partial = store.wait(cursor, timeout, auto=auto_answer)
                self._send({"cursor": cursor, "events": events, "partial": partial, "auto": auto_answer})
            elif url.path == "/api/recent":
                cursor, events = store.recent((TRANSCRIPT, REQUEST), int(query.get("last", 30)))
                self._send({"cursor": cursor, "events": events, "pending": store.pending_requests()})
            else:
                self._send({"error": "not found"}, 404)

        def do_POST(self):
            url = urlparse(self.path)
            try:
                body = self._body()
            except json.JSONDecodeError:
                return self._send({"error": "invalid json"}, 400)
            if url.path == "/api/answer":
                text = str(body.get("text", "")).strip()
                if not text:
                    return self._send({"error": "text is required"}, 400)
                self._send(store.add(ANSWER, text, str(body.get("title", "")).strip()))
            elif url.path == "/api/request":
                self._send(store.add(REQUEST, str(body.get("text", "")).strip()))
            elif url.path == "/api/control":
                action = body.get("action")
                if action == "quit":
                    self._send({"quitting": True})
                    return on_quit()
                if action == "copilot":
                    try:
                        return self._send(on_copilot(body.get("model"), body.get("effort")))
                    except ValueError as error:
                        return self._send({"error": str(error)}, 400)
                if action not in ("pause", "resume"):
                    return self._send({"error": "action must be pause, resume, copilot or quit"}, 400)
                store.update(paused=action == "pause", partial="")
                self._send({"paused": store.paused})
            else:
                self._send({"error": "not found"}, 404)

    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, name="api", daemon=True).start()
    log.info("API: http://%s:%d", host, port)
    return server
