"""Thread-safe event log shared by the transcriber, the HTTP API and the session file.

Event ids are consecutive from 1, so "everything after cursor N" is events[N:].
"""

import threading
import time
from datetime import datetime
from pathlib import Path

TRANSCRIPT = "transcript"
ANSWER = "answer"
REQUEST = "request"


class Store:
    def __init__(self, session_file: Path):
        self.session_file = session_file
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
        session_file.parent.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%d.%m.%Y %H:%M")
        session_file.write_text(f"# Midas meeting log — {stamp}\n\n", encoding="utf-8")

    def add(self, kind: str, text: str, title: str = "") -> dict:
        now = time.time()
        with self._cond:
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
            self._cond.notify_all()
        self._append_to_file(event)
        return event

    def update(self, **fields):
        with self._cond:
            for key, value in fields.items():
                setattr(self, key, value)
            self._cond.notify_all()

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

    def snapshot(self) -> dict:
        with self._cond:
            answers = [e for e in self._events if e["kind"] == ANSWER]
            requests = [e for e in self._events if e["kind"] == REQUEST]
            transcript = [e for e in self._events if e["kind"] == TRANSCRIPT]
            if self.claude_waiting:
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
                "transcript": transcript[-8:],
                "answers": answers[-15:],
                "session_file": self.session_file.name,
                "copilot": self.copilot,
            }

    def _append_to_file(self, event: dict):
        if event["kind"] == TRANSCRIPT:
            line = f"**[{event['time']}]** {event['text']}\n\n"
        elif event["kind"] == ANSWER:
            body = event["text"].replace("\n", "\n> ")
            line = f"> **Midas · {event['title'] or 'suggestion'}** ({event['time']})\n> {body}\n\n"
        else:
            line = f"**[{event['time']}] You → Claude:** {event['text'] or '(Answer pressed)'}\n\n"
        with self.session_file.open("a", encoding="utf-8") as handle:
            handle.write(line)
