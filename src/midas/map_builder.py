"""Keeps the meeting map current: a model reads what was said since its last pass and
proposes new map items (meeting_map.py checks and adds them).

With a local model (Ollama) the map follows the meeting by itself. Claude reads the meeting
only when the user asks for something (Answer, Summary, Update map, Save map), as the panel
promises, unless auto_answer already lets it read along.
"""

import json
import logging
import os
import shutil
import subprocess
import threading
import time
from collections.abc import Callable
from tempfile import gettempdir

from .config import CLAUDE_MODELS, Config
from .conversation import marker_note, user_context
from .meeting_map import MeetingMap
from .ollama import Ollama, OllamaError
from .store import ANSWER, MARKER, TRANSCRIPT, Store, speaker_label

log = logging.getLogger("midas.map")

SYSTEM = """\
You keep a map of a meeting for the user: its topics and, under each topic, the questions \
put to the user, the answers Midas suggested to them, decisions, action items, risks and \
open questions. Lines marked Others are the other participants (the meeting app's audio); \
lines marked You are the user, from their microphone, when it is on and not muted. Every line \
starts with its id in brackets.

You get the map so far and the lines said since your last look. Return only what is NEW:
- topics: new topics, 2 to 4 words, each with a key you choose and the ids of the lines \
where it starts. Prefer an existing topic (by its id); a meeting rarely has more than 7.
- items: new items. Each has a type, its topic (an existing topic id or a new topic's key), \
a label of at most 7 words, and the ids of the lines it rests on. A topic marked "from the \
last meeting" only holds what that meeting left open: put new items under this meeting's \
own topics. Types:
  question: a question put to the user, or to everyone, that needs an answer. Give it a key.
  answer: a line marked "Midas suggested" that answers a question; set "answers" to that \
question's id or key. Skip summaries, explanations and other suggestions.
  decision: something the participants agreed on.
  action: a task someone took on. owner: the name as said in the meeting ("You" for a task \
the user took on in a You line), else empty. \
due: as said ("Thursday"), else empty.
  risk: a concern or something that could go wrong.
  open_question: a question the meeting left open.
- updates: changes to existing items by id, when later lines change them (a new due date, \
a clearer label). This includes the items from the last meeting: when a line says one \
slipped or got a new date, update it instead of adding it again.
- links: pairs of item ids (or keys) about the same issue under different topics.
- title: a name for the meeting, at most 4 words, only if the map has none yet.

Only include what the lines say, and cite at least one line id for every item. Don't repeat \
what is already on the map. Write labels in the language of the meeting. When nothing new \
happened, return empty lists."""

SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "topics": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "key": {"type": "string"},
                    "label": {"type": "string"},
                    "source": {"type": "array", "items": {"type": "integer"}},
                },
                "required": ["key", "label", "source"],
            },
        },
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "type": {"type": "string", "enum": ["question", "answer", "decision", "action", "risk", "open_question"]},
                    "topic": {"type": "string"},
                    "label": {"type": "string"},
                    "source": {"type": "array", "items": {"type": "integer"}},
                    "key": {"type": "string"},
                    "answers": {"type": "string"},
                    "owner": {"type": "string"},
                    "due": {"type": "string"},
                },
                "required": ["type", "topic", "label", "source"],
            },
        },
        "updates": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "string"},
                    "label": {"type": "string"},
                    "owner": {"type": "string"},
                    "due": {"type": "string"},
                },
                "required": ["id"],
            },
        },
        "links": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"from": {"type": "string"}, "to": {"type": "string"}},
                "required": ["from", "to"],
            },
        },
    },
    "required": ["topics", "items", "updates", "links"],
}

# Lines before the new ones, so a decision can be read with the question it settles.
CONTEXT_LINES = 6
CHARS_PER_TOKEN = 3
CLAUDE_CHUNK_CHARS = 60_000


class MapError(Exception):
    """Why the map couldn't be updated, worded for the panel."""


def line(event: dict) -> str:
    if event["kind"] == ANSWER:
        return f"[{event['id']}] {event['time']} (Midas suggested to the user: {' '.join(event['text'].split())})"
    if event["kind"] == MARKER:
        return f"[{event['id']}] {marker_note(event)}"
    return f"[{event['id']}] {event['time']} {speaker_label(event)}: {event['text']}"


