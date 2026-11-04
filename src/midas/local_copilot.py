"""The local copilot: a model in Ollama answers in the panel, streamed as it writes.
Nothing leaves the Mac, and no Claude Code is needed."""

import logging
import re
import time
from collections.abc import Callable

from .config import Config
from .conversation import EMPTY_REQUEST, marker_note, user_context
from .ollama import Ollama, OllamaError
from .prompt import local_system_prompt
from .store import ANSWER, MARKER, REQUEST, TRANSCRIPT, Store

log = logging.getLogger("midas.ollama")

# Reasoning some models write inline, closed or (while streaming) not yet.
THINKING = re.compile(r"<think>.*?(?:</think>|\Z)", re.DOTALL)
TITLE = re.compile(r"^\W*title\W*:\s*(.+)$", re.IGNORECASE)
TITLE_SO_FAR = re.compile(r"^\W*t(?:i(?:t(?:le?)?)?)?\W*$", re.IGNORECASE)
CHARS_PER_TOKEN = 3  # conservative, for Turkish as much as English
RESERVED_TOKENS = 1200  # system prompt, request and the answer itself


def split_reply(text: str, final: bool = True) -> tuple[str, str]:
    """(title, body) from "TITLE: …" followed by the reply. While streaming, a title line
    still being written shows as nothing rather than as the start of the answer."""
    text = THINKING.sub("", text).lstrip()
    first, newline, rest = text.partition("\n")
    if match := TITLE.match(first.strip()):
        if not newline and not final:
            return "", ""
        return match.group(1).strip(" *#\"'"), rest.strip()
    if not newline and not final and TITLE_SO_FAR.match(first.strip()):
        return "", ""
    return "", text.strip()


def build_messages(events: list[dict], partial: str, auto: bool, context_tokens: int) -> list[dict]:
    """The whole task in one message: the meeting so far, then what to do now. The
    transcript only grows at the end, so Ollama can reuse its cache between answers."""
    last_answer = max((e["id"] for e in events if e["kind"] == ANSWER), default=0)
    lines = []
    for event in events:
        if event["kind"] == TRANSCRIPT:
            lines.append(f"[{event['time']}] {event['text']}")
        elif event["kind"] == ANSWER:
            said = " ".join(event["text"].split())
            lines.append(f"[{event['time']}] (Midas suggested to the user: {said})")
        elif event["kind"] == MARKER:
            lines.append(marker_note(event))
    budget = max(context_tokens - RESERVED_TOKENS, 1000) * CHARS_PER_TOKEN
    while lines and sum(len(line) + 1 for line in lines) > budget:
        lines.pop(0)
    if len(lines) < sum(1 for e in events if e["kind"] in (TRANSCRIPT, ANSWER, MARKER)):
        lines.insert(0, "(earlier part of the meeting left out)")
    if partial:
        lines.append(f"[being said right now, unfinished] {partial}")

    requests = [e for e in events if e["kind"] == REQUEST and e["id"] > last_answer]
    if requests:
        task = "\n".join(f"USER REQUEST: {e['text'] or EMPTY_REQUEST}" for e in requests)
    elif auto:
        task = (
            "No request from the user. If the latest lines hold a question or request addressed "
            "to the user, write their reply. Otherwise answer with exactly: SKIP"
        )
    else:
        task = f"USER REQUEST: {EMPTY_REQUEST}"
    transcript = "\n".join(lines) or "(nothing has been said yet)"
    return [
        {"role": "system", "content": local_system_prompt(user_context())},
        {"role": "user", "content": f"Meeting transcript (other participants only):\n{transcript}\n\n{task}"},
    ]


class LocalCopilot:
    """Answers the panel's requests with an Ollama model until `active()` turns false."""

    def __init__(self, store: Store, config: Config, active: Callable[[], bool], choose_model: Callable[[str], None]):
        self.store = store
        self.config = config
        self.active = active
        self.choose_model = choose_model
        self.ollama = Ollama(config.ollama_url, config.ollama_keep_alive)
        self._loaded = ""

    @property
    def model(self) -> str:
        return (self.store.copilot or {}).get("ollama_model", "")

    def run(self):
        log.info("local copilot: Ollama at %s", self.ollama.url)
        cursor = len(self.store.conversation()[0])
        online, checked = False, 0.0
        try:
            while self.active():
                if time.monotonic() - checked > 5 or (online and self.model != self._loaded):
                    checked = time.monotonic()
                    online = self._prepare()
                if self.store.pending_requests():
                    self._answer()
                    continue
                cursor, fresh, _ = self.store.wait(cursor, 2.0, auto=self.config.auto_answer)
                if online and self.config.auto_answer and fresh and all(e["kind"] != REQUEST for e in fresh):
                    self._answer(auto=True)
        finally:
            self.store.update(copilot_state=None, draft="")

    def _prepare(self) -> bool:
        """Checks that Ollama is up, picks a model if none is chosen yet and loads it."""
        if not self.ollama.reachable():
            self._loaded = ""
            self.store.update(copilot_state="offline")
            return False
        if not self.model:
            try:
                models = self.ollama.models()
            except OllamaError:
                models = []
            if models:
                self.choose_model(models[0]["name"])
        if self.model and self.model != self._loaded:
            self.store.update(copilot_state="loading")
            started = time.monotonic()
            try:
                self.ollama.load(self.model)
                log.info("Ollama loaded %s in %.1f s", self.model, time.monotonic() - started)
            except OllamaError as error:
                log.warning("couldn't load %s: %s", self.model, error)
            self._loaded = self.model
        self.store.update(copilot_state="ready" if self.model else "no model")
        return True

    def _answer(self, auto: bool = False):
        model = self.model
        if not model:
            if not auto:
                self.store.add(
                    ANSWER, "Pull one in Terminal (for example `ollama pull llama3.2`), then pick it in ⚙︎.",
                    "No Ollama model yet")  # fmt: skip
            return
        events, partial = self.store.conversation()
        messages = build_messages(events, partial, auto, self.config.ollama_context)
        self.store.update(copilot_state="thinking", draft="")
        started, shown, text = time.monotonic(), 0.0, ""
        try:
            for piece in self.ollama.chat(model, messages, self.config.ollama_context):
                text += piece
                if time.monotonic() - shown > 0.15:
                    shown = time.monotonic()
                    self.store.update(draft=split_reply(text, final=False)[1])
        except OllamaError as error:
            log.warning("Ollama couldn't answer: %s", error)
            if not auto:
                self.store.add(ANSWER, str(error), "Ollama couldn't answer")
            self.store.update(copilot_state="ready", draft="")
            return
        title, body = split_reply(text)
        log.info("%s answered in %.1f s", model, time.monotonic() - started)
        if auto and (not body or body.upper().startswith("SKIP")):
            self.store.update(draft="")
        else:
            self.store.add(ANSWER, body or "(the model returned an empty answer)", title)
        self.store.update(copilot_state="ready")
