"""The copilot instructions, shared by the /midas command, the MCP prompt and Midas.app."""

import re

from .config import ROOT

COMMAND_FILE = ROOT / ".claude" / "commands" / "midas.md"

# Midas.app runs Claude Code with only the midas tools; this replaces Claude Code's own
# (much longer) system prompt, which would otherwise be re-read on every call.
SYSTEM_PROMPT = (
    "You are Midas, an invisible meeting assistant running in the background on the user's Mac. "
    "Your only tools are the midas MCP tools. Follow the instructions in the user message exactly. "
    "Don't write text replies; do all communication through the tools."
)


def copilot_prompt(focus: str = "") -> str:
    text = COMMAND_FILE.read_text(encoding="utf-8")
    text = re.sub(r"\A---\n.*?\n---\n", "", text, flags=re.DOTALL)
    return text.replace("$ARGUMENTS", focus or "(none)").strip()
