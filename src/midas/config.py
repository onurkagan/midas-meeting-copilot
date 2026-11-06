"""Settings, read from config.toml in the project root (every key is optional)."""

import os
import tomllib
from dataclasses import dataclass, field, fields
from pathlib import Path
from urllib.parse import urlsplit

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
# Who answers: Claude through Claude Code, or a local model through Ollama.
COPILOT_PROVIDERS = ("claude", "ollama")


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
    # "claude", or "ollama" for a local model: nothing leaves the Mac. The panel's choice
    # (copilot.json) wins.
    provider: str = "claude"
    # Ollama (https://ollama.com). Empty host: $OLLAMA_HOST, else the default local port.
    ollama_host: str = ""
    # Empty: the first model you have pulled. The panel's choice wins.
    ollama_model: str = ""
    # Context window for each answer, in tokens; the oldest lines are left out beyond it.
    ollama_context: int = 8192
    # How long Ollama keeps the model loaded between answers.
    ollama_keep_alive: str = "30m"
    # Privacy. At the start of each meeting the panel reminds you to tell the others that
    # you're transcribing, with a message to paste into the chat.
    consent_reminder: bool = True
    # Your own wording for that message; empty uses Midas's (English, plus Turkish if you
    # transcribe Turkish).
    notice_message: str = ""
    # Only local models (Ollama) may answer; Claude can't read the meeting.
    local_only: bool = False
    # Delete meeting logs in sessions/ older than this many days when Midas starts; 0 keeps them.
    keep_sessions_days: int = 0
    # A copilot reads only what was said in the last this-many minutes (your requests always
    # go), so sound from before the meeting can't reach it; 0 lets it read the whole meeting.
    recent_minutes: int = 10
    # What Midas listens to: "auto" (whichever app is in a call: its microphone is on),
    # "all" (everything the Mac plays) or one app's bundle ID such as "us.zoom.xos". With an
    # app, only that app is heard, and only during its calls. The panel's choice wins.
    listen_to: str = "auto"
    # Transcribe what you say too, from the microphone, while the meeting app is in a call.
    # Your lines are marked "You"; ⌃⌥V mutes Midas's microphone at any time.
    microphone: bool = True
    # Speech after this many quiet minutes starts a new meeting: its own log and map, and the
    # copilot starts over without the last one; 0 keeps one meeting per run.
    meeting_gap_minutes: int = 15
    # The meeting map: topics, questions put to you, your answers, decisions and action items.
    # With a local model it follows the meeting by itself, at most every map_interval_s.
    # Claude updates it only when you ask (Answer, Summary, Update map), unless auto_answer.
    map_live: bool = True
    map_interval_s: int = 60
    # The Claude model for the map; a quick one is plenty.
    map_model: str = "sonnet"
    # Action items not done and questions left open in your last meeting come over to the
    # new map, if that meeting was within this many days; 0 turns it off.
    carry_over_days: int = 14

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}"

    @property
    def ollama_url(self) -> str:
        # Read like Ollama reads OLLAMA_HOST: without a scheme the port defaults to 11434,
        # with one to the scheme's own port.
        host = (self.ollama_host or os.environ.get("OLLAMA_HOST") or "").strip() or "127.0.0.1"
        explicit = "://" in host
        url = urlsplit(host if explicit else f"http://{host}")
        port = url.port or (11434 if not explicit else 443 if url.scheme == "https" else 80)
        # OLLAMA_HOST may name the address Ollama listens on, such as 0.0.0.0.
        hostname = "127.0.0.1" if url.hostname in (None, "", "0.0.0.0") else url.hostname
        return f"{url.scheme}://{hostname}:{port}"


def load_config() -> Config:
    path = Path(os.environ.get("MIDAS_CONFIG", ROOT / "config.toml"))
    data = tomllib.loads(path.read_text()) if path.exists() else {}
    known = {f.name for f in fields(Config)}
    config = Config(**{k: v for k, v in data.items() if k in known})
    if port := os.environ.get("MIDAS_PORT"):
        config.port = int(port)
    return config
