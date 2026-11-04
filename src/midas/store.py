"""Thread-safe event log shared by the transcriber, the HTTP API and the session file.

Event ids are consecutive from 1, so "everything after cursor N" is events[N:].
"""

import logging
import threading
import time
from collections import deque
from datetime import datetime
from pathlib import Path

TRANSCRIPT = "transcript"
ANSWER = "answer"
REQUEST = "request"
# Where the user went off the record (paused) and back; nothing is transcribed in between.
MARKER = "marker"
OFF_THE_RECORD = "Off the record"
BACK_ON_THE_RECORD = "Back on the record"

log = logging.getLogger("midas")


class Store:
    def __init__(self, session_file: Path):
        self.session_file = session_file
        # Identifies this run, so the panel notices a restarted daemon (ids start at 1 again).
        self.started = time.time()
        self._cond = threading.Condition()
        self._events: list[dict] = []
        self.partial = ""
        self.speaking = False
        self.paused = False
        self.status = "starting"
        self.last_final_at = 0.0
        self.claude_seen_at = 0.0
        self.claude_waiting = 0
        # Set when the daemon runs the copilot itself, so the panel can offer the choice.
        self.copilot: dict | None = None
        # A copilot that reports its own state (the local Ollama one); None means Claude,
        # whose state follows from its waits.
        self.copilot_state: str | None = None
        # The answer as it is being written, for copilots that stream it.
        self.draft = ""
        # The privacy settings the panel shows (see privacy.panel_privacy).
        self.privacy: dict = {}
        # Seconds from a request to its answer, per copilot, for /api/health.
        self._latencies: deque[tuple[str, float]] = deque(maxlen=500)
        session_file.parent.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%d.%m.%Y %H:%M")
        session_file.write_text(f"# Midas meeting log — {stamp}\n\n", encoding="utf-8")

    def add(self, kind: str, text: str, title: str = "") -> dict:
        now = time.time()
        with self._cond:
            if kind == ANSWER:
                self._measure(now)
            event = {
                "id": len(self._events) + 1,
                "ts": now,
                "time": datetime.fromtimestamp(now).strftime("%H:%M:%S"),
                "kind": kind,
                "text": text,
                "title": title,
            }
            self._events.append(event)
            if kind == TRANSCRIPT:
                self.last_final_at = now
                self.partial = ""
            elif kind == ANSWER:
                self.draft = ""
            self._cond.notify_all()
        self._append_to_file(event)
        return event

    def _measure(self, now: float):
        """Records how long the oldest unanswered request waited for this answer."""
        last_answer = max((e["id"] for e in self._events if e["kind"] == ANSWER), default=0)
        asked = next((e["ts"] for e in self._events if e["kind"] == REQUEST and e["id"] > last_answer), None)
        if asked is None:
            return  # an answer nobody asked for (auto_answer)
        provider = (self.copilot or {}).get("provider", "claude")
        self._latencies.append((provider, now - asked))
        log.info("answered in %.1f s (%s)", now - asked, provider)

    def latency(self) -> dict:
        """Median and 95th percentile seconds from request to answer, per copilot."""
        with self._cond:
            samples = list(self._latencies)
        summary = {}
        for provider in sorted({p for p, _ in samples}):
            values = sorted(s for p, s in samples if p == provider)
            rank = lambda q: values[min(len(values) - 1, round(q * (len(values) - 1)))]  # noqa: E731
            summary[provider] = {"answers": len(values), "p50": round(rank(0.5), 2), "p95": round(rank(0.95), 2)}
        return summary

    def set_paused(self, paused: bool):
        """Going off the record stops transcription; the timeline and the log mark where."""
        with self._cond:
            changed = paused != self.paused
            self.paused = paused
            self.partial = ""
            self._cond.notify_all()
        if changed:
            self.add(MARKER, OFF_THE_RECORD if paused else BACK_ON_THE_RECORD)

    def update(self, **fields):
        with self._cond:
            for key, value in fields.items():
                setattr(self, key, value)
            self._cond.notify_all()

    def conversation(self) -> tuple[list[dict], str]:
        """Every event so far and the sentence still being spoken."""
        with self._cond:
            return list(self._events), self.partial

    def recent(self, kinds: tuple[str, ...], limit: int) -> tuple[int, list[dict]]:
        with self._cond:
            matching = [e for e in self._events if e["kind"] in kinds]
            return len(self._events), matching[-limit:] if limit > 0 else []

    def pending_requests(self) -> list[dict]:
        """Requests made after the last answer, e.g. while the copilot was restarting."""
        with self._cond:
            last_answer = max((e["id"] for e in self._events if e["kind"] == ANSWER), default=0)
            return [e for e in self._events if e["kind"] == REQUEST and e["id"] > last_answer]

    def wait(self, cursor: int, timeout: float, auto: bool, settle: float = 0.6) -> tuple[int, list[dict], str]:
        """Long-poll for transcript lines and user requests after `cursor`.

        On demand (auto=False) it returns only when the user asks for an answer, with
        everything said since the last delivery; a timeout consumes nothing. With auto
        it also returns once new speech has settled (nobody talking for `settle` s).
        The in-progress utterance is returned too, so a question still being
        transcribed when the user presses the button isn't missed.
        """
        deadline = time.monotonic() + timeout
        with self._cond:
            self.claude_waiting += 1
            try:
                while True:
                    fresh = [e for e in self._events[cursor:] if e["kind"] in (TRANSCRIPT, REQUEST)]
                    remaining = deadline - time.monotonic()
                    if any(e["kind"] == REQUEST for e in fresh):
                        break
                    if auto and fresh and not self.speaking and time.time() - self.last_final_at >= settle:
                        break
                    if remaining <= 0:
                        if not auto:
                            return cursor, [], ""
                        break
                    self._cond.wait(min(0.25, remaining))
            finally:
                self.claude_waiting -= 1
                self.claude_seen_at = time.time()
            return len(self._events), fresh, self.partial

    def snapshot(self, since: int = 0) -> dict:
        """Panel state plus every event after id `since`, so the panel can keep the full
        timeline while fetching only what is new."""
        with self._cond:
            answers = [e for e in self._events if e["kind"] == ANSWER]
            requests = [e for e in self._events if e["kind"] == REQUEST]
            if self.copilot_state:
                claude = self.copilot_state
            elif self.claude_waiting:
                claude = "ready"
            elif time.time() - self.claude_seen_at < 120:
                claude = "thinking"
            else:
                claude = "offline"
            pending = bool(requests) and (not answers or requests[-1]["id"] > answers[-1]["id"])
            return {
                "status": self.status,
                "paused": self.paused,
                "speaking": self.speaking,
                "claude": claude,
                "pending_request": pending,
                "partial": self.partial,
                "draft": self.draft,
                "session_file": self.session_file.name,
                "copilot": self.copilot,
                "privacy": self.privacy,
                "session": self.started,
                "count": len(self._events),
                "events": self._events[max(since, 0) :],
            }

    def _append_to_file(self, event: dict):
        if event["kind"] == TRANSCRIPT:
            line = f"**[{event['time']}]** {event['text']}\n\n"
        elif event["kind"] == ANSWER:
            body = event["text"].replace("\n", "\n> ")
            line = f"> **Midas · {event['title'] or 'suggestion'}** ({event['time']})\n> {body}\n\n"
        elif event["kind"] == MARKER:
            line = f"*[{event['time']}] {event['text']}.*\n\n"
        else:
            line = f"**[{event['time']}] You → Claude:** {event['text'] or '(Answer pressed)'}\n\n"
        with self.session_file.open("a", encoding="utf-8") as handle:
            handle.write(line)
