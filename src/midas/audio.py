"""Audio sources that yield 16 kHz mono float32 chunks of 100 ms."""

import json
import logging
import subprocess
import tempfile
import threading
import time
import wave
from collections.abc import Iterator
from pathlib import Path

import numpy as np

from .config import BIN_DIR

SAMPLE_RATE = 16000
CHUNK_SAMPLES = SAMPLE_RATE // 10
LISTENING = "listening"
# Shown after 20 s of pure silence; the daemon clears it as soon as sound arrives.
SILENT_STATUS = "listening · no sound right now"
WAITING = "waiting for a call"
# What Midas listens to: "auto" (whichever app is in a call), "all" (everything the Mac
# plays) or one app's bundle ID.
AUTO, ALL = "auto", "all"
# Listening to a browser means listening to every tab in it, which the panel says.
BROWSERS = {
    "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.apple.Safari",
    "com.apple.SafariTechnologyPreview", "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser",
    "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "org.chromium.Chromium",
}  # fmt: skip

log = logging.getLogger("midas.audio")


def list_apps() -> list[dict]:
    """The apps using audio, those in a call first, from bin/midas-audio --list."""
    binary = BIN_DIR / "midas-audio"
    try:
        done = subprocess.run([str(binary), "--list"], capture_output=True, text=True, timeout=10, check=True)
        apps = json.loads(done.stdout)
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        log.warning("couldn't list the apps using audio: %s", error)
        return []
    return [{**app, "browser": app.get("bundle") in BROWSERS} for app in apps]


class SystemAudio:
    """Runs the native Core Audio tap (bin/midas-audio) and restarts it if it dies.

    listen_to: AUTO, ALL or a bundle ID. With an app (or AUTO), midas-audio taps only that
    app, and only while it is in a call."""

    def __init__(self, listen_to: str = AUTO, on_status=None, on_source=None):
        self.binary = BIN_DIR / "midas-audio"
        self.listen_to = listen_to
        self.on_status = on_status or (lambda text: None)
        self.on_source = on_source or (lambda source: None)
        self._proc: subprocess.Popen | None = None
        self._switching = False
        self._report(app="", name="", state=ALL if listen_to == ALL else "waiting")

    def listen(self, listen_to: str):
        """Switches to another app (or AUTO, or ALL) at once."""
        if listen_to == self.listen_to:
            return
        self.listen_to = listen_to
        self._switching = True
        self._report(app="", name="", state=ALL if listen_to == ALL else "waiting")
        self.close()

    def _report(self, **source):
        self.source = {"listen_to": self.listen_to, **source, "browser": source.get("app") in BROWSERS}
        self.on_source(self.source)

    def chunks(self, stop: threading.Event) -> Iterator[np.ndarray]:
        if not self.binary.exists():
            raise FileNotFoundError(f"{self.binary} is missing; run ./midas setup first")
        backoff = 1.0
        while not stop.is_set():
            command = [str(self.binary), "--rate", str(SAMPLE_RATE)]
            if self.listen_to != ALL:
                command += ["--app", self.listen_to]
            self._proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            threading.Thread(target=self._pump_stderr, args=(self._proc,), daemon=True).start()
            started = time.monotonic()
            while not stop.is_set():
                data = self._proc.stdout.read(CHUNK_SAMPLES * 2)
                if not data:
                    break
                yield np.frombuffer(data, dtype=np.int16).astype(np.float32) / 32768.0
            self.close()
            if stop.is_set():
                return
            if self._switching:
                self._switching = False
                continue
            backoff = 1.0 if time.monotonic() - started > 30 else min(backoff * 2, 15.0)
            log.warning("midas-audio stopped, restarting in %.0f s", backoff)
            self.on_status("restarting audio capture")
            stop.wait(backoff)

    def close(self):
        if self._proc and self._proc.poll() is None:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self._proc.kill()

    def _pump_stderr(self, proc: subprocess.Popen):
        for raw in proc.stderr:
            line = raw.decode(errors="replace").strip()
            log.info(line)
            if line.startswith("[midas-audio] app: "):
                # "app: us.zoom.xos zoom.us": the tap now follows this app's call.
                bundle, _, name = line.removeprefix("[midas-audio] app: ").partition(" ")
                self._report(app=bundle, name=name or bundle, state="listening")
                self.on_status(LISTENING)
            elif line.startswith("[midas-audio] waiting: ") or line.startswith("[midas-audio] stopped: "):
                self._report(app="", name="", state="waiting")
                self.on_status(WAITING)
            elif "silence:" in line:
                # A missing permission is reported as an error line instead.
                self.on_status(SILENT_STATUS)
            elif "ready" in line:
                self.on_status(LISTENING)
            elif "error" in line:
                self.on_status("audio capture error: " + line.split("error:", 1)[-1].strip())


class FileAudio:
    """Plays an audio file into the pipeline in real time (for testing without a meeting)."""

    def __init__(self, path: str, realtime: bool = True):
        self.path = Path(path)
        self.realtime = realtime

    def chunks(self, stop: threading.Event) -> Iterator[np.ndarray]:
        samples = self._load()
        log.info("playing file: %s (%.1f s)", self.path.name, len(samples) / SAMPLE_RATE)
        for start in range(0, len(samples), CHUNK_SAMPLES):
            if stop.is_set():
                return
            yield samples[start : start + CHUNK_SAMPLES]
            if self.realtime:
                time.sleep(CHUNK_SAMPLES / SAMPLE_RATE)
        log.info("file finished; continuing with silence")
        silence = np.zeros(CHUNK_SAMPLES, dtype=np.float32)
        while not stop.is_set():
            yield silence
            time.sleep(CHUNK_SAMPLES / SAMPLE_RATE)

    def close(self):
        pass

    def _load(self) -> np.ndarray:
        # afconvert ships with macOS and decodes anything Core Audio can play.
        with tempfile.TemporaryDirectory() as tmp:
            wav_path = Path(tmp) / "input.wav"
            subprocess.run(
                ["afconvert", "-f", "WAVE", "-d", f"LEI16@{SAMPLE_RATE}", "-c", "1", str(self.path), str(wav_path)],
                check=True,
                capture_output=True,
            )
            with wave.open(str(wav_path), "rb") as wav:
                frames = wav.readframes(wav.getnframes())
        return np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