def build_prompt(outline: str, earlier: list[dict], fresh: list[dict], context: str) -> str:
    parts = []
    if context not in ("(none)", "(template not filled in)"):
        parts.append(f"The user's notes (who they are, the agenda):\n{context[:2000]}")
    parts.append(f"The map so far:\n{outline}")
    if earlier:
        parts.append("Earlier lines, already read (context only):\n" + "\n".join(map(line, earlier)))
    parts.append("New lines:\n" + "\n".join(map(line, fresh)))
    return "\n\n".join(parts)


class ClaudeMap:
    """One `claude -p` call per pass, with no tools and a JSON schema for the reply."""

    def __init__(self, command: str, model: str):
        self.command = command
        self.model = CLAUDE_MODELS.get(model, model)
        self.chunk_chars = CLAUDE_CHUNK_CHARS
        self.name = "Claude"

    def ops(self, prompt: str, abort: Callable[[], bool]) -> dict:
        claude = shutil.which(self.command)
        if not claude:
            raise MapError(f"'{self.command}' wasn't found, so Claude can't update the map.")
        command = [
            claude, "-p", "--model", self.model, "--effort", "low",
            "--system-prompt", SYSTEM, "--tools", "", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
            "--no-session-persistence", "--output-format", "json", "--json-schema", json.dumps(SCHEMA),
        ]  # fmt: skip
        environment = {**os.environ, "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"}
        try:
            # Outside the project folder, so no project instructions are read along.
            done = subprocess.run(
                command, input=prompt, capture_output=True, text=True, timeout=180, cwd=gettempdir(), env=environment
            )
        except subprocess.TimeoutExpired as error:
            raise MapError("Claude took too long to update the map.") from error
        try:
            result = json.loads(done.stdout)
        except json.JSONDecodeError as error:
            raise MapError(f"Claude couldn't update the map: {(done.stderr or done.stdout).strip()[:200]}") from error
        if result.get("is_error") or not isinstance(result.get("structured_output"), dict):
            raise MapError(f"Claude couldn't update the map: {str(result.get('result'))[:200]}")
        return result["structured_output"]


class OllamaMap:
    """A local model with Ollama's structured output. It steps aside when the user asks
    for an answer: the answer matters more than the map."""

    def __init__(self, ollama: Ollama, model: str, context: int):
        self.ollama = ollama
        self.model = model
        self.context = context
        self.chunk_chars = max(context - 2500, 1500) * CHARS_PER_TOKEN
        self.name = "Ollama"

    def ops(self, prompt: str, abort: Callable[[], bool]) -> dict:
        if not self.model:
            raise MapError("Pick a local model in ⚙︎ to build the map.")
        messages = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": prompt}]
        try:
            return self.ollama.structured(self.model, messages, SCHEMA, self.context, abort)
        except OllamaError as error:
            raise MapError(str(error)) from error


