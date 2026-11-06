"""What Midas tells the other participants, and how long it keeps meeting logs."""

import logging
import time
from pathlib import Path

from .config import Config

log = logging.getLogger("midas")

# A message to paste into the meeting chat (or say) at the start. Honest about the AI and
# about what is and isn't kept; edit it with `notice_message` in config.toml.
NOTICES = {
    "en": (
        "Heads-up: I'm using an AI assistant on my Mac (Midas) that transcribes this call, so I can take "
        "notes and get suggestions. No audio is recorded. If you'd rather I didn't, just say so and I'll turn it off."
    ),
    "tr": (
        "Bilginize: Not alabilmek ve öneri alabilmek için bu görüşmeyi Mac'imde çalışan bir yapay zekâ "
        "asistanıyla (Midas) yazıya döküyorum. Ses kaydı tutulmuyor. İstemezseniz söylemeniz yeterli, kapatırım."
    ),
}

# Only Midas's own logs (sessions/YYYY-MM-DD_HH-MM.md) are ever deleted, with the meeting
# map files saved beside them.
SESSION_GLOB = "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9].md"
MAP_SUFFIXES = (".map.json", ".map.md", ".map.html", ".map.pdf", ".canvas", ".png")


def panel_privacy(config: Config) -> dict:
    """The privacy settings the panel shows: the reminder and its messages, whether only
    local models may answer, and whether Claude reads the meeting without being asked."""
    if config.notice_message.strip():
        notices = {"custom": config.notice_message.strip()}
    else:
        notices = {"en": NOTICES["en"]}
        if "tr" in config.languages:
            notices["tr"] = NOTICES["tr"]
    return {
        "reminder": config.consent_reminder,
        "notices": notices,
        "local_only": config.local_only,
        "auto_answer": config.auto_answer,
    }


def prune_sessions(folder: Path, days: int) -> int:
    """Deletes meeting logs older than `days` (0 keeps them all); returns how many."""
    if days <= 0 or not folder.is_dir():
        return 0
    cutoff = time.time() - days * 86400
    removed = 0
    for path in folder.glob(SESSION_GLOB):
        if path.stat().st_mtime < cutoff:
            path.unlink(missing_ok=True)
            for suffix in MAP_SUFFIXES:
                path.with_suffix(suffix).unlink(missing_ok=True)
            removed += 1
    if removed:
        log.info("deleted %d meeting log(s) older than %d days (keep_sessions_days)", removed, days)
    return removed
