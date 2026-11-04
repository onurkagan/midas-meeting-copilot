"""Past meetings, for Claude Code over MCP: list them, search them, read one.

Reads the logs and meeting maps in sessions/. Each meeting is named by its log, such as
2026-11-05_10-00 (date and start time).
"""

import json
import re
from pathlib import Path

NAME = re.compile(r"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}$")
MAX_CHARS = 20_000


def _logs(folder: Path) -> list[Path]:
    """Meeting logs, newest first."""
    return sorted((p for p in folder.glob("*.md") if NAME.match(p.stem)), reverse=True)


def _map(log: Path) -> dict:
    try:
        return json.loads(log.with_suffix(".map.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _when(name: str) -> str:
    """2026-11-05_10-00 → 2026-11-05 10:00"""
    return name[:10] + " " + name[11:].replace("-", ":")


def listing(folder: Path, limit: int) -> str:
    lines = []
    for log in _logs(folder)[:limit]:
        data = _map(log)
        nodes = data.get("nodes", [])
        count = lambda kind: sum(1 for n in nodes if n.get("type") == kind)  # noqa: E731
        summary = (
            f" · {data.get('title') or 'untitled'}: {count('decision')} decisions, "
            f"{sum(1 for n in nodes if n.get('type') == 'action' and not n.get('done'))} open action items"
            if nodes else " · no map"
        )  # fmt: skip
        lines.append(f"{log.stem} ({_when(log.stem)}){summary}")
    return "\n".join(lines) or "(no meetings saved yet)"


def search(folder: Path, query: str, limit: int) -> str:
    """Map items first (decisions, action items, questions and answers), then what was said."""
    terms = [t for t in query.casefold().split() if t]
    if not terms:
        return "Give a word or phrase to search for."
    found = lambda text: all(t in text.casefold() for t in terms)  # noqa: E731
    hits, said = [], []
    for log in _logs(folder):
        data = _map(log)
        for node in data.get("nodes", []):
            text = " ".join([node.get("label", "")] + [s.get("text", "") for s in node.get("sources", [])])
            if node.get("type") != "topic" and found(text):
                kind = node.get("sub") or node.get("type", "").capitalize()
                extra = " · ".join(v for v in (node.get("owner"), node.get("due")) if v)
                state = " (done)" if node.get("done") else " (said)" if node.get("said") else ""
                hits.append(f"{log.stem} · {data.get('title') or 'meeting'} · {kind}: {node['label']}"
                            + (f" · {extra}" if extra else "") + state + f" ({node.get('time', '')})")  # fmt: skip
        try:
            text = log.read_text(encoding="utf-8")
        except OSError:
            continue
        for line in text.splitlines():
            if line.startswith("**[") and found(line):
                said.append(f"{log.stem} · {line.replace('**', '')}")
    out = hits[:limit] + said[: max(limit - len(hits), 0)]
    if not out:
        return f"Nothing found for {query!r} in {len(_logs(folder))} meetings."
    return "\n".join(out)


def meeting(folder: Path, name: str) -> str:
    """One meeting: its map (as Markdown) if it has one, then its log."""
    logs = _logs(folder)
    if name in ("", "latest"):
        if not logs:
            return "(no meetings saved yet)"
        log = logs[0]
    elif NAME.match(name):
        log = folder / f"{name}.md"
        if not log.exists():
            return f"No meeting named {name}. Use list_meetings to see their names."
    else:
        return "Name a meeting like 2026-11-05_10-00, or 'latest'."
    parts = []
    note = log.with_suffix(".map.md")
    if note.exists():
        parts.append(note.read_text(encoding="utf-8"))
    parts.append(log.read_text(encoding="utf-8"))
    text = "\n\n".join(parts)
    return text if len(text) <= MAX_CHARS else text[:MAX_CHARS] + "\n(… the rest is left out)"
