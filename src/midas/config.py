"""Settings, read from config.toml in the project root (every key is optional)."""

import os
import tomllib
from dataclasses import dataclass, field, fields
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BIN_DIR = ROOT / "bin"
SESSIONS_DIR = ROOT / "sessions"
LOGS_DIR = ROOT / "logs"
PID_FILE = LOGS_DIR / "midas.pid"
CONTEXT_FILE = ROOT / "context.md"
COPILOT_FILE = ROOT / "copilot.json"
# Full ids, not Claude Code's aliases: its `haiku` alias still means Haiku 4.5, which
# thinks for 10+ s at medium effort.
CLAUDE_MODELS = {"opus": "claude-opus-5-5", "sonnet": "claude-sonnet-5-5", "haiku": "claude-haiku-5-5"}
CLAUDE_EFFORTS = ("low", "medium", "high", "max")


@dataclass
class Config:
    host: str = "127.0.0.1"
    port: int = 47821
    # Any mlx-community Whisper repo; large-v3-turbo is the best speed/quality trade-off.
    model: str = "mlx-community/whisper-large-v3-turbo"
    # One language forces it; several lets Whisper pick among them per utterance.
    languages: list[str] = field(default_factory=lambda: ["tr", "en"])
    # Names and jargon that Whisper should spell correctly.
    vocabulary: str = ""
    silence_ms: int = 700
    max_segment_s: float = 20.0
    partials: bool = True
    overlay: bool = True
    # False: Claude answers only when you press "Cevap ver". True: it also decides by itself.
    auto_answer: bool = False
    # Headless Claude Code copilot (Midas.app / `midas run --copilot`). These are the
    # defaults; the panel's model/effort choice is saved to copilot.json and wins.
    claude_command: str = "claude"
    claude_model: str = "opus"
    claude_effort: str = "medium"
    # How long one idle wait lasts. Each wait that ends without a request costs a call,
    # so keep it long, but under the 1 h prompt-cache lifetime.
    idle_wait_s: int = 1500

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}"


def load_config() -> Config:
    path = Path(os.environ.get("MIDAS_CONFIG", ROOT / "config.toml"))
    data = tomllib.loads(path.read_text()) if path.exists() else {}
    known = {f.name for f in fields(Config)}
    config = Config(**{k: v for k, v in data.items() if k in known})
    if port := os.environ.get("MIDAS_PORT"):
        config.port = int(port)
    return config
