"""Local HTTP API (127.0.0.1 only) used by the MCP bridge and the overlay.

Only programs on this Mac may use it, never web pages: a site open in the browser could
otherwise send commands to 127.0.0.1, or read the meeting through DNS rebinding."""

import json
import logging
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse, urlsplit

from . import __version__
from .config import CONTEXT_FILE
from .store import ANSWER, REQUEST, TRANSCRIPT, Store

log = logging.getLogger("midas.api")

LOOPBACK = {"127.0.0.1", "localhost", "::1"}


def refusal(method: str, headers, allowed_hosts: set[str]) -> tuple[int, str] | None:
    """(status, reason) when a request must be refused, else None. Browsers mark their
    requests with Origin or Sec-Fetch-Site (except for an address the user typed in), and
    a cross-site page can't send JSON without a CORS preflight, which this server never
    allows. A Host naming another machine means DNS rebinding."""
    host = urlsplit(f"//{headers.get('Host', '')}").hostname or ""
    if host and host not in allowed_hosts:
        return 403, f"host {host!r} isn't this Mac"
    origin, site = headers.get("Origin"), headers.get("Sec-Fetch-Site")
    if origin is not None or (site and site != "none"):
        return 403, f"request from a web page ({origin or site})"
    content_type = (headers.get("Content-Type") or "").split(";")[0].strip().lower()
    if method == "POST" and content_type != "application/json":
        return 415, "POST bodies must be application/json"
    return None


def serve(store: Store, host: str, port: int, on_quit, on_copilot, on_ollama, auto_answer: bool) -> ThreadingHTTPServer:
    allowed_hosts = LOOPBACK | {host}
    reported: set[str] = set()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def _refused(self) -> bool:
            if not (problem := refusal(self.command, self.headers, allowed_hosts)):
                return False
            status, reason = problem
            if reason not in reported:  # once each, so a page can't flood the log
                reported.add(reason)
                log.warning("refused %s %s: %s", self.command, self.path.split("?")[0], reason)
            self._send({"error": f"refused: {reason}"}, status)
            return True

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
            if self._refused():
                return
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
                self._send(store.snapshot(int(query.get("since", 0))))
            elif url.path == "/api/wait":
                cursor = int(query.get("cursor", 0))
                timeout = min(float(query.get("timeout", 30)), 3600.0)
                cursor, events, partial = store.wait(cursor, timeout, auto=auto_answer)
                self._send({"cursor": cursor, "events": events, "partial": partial, "auto": auto_answer})
            elif url.path == "/api/ollama":
                self._send(on_ollama())
            elif url.path == "/api/recent":
                cursor, events = store.recent((TRANSCRIPT, REQUEST), int(query.get("last", 30)))
                self._send({"cursor": cursor, "events": events, "pending": store.pending_requests()})
            else:
                self._send({"error": "not found"}, 404)

        def do_POST(self):
            if self._refused():
                return
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
                        fields = ("provider", "model", "effort", "ollama_model")
                        return self._send(on_copilot(**{key: body.get(key) for key in fields}))
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
