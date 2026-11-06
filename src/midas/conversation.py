"""How the meeting is put into words for a model: shared by the MCP bridge (Claude Code)
and the local Ollama copilot."""

from .config import CONTEXT_FILE, ROOT
from .store import OFF_THE_RECORD, speaker_label

EMPTY_REQUEST = "(pressed Answer: draft a reply to the latest question or topic now)"


def marker_note(event: dict) -> str:
    """Where the user went off the record, so a model doesn't mistake the gap for silence."""
    if event["text"] == OFF_THE_RECORD:
        return f"[{event['time']}] (the user went off the record: nothing said until they resumed was transcribed)"
    return f"[{event['time']}] (back on the record)"


def format_events(events: list[dict], partial: str = "", live: bool = True) -> str:
    """Live requests go last and must be answered; past ones stay in place as history."""
    lines = []
    for event in events:
        if event["kind"] == "transcript":
            lines.append(f"[{event['time']}] {speaker_label(event)}: {event['text']}")
        elif event["kind"] == "marker":
            lines.append(marker_note(event))
        elif not live:
            lines.append(f"[{event['time']}] (earlier request, already answered: {event['text'] or 'Answer'})")
    if partial:
        lines.append(f"[being said right now, unfinished] Others: {partial}")
    if live:
        for event in events:
            if event["kind"] == "request":
                lines.append(f"[{event['time']}] >>> USER REQUEST (must answer): {event['text'] or EMPTY_REQUEST}")
    return "\n".join(lines)


def user_context() -> str:
    """The user's notes from context.md, unless it is still the untouched template."""
    template = ROOT / "context.example.md"
    if not CONTEXT_FILE.exists():
        return "(none)"
    text = CONTEXT_FILE.read_text(encoding="utf-8").strip()
    if template.exists() and text == template.read_text(encoding="utf-8").strip():
        return "(template not filled in)"
    return text[:6000]
