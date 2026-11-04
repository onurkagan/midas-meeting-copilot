# Security policy

Midas listens to your meetings, so its security and privacy matter. Thank you for helping keep its users safe.

## Supported versions

Fixes go into the `main` branch and the next release. Please check that a problem still happens on the [latest release](https://github.com/onurkagan/midas-meeting-copilot/releases/latest) or on `main` before reporting it. Rerunning the [one-line installer](README.md#quick-start) updates an existing install.

## Reporting a vulnerability

**Please don't open a public issue.** Report it privately through GitHub instead:

**[Report a vulnerability](https://github.com/onurkagan/midas-meeting-copilot/security/advisories/new)** (repository → Security → Report a vulnerability)

Please include:

- what an attacker can do, and what they need first (another app on the Mac, a website the user visits, a device on the same network…)
- steps to reproduce, or a proof of concept
- your macOS version, Mac, Midas version (or commit) and copilot (Claude or Ollama)

Leave real meeting transcripts and personal data out of the report.

## What to expect

Midas is maintained by one person in their spare time, so these are goals rather than guarantees:

- an acknowledgement within 7 days
- an assessment, and a plan or a question back, within 14 days
- a fix as soon as practical, released together with a GitHub security advisory that credits you, unless you'd rather stay anonymous

Please give us a reasonable chance to release a fix before you disclose the issue publicly.

## Scope

In scope is anything in this repository, in particular:

- **Meeting data:** anything that lets another app, a website or another user read the audio, transcripts, answers, `context.md` or the meeting logs in `sessions/` without the user's consent.
- **The local API:** the daemon listens on `127.0.0.1:47821`; anything that lets someone else read from it or control it, for example from a web page.
- **Screen-share invisibility:** a way for the Midas panel, or a window it opens, to show up in a screen share or recording while it should be hidden.
- **Data leaving the Mac:** anything sent anywhere other than the copilot the user chose (Claude Code, or the Ollama server set in `config.toml`).
- **Installation:** `install.sh`, `./midas setup` and `./midas install`, for example running code from an unexpected place or weakening macOS permissions.

Out of scope:

- problems in Claude Code, Ollama, Whisper or MLX themselves; please report those to their projects
- attacks that already need full control of the user's account or an unlocked Mac
- meeting text reaching Anthropic when you ask the Claude copilot for an answer: that is how it works, and the README says so. Choose the Ollama copilot to keep everything on the Mac.
