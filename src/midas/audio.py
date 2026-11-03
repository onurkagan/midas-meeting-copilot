"""Audio sources that yield 16 kHz mono float32 chunks of 100 ms."""

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

log = logging.getLogger("midas.audio")


class SystemAudio:
    """Runs the native Core Audio tap (bin/midas-audio) and restarts it if it dies."""

    def __init__(self, on_status=None):
        self.binary = BIN_DIR / "midas-audio"
        self.on_status = on_status or (lambda text: None)
        self._proc: subprocess.Popen | None = None

    def chunks(self, stop: threading.Event) -> Iterator[np.ndarray]:
        if not self.binary.exists():
            raise FileNotFoundError(f"{self.binary} is missing; run ./midas setup first")
        backoff = 1.0
        while not stop.is_set():
            self._proc = subprocess.Popen(
                [str(self.binary), "--rate", str(SAMPLE_RATE)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
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
            if "silence:" in line:
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
