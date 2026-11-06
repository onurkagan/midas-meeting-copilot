"""Energy-based voice activity detection that cuts the stream into utterances."""

import time
from collections import deque
from dataclasses import dataclass, field

import numpy as np

from .audio import SAMPLE_RATE

FRAME = 480  # 30 ms
FRAME_S = FRAME / SAMPLE_RATE


@dataclass
class Segment:
    id: int
    kind: str  # "partial" while someone is still talking, "final" once they pause
    audio: np.ndarray
    speaker: str = "others"  # "others" (the call's audio) or "you" (the microphone)
    at: float = field(default_factory=time.time)  # when it was cut


class Segmenter:
    def __init__(
        self,
        silence_ms: int = 700,
        max_segment_s: float = 20.0,
        partial_every_s: float = 1.0,
        min_speech_ms: int = 250,
        preroll_ms: int = 300,
        on_speaking=None,
        speaker: str = "others",
    ):
        self.speaker = speaker
        self.silence_frames = max(1, int(silence_ms / 1000 / FRAME_S))
        # Whisper sees at most 30 s per pass, so utterances are cut before that.
        self.max_frames = int(min(max_segment_s, 28.0) / FRAME_S)
        self.partial_frames = int(partial_every_s / FRAME_S) if partial_every_s else 0
        self.min_voiced = int(min_speech_ms / 1000 / FRAME_S)
        self.on_speaking = on_speaking or (lambda speaking: None)
        self._preroll = deque(maxlen=int(preroll_ms / 1000 / FRAME_S))
        self._pending = np.zeros(0, dtype=np.float32)
        self._noise_db = -70.0
        self._onset = 0
        self._next_id = 1
        self.reset()

    def reset(self):
        self._frames: list[np.ndarray] = []
        self._levels: list[float] = []
        self._voiced = 0
        self._silence = 0
        self._since_partial = 0
        if getattr(self, "_active", False):
            self.on_speaking(False)
        self._active = False

    def feed(self, chunk: np.ndarray) -> list[Segment]:
        out: list[Segment] = []
        data = np.concatenate([self._pending, chunk]) if self._pending.size else chunk
        usable = len(data) - len(data) % FRAME
        self._pending = data[usable:]
        for start in range(0, usable, FRAME):
            out.extend(self._frame(data[start : start + FRAME]))
        return out

    def _frame(self, frame: np.ndarray) -> list[Segment]:
        level = 20 * np.log10(np.sqrt(np.mean(frame * frame)) + 1e-9)
        threshold = min(max(-50.0, self._noise_db + 12.0), -28.0)
        speech = level > threshold

        if not self._active:
            # Track the background level so steady noise doesn't count as speech.
            rate = 0.05 if not speech else 0.002
            self._noise_db += rate * (max(level, -90.0) - self._noise_db)
            self._preroll.append(frame)
            self._onset = self._onset + 1 if speech else 0
            if self._onset >= 3:
                self._active = True
                self._frames = list(self._preroll)
                self._levels = [threshold] * len(self._frames)
                self._voiced = self._onset
                self._silence = 0
                self._since_partial = 0
                self._preroll.clear()
                self.on_speaking(True)
            return []

        self._frames.append(frame)
        self._levels.append(level)
        self._since_partial += 1
        if speech:
            self._voiced += 1
            self._silence = 0
        else:
            self._silence += 1

        if self._silence >= self.silence_frames:
            keep = len(self._frames) - self._silence + min(self._silence, 7)
            return self._finish(self._frames[:keep])
        if len(self._frames) >= self.max_frames:
            # Cut at the quietest moment of the last 3 s and keep talking.
            window = self._levels[-100:]
            cut = len(self._frames) - len(window) + int(np.argmin(window)) + 1
            head, tail, tail_levels = self._frames[:cut], self._frames[cut:], self._levels[cut:]
            segments = self._finish(head, keep_active=True)
            self._frames, self._levels = tail, tail_levels
            return segments
        if self.partial_frames and self._since_partial >= self.partial_frames and len(self._frames) > 33:
            self._since_partial = 0
            return [Segment(self._next_id, "partial", np.concatenate(self._frames), self.speaker)]
        return []

    def _finish(self, frames: list[np.ndarray], keep_active: bool = False) -> list[Segment]:
        voiced = self._voiced
        segment_id = self._next_id
        self._next_id += 1
        if keep_active:
            self._voiced = 0
            self._since_partial = 0
        else:
            self.reset()
            self._onset = 0
        if voiced < self.min_voiced or not frames:
            return []
        return [Segment(segment_id, "final", np.concatenate(frames), self.speaker)]
