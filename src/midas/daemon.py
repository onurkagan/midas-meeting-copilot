"""The Midas daemon: audio -> VAD -> Whisper -> store, plus the API and the overlay."""

import json
import logging
import os
import shutil
import signal
import subprocess
import threading
import time
from collections import deque
from datetime import datetime

from . import api
from .audio import LISTENING, SILENT_STATUS, FileAudio, SystemAudio
from .config import (
    BIN_DIR, CLAUDE_EFFORTS, CLAUDE_MODELS, COPILOT_FILE, COPILOT_PROVIDERS, LOGS_DIR, PID_FILE, ROOT,
    SESSIONS_DIR, Config,
)  # fmt: skip
from .local_copilot import LocalCopilot
from .map_builder import MapBuilder
from .meeting_map import MeetingMap
from .ollama import Ollama, OllamaError
from .privacy import panel_privacy, prune_sessions
from .prompt import SYSTEM_PROMPT, copilot_prompt
from .segmenter import Segment, Segmenter
from .store import TRANSCRIPT, Store
from .transcriber import Transcriber

log = logging.getLogger("midas")


class Daemon:
    def __init__(self, config: Config, input_file: str | None = None, copilot: bool = False):
        self.config = config
        self.copilot = copilot
        self._claude: subprocess.Popen | None = None
        self.stop = threading.Event()
        prune_sessions(SESSIONS_DIR, config.keep_sessions_days)
        session = SESSIONS_DIR / f"{datetime.now():%Y-%m-%d_%H-%M}.md"
        self.store = Store(session, window_s=config.recent_minutes * 60)
        self.store.privacy = panel_privacy(config)
        self.source = FileAudio(input_file) if input_file else SystemAudio(on_status=self._audio_status)
        self.transcriber = Transcriber(config.model, config.languages, config.vocabulary)
        self.segmenter = Segmenter(
            silence_ms=config.silence_ms,
            max_segment_s=config.max_segment_s,
            partial_every_s=1.0 if config.partials else 0,
            on_speaking=lambda speaking: self.store.update(speaking=speaking),
        )
        self._jobs = threading.Condition()
        self._finals: deque[Segment] = deque()
        self._partial: Segment | None = None
        self._ready = threading.Event()
        self._overlay: subprocess.Popen | None = None
        self._restart_claude = threading.Event()
        self._settings = threading.Lock()
        self._ollama = Ollama(config.ollama_url, config.ollama_keep_alive)
        if copilot:
            settings = {
                "provider": config.provider,
                "model": config.claude_model,
                "effort": config.claude_effort,
                "ollama_model": config.ollama_model,
            }
            if COPILOT_FILE.exists():
                settings.update(json.loads(COPILOT_FILE.read_text()))
            if config.local_only:
                settings["provider"] = "ollama"
            self.store.copilot = settings
        self.map = MeetingMap(session)
        if carried := self.map.carry_over(SESSIONS_DIR, config.carry_over_days):
            log.info("map: %d open item(s) carried over from the last meeting", carried)
        self.map_builder = MapBuilder(self.store, config, self.map, lambda: self.store.copilot or {})

    def run(self):
        try:
            server = api.serve(
                self.store, self.config.host, self.config.port,
                on_quit=self.stop.set, on_copilot=self.set_copilot, on_ollama=self.ollama_models,
                auto_answer=self.config.auto_answer, map_builder=self.map_builder,
            )  # fmt: skip
        except OSError:
            log.error("Port %d is in use; Midas may already be running (./midas stop)", self.config.port)
            raise SystemExit(1)
        PID_FILE.parent.mkdir(parents=True, exist_ok=True)
        PID_FILE.write_text(str(os.getpid()))
        for signum in (signal.SIGINT, signal.SIGTERM):
            signal.signal(signum, lambda *_: self.stop.set())

        self._start_overlay()
        threading.Thread(target=self._transcribe_loop, name="whisper", daemon=True).start()
        threading.Thread(target=self._audio_loop, name="audio", daemon=True).start()
        if self.copilot:
            threading.Thread(target=self._copilot_loop, name="copilot", daemon=True).start()
        threading.Thread(target=self.map_builder.run, args=(self.stop,), name="map", daemon=True).start()
        log.info("session log: %s", self.store.session_file)

        while not self.stop.wait(1.0):
            if self._overlay and self._overlay.poll() is not None:
                log.info("overlay closed")
                self._overlay = None

        log.info("shutting down")
        self.source.close()
        server.shutdown()
        for child in (self._overlay, self._claude):
            if child and child.poll() is None:
                child.terminate()
        PID_FILE.unlink(missing_ok=True)

    def _provider(self) -> str:
        return (self.store.copilot or {}).get("provider", "claude")

    def _copilot_loop(self):
        """Runs the copilot the user chose (Claude or a local Ollama model), switching when
        they choose the other one in the panel."""
        while not self._ready.wait(1):
            if self.stop.is_set():
                return
        while not self.stop.is_set():
            provider = self._provider()

            def active(provider=provider) -> bool:
                return not self.stop.is_set() and self._provider() == provider

            if provider == "ollama":
                LocalCopilot(self.store, self.config, active, lambda name: self.set_copilot(ollama_model=name)).run()
            else:
                self._run_claude(active)

    def _run_claude(self, active):
        """Keeps a headless Claude Code session running the /midas loop, restarting it if it ends."""
        claude = shutil.which(self.config.claude_command)
        if not claude:
            log.error("'%s' not found; cannot start the Claude Code copilot", self.config.claude_command)
            self.store.update(copilot_state="missing")
            while active():
                self.stop.wait(1)
            self.store.update(copilot_state=None)
            return
        mcp_config = {
            "mcpServers": {
                "midas": {
                    "command": str(ROOT / "midas"),
                    "args": ["mcp"],
                    "env": {"MIDAS_WAIT_SECONDS": str(self.config.idle_wait_s)},
                }
            }
        }
        # Only the midas tools and a short system prompt: every call re-reads this context,
        # and Claude Code's defaults would make it ~35k tokens instead of ~3k.
        command = [
            claude, "-p", copilot_prompt(),
            "--system-prompt", SYSTEM_PROMPT,
            "--tools", "",
            "--mcp-config", json.dumps(mcp_config), "--strict-mcp-config",
            "--allowedTools", "mcp__midas",
            # The meeting stays in sessions/ only, not in Claude Code's own history too.
            "--no-session-persistence",
        ]  # fmt: skip
        environment = {
            **os.environ,
            "MCP_TOOL_TIMEOUT": str((self.config.idle_wait_s + 300) * 1000),
            "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
        }
        backoff = 5.0
        while active():
            started = time.monotonic()
            settings = self.store.copilot
            model = CLAUDE_MODELS.get(settings["model"], settings["model"])
            options = ["--model", model, "--effort", settings["effort"]]
            with (LOGS_DIR / "claude.log").open("a") as output:
                self._claude = subprocess.Popen(
                    command + options, cwd=ROOT, env=environment,
                    stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                )  # fmt: skip
                log.info("Claude Code copilot started (%s, effort %s)", settings["model"], settings["effort"])
                while self._claude.poll() is None and not self.stop.wait(1):
                    pass
            if not active():
                return
            if self._restart_claude.is_set():
                self._restart_claude.clear()
                continue
            backoff = 5.0 if time.monotonic() - started > 120 else min(backoff * 2, 120.0)
            log.warning("Claude Code session ended (code %s), restarting in %.0f s", self._claude.returncode, backoff)
            deadline = time.monotonic() + backoff
            while active() and time.monotonic() < deadline:
                self.stop.wait(1)

    def set_copilot(
        self, provider: str | None = None, model: str | None = None, effort: str | None = None,
        ollama_model: str | None = None,
    ) -> dict:  # fmt: skip
        """The panel's choice of copilot, model and effort: saved, then the copilot
        restarts with it (or the other copilot takes over)."""
        if not self.copilot:
            raise ValueError("Midas does not manage the copilot in this mode")
        with self._settings:
            previous = self.store.copilot
            settings = {**previous}
            if provider:
                if provider not in COPILOT_PROVIDERS:
                    raise ValueError(f"provider must be one of: {', '.join(COPILOT_PROVIDERS)}")
                if provider != "ollama" and self.config.local_only:
                    raise ValueError("only local models may answer (local_only = true in config.toml)")
                settings["provider"] = provider
            if model:
                if model not in CLAUDE_MODELS:
                    raise ValueError(f"model must be one of: {', '.join(CLAUDE_MODELS)}")
                settings["model"] = model
            if effort:
                if effort not in CLAUDE_EFFORTS:
                    raise ValueError(f"effort must be one of: {', '.join(CLAUDE_EFFORTS)}")
                settings["effort"] = effort
            if ollama_model is not None:
                settings["ollama_model"] = str(ollama_model).strip()
            if settings == previous:
                return settings
            COPILOT_FILE.write_text(json.dumps(settings))
            self.store.update(copilot=settings)
            log.info("copilot: %s", settings)
            claude_changed = any(previous.get(key) != settings.get(key) for key in ("provider", "model", "effort"))
            if claude_changed and self._claude and self._claude.poll() is None:
                if settings["provider"] == "claude":
                    self._restart_claude.set()
                self._claude.terminate()
            return settings

    def ollama_models(self) -> dict:
        """The panel's list of local models to pick from."""
        try:
            return {"reachable": True, "url": self._ollama.url, "models": self._ollama.models()}
        except OllamaError as error:
            return {"reachable": False, "url": self._ollama.url, "models": [], "error": str(error)}

    def _audio_status(self, text: str):
        if self._ready.is_set():
            self.store.update(status=text)

    def _start_overlay(self):
        binary = BIN_DIR / "midas-overlay"
        if not self.config.overlay or not binary.exists():
            return
        self._overlay = subprocess.Popen(
            [str(binary), "--port", str(self.config.port), "--parent-pid", str(os.getpid()), "--root", str(ROOT)],
            stdout=subprocess.DEVNULL,
        )

    def _audio_loop(self):
        try:
            for chunk in self.source.chunks(self.stop):
                if self.store.status == SILENT_STATUS and chunk.any():
                    self.store.update(status=LISTENING)
                if self.store.paused:
                    if self.segmenter._active:
                        self.segmenter.reset()
                    continue
                for segment in self.segmenter.feed(chunk):
                    self._enqueue(segment)
        except Exception as error:
            log.exception("audio loop stopped")
            self.store.update(status=f"audio error: {error}")

    def _enqueue(self, segment: Segment):
        with self._jobs:
            if segment.kind == "final":
                self._finals.append(segment)
                if self._partial and self._partial.id <= segment.id:
                    self._partial = None
            else:
                self._partial = segment
            self._jobs.notify()

    def _transcribe_loop(self):
        self.store.update(status="loading model…")
        try:
            self.transcriber.load()
        except Exception as error:
            log.exception("could not load the Whisper model")
            self.store.update(status=f"model error: {error}")
            return
        self._ready.set()
        self.store.update(status=LISTENING)
        context = ""
        last_final_id = 0
        while not self.stop.is_set():
            with self._jobs:
                while not self._finals and not self._partial and not self.stop.is_set():
                    self._jobs.wait(0.5)
                if self._finals:
                    segment = self._finals.popleft()
                else:
                    segment, self._partial = self._partial, None
            if segment is None or (segment.kind == "partial" and segment.id <= last_final_id):
                continue
            try:
                text = self.transcriber.transcribe(segment.audio, final=segment.kind == "final", context=context)
            except Exception:
                log.exception("transcription error")
                continue
            if segment.kind == "final":
                last_final_id = segment.id
                if text:
                    self.store.add(TRANSCRIPT, text)
                    context = text
                    log.info("» %s", text)
                else:
                    self.store.update(partial="")
            elif text:
                self.store.update(partial=text)