class MapBuilder:
    """Runs map passes in the background: when asked, after each answer, and with a local
    model also as the meeting goes."""

    def __init__(self, store: Store, config: Config, meeting_map: MeetingMap, settings: Callable[[], dict]):
        self.store = store
        self.config = config
        self.map = meeting_map
        self.settings = settings
        self._wake = threading.Event()
        self._save = threading.Event()
        self._last_pass = 0.0
        self._answers_seen = 0
        # A pass and a switch to a new meeting's map never overlap.
        self._lock = threading.Lock()
        self._publish()

    def new_meeting(self, meeting_map: MeetingMap):
        """A new meeting gets its own map, which reads from the meeting's first line; the
        last one stays saved beside its log."""
        with self._lock:
            meeting_map.cursor = self.store.meeting_start
            self.map = meeting_map
            self._publish()

    # Called from the API -----------------------------------------------------------------

    def update(self):
        self._wake.set()

    def export(self):
        self._save.set()
        self._wake.set()

    def document(self, kind: str):
        """The map to share, as "md" or "html", written beside the meeting log."""
        with self._lock:
            path = self.map.document(kind)
        log.info("map exported: %s", path.name)
        return path

    def set(self, node_id: str, **flags) -> bool:
        changed = self.map.set(node_id, **flags)
        if changed:
            self._written()
        return changed

    def remove(self, node_id: str) -> bool:
        removed = self.map.remove(node_id)
        if removed:
            self._written()
        return removed

    # The loop ------------------------------------------------------------------------------

    def run(self, stop: threading.Event):
        while not stop.is_set():
            asked = self._wake.wait(5)
            self._wake.clear()
            try:
                with self._lock:
                    if asked or self._answered() or self._due():
                        self._pass()
                    if self._save.is_set():
                        self._save.clear()
                        self._export()
            except Exception:
                log.exception("map pass failed")
                self._state("error: the map couldn't be updated")

    def _provider(self) -> str:
        if self.config.local_only:
            return "ollama"
        return self.settings().get("provider") or self.config.provider

    def _model(self):
        if self._provider() == "ollama":
            model = self.settings().get("ollama_model") or self.config.ollama_model
            return OllamaMap(Ollama(self.config.ollama_url, self.config.ollama_keep_alive), model, self.config.ollama_context)
        return ClaudeMap(self.config.claude_command, self.config.map_model)

    def _reads_along(self) -> bool:
        """Whether the map may follow the meeting without being asked."""
        return self._provider() == "ollama" or self.config.auto_answer

    def _answered(self) -> bool:
        """A new answer from the copilot: the user asked, so the map catches up too."""
        events, _ = self.store.conversation()
        answers = sum(1 for e in events if e["kind"] == ANSWER)
        new, self._answers_seen = answers > self._answers_seen, answers
        return new

    def _due(self) -> bool:
        if not self.config.map_live or not self._reads_along() or self.store.paused:
            return False
        if time.monotonic() - self._last_pass < self.config.map_interval_s:
            return False
        events, _ = self.store.conversation()
        fresh = [e for e in events[self.map.cursor :] if e["kind"] == TRANSCRIPT]
        return len(fresh) >= 3 and not self.store.speaking

    def _busy(self) -> bool:
        """An answer is being asked for or written: a local map pass waits."""
        return bool(self.store.pending_requests()) or self.store.copilot_state == "thinking"

    def _pass(self):
        events, _ = self.store.conversation()
        fresh = [e for e in events[self.map.cursor :] if e["kind"] in (TRANSCRIPT, ANSWER, MARKER)]
        if not any(e["kind"] in (TRANSCRIPT, ANSWER) for e in fresh):
            return
        model = self._model()
        if isinstance(model, OllamaMap) and self._busy():
            self._wake.set()  # try again once the answer is out
            time.sleep(1)
            return
        by_id = {e["id"]: e for e in events}
        self._state("updating")
        started = time.monotonic()
        abort = (lambda: self._busy()) if isinstance(model, OllamaMap) else (lambda: False)
        try:
            while fresh:
                chunk, size = [], 0
                for event in fresh:
                    size += len(line(event)) + 1
                    if chunk and size > model.chunk_chars:
                        break
                    chunk.append(event)
                fresh = fresh[len(chunk) :]
                before = events[self.store.meeting_start : chunk[0]["id"] - 1]
                earlier = [e for e in before if e["kind"] in (TRANSCRIPT, ANSWER)][-CONTEXT_LINES:]
                prompt = build_prompt(self.map.outline(), earlier, chunk, user_context())
                ops = model.ops(prompt, abort)
                if ops is None:  # stepped aside for an answer
                    self._wake.set()
                    self._state("idle")
                    return
                last = chunk[-1]["id"]
                # Requests after the last line read don't hold the map back.
                changes = self.map.apply(ops, by_id, last)
                log.info("map: %d change(s) from %s (lines up to %d)", changes, model.name, last)
        except MapError as error:
            log.warning("map: %s", error)
            self._state(f"error: {error}")
            return
        finally:
            self._last_pass = time.monotonic()
        log.info("map updated in %.1f s", time.monotonic() - started)
        self._state("idle")
        self._written()

    def _export(self):
        paths = self.map.export()
        log.info("map saved: %s", ", ".join(p.name for p in paths))
        self._publish()

    def _written(self):
        if self.map.nodes:
            self.map.save()
        self._publish()

    def _state(self, state: str):
        self.map.state = state
        self._publish()

    def _publish(self):
        live = self.config.map_live and self._reads_along()
        self.store.update(map_info={**self.map.summary(), "live": live})
