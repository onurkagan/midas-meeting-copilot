"""MCP bridge between Claude Code and the Midas daemon (stdio transport)."""

import logging
import os

import httpx
from mcp.server import MCPServer

from .config import CONTEXT_FILE, load_config
from .conversation import format_events, user_context
from .prompt import copilot_prompt

logging.getLogger("httpx").setLevel(logging.WARNING)
config = load_config()
# Midas.app raises this so idle waits cost no calls; interactive sessions keep it short.
WAIT_SECONDS = int(os.environ.get("MIDAS_WAIT_SECONDS", "100"))

mcp = MCPServer(
    name="midas",
    instructions=(
        "Midas transcribes the meeting audio playing on the user's Mac in real time and shows a "
        "panel that is hidden from screen sharing. To start copilot mode, use the `copilot` prompt "
        "(or the /midas command in the Midas folder): wait for the user's 'Answer' request with "
        "wait_for_conversation, then show a short reply in the panel with show_answer."
    ),
)

_cursor: int | None = None


class DaemonDown(Exception):
    pass


async def _call(method: str, path: str, timeout: float = 10.0, **kwargs) -> dict:
    try:
        async with httpx.AsyncClient(base_url=config.base_url, timeout=timeout) as client:
            response = await client.request(method, path, **kwargs)
            response.raise_for_status()
            return response.json()
    except httpx.ConnectError as error:
        raise DaemonDown() from error


DOWN_MESSAGE = (
    f"ERROR: the Midas daemon is not running ({config.base_url}). Tell the user to run "
    "`./midas run` (or `./midas start`) in the Midas folder."
)


LOCAL_ONLY_MESSAGE = (
    "STOP: Midas is set to local_only = true in config.toml, so Claude may not read this meeting. "
    "Tell the user that, and don't call the Midas tools again."
)


def _initial_context(data: dict) -> str:
    """What a (re)started copilot sees first: history, plus any request still unanswered,
    e.g. one made while the model was being switched. Answered requests stay history."""
    pending = data.get("pending", [])
    pending_ids = {event["id"] for event in pending}
    history = [event for event in data["events"] if event["id"] not in pending_ids]
    parts = []
    if history:
        parts.append("Context: the conversation so far (not a request, do not answer):\n" + format_events(history, live=False))
    if pending:
        parts.append("Unanswered request:\n" + format_events(pending))
    return "\n\n".join(parts)


@mcp.tool()
async def wait_for_conversation() -> str:
    """Waits for the user's request for an answer and returns it with what has been said (long-poll).

    The conversation comes from the Mac's system audio, so it belongs to the OTHER meeting
    participants. When the user presses "Answer" in the panel or types a question, this returns
    at once with everything transcribed since the last delivery and the sentence still being
    spoken. Without a request it returns empty after a while; then call it again right away.
    The first call returns the conversation so far, as context only.
    """
    global _cursor
    if config.local_only:
        return LOCAL_ONLY_MESSAGE
    try:
        if _cursor is None:
            data = await _call("GET", "/api/recent", params={"last": 30})
            _cursor = data["cursor"]
            if context := _initial_context(data):
                return context
        timeout = max(5, min(WAIT_SECONDS, 3600))
        data = await _call(
            "GET", "/api/wait", timeout=timeout + 10, params={"cursor": _cursor, "timeout": timeout}
        )
    except DaemonDown:
        return DOWN_MESSAGE
    _cursor = data["cursor"]
    if not data["events"]:
        return "(no request yet; call wait_for_conversation again right away)"
    text = format_events(data["events"], data.get("partial", ""))
    if data.get("auto") and not any(e["kind"] == "request" for e in data["events"]):
        text += "\n(Auto mode: show a reply with show_answer if one is needed, otherwise go back to waiting.)"
    return text


@mcp.tool()
async def show_answer(text: str, title: str = "") -> str:
    """Shows a reply or suggestion in the hidden Midas panel on the user's screen.

    title: a heading of at most ~6 words (e.g. the gist of the question).
    text: a short reply the user can say in the meeting; the first line is the answer itself,
    followed by a few short bullets if needed. Inline **bold** is supported.
    """
    try:
        await _call("POST", "/api/answer", json={"text": text, "title": title})
    except DaemonDown:
        return DOWN_MESSAGE
    return "Shown in the panel."


@mcp.tool()
async def get_transcript(last_n: int = 40) -> str:
    """Returns the last last_n lines of the meeting transcript (and the user's requests)."""
    if config.local_only:
        return LOCAL_ONLY_MESSAGE
    try:
        data = await _call("GET", "/api/recent", params={"last": max(1, min(last_n, 500))})
    except DaemonDown:
        return DOWN_MESSAGE
    return format_events(data["events"], live=False) or "(no transcript yet)"


@mcp.tool()
async def midas_status() -> str:
    """Returns the Midas daemon's status and the user's context notes (context.md: who they are, role, agenda)."""
    if config.local_only:
        return LOCAL_ONLY_MESSAGE
    try:
        health = await _call("GET", "/api/health")
    except DaemonDown:
        return DOWN_MESSAGE
    return (
        f"Status: {health['status']}{' (paused)' if health['paused'] else ''}\n"
        f"Session log: {health['session_file']}\n\n"
        f"The user's context notes ({CONTEXT_FILE.name}):\n{user_context()}"
    )


@mcp.prompt(name="copilot", description="Starts the Midas meeting copilot loop")
def copilot(focus: str = "") -> str:
    return copilot_prompt(focus)


def main():
    mcp.run()
