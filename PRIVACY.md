# Privacy

Midas listens to meetings, so this page says exactly what it keeps, where text goes, and what it never does. Midas has no servers, accounts, analytics or telemetry: everything below happens on your Mac, except the answers you ask Claude for.

## What Midas hears

By default, only the app you're in a call with, and only while the call lasts: Midas taps that app's audio while its microphone is on, and stops shortly after the call ends. Other apps, a video, music or a notification sound, aren't heard. In a browser Midas hears every tab, and the panel says so while it does. You can pick one app, or everything the Mac plays, under **Listen to** in the panel's settings (⚙︎), or with `listen_to` in `config.toml`.

Your microphone too, during the same calls: what you say is transcribed and marked **You**, with macOS's echo cancellation keeping the other side out of it. The microphone button or ⌃⌥V mutes it; what it hears while muted isn't transcribed. `microphone = false` in `config.toml` turns it off.

## What Midas keeps on your Mac

| What | Where | How long |
|---|---|---|
| **Audio** | Only in memory, while Whisper transcribes it | Never written to disk, never sent anywhere |
| **Transcript, your requests and the answers** | `sessions/YYYY-MM-DD_HH-MM.md`, one Markdown file per run | Until you delete it, or for `keep_sessions_days` days |
| **The meeting map** (topics, decisions, action items, with the lines they came from) | Beside the log: `.map.json`, `.map.md`, and after **Save map** `.canvas` and `.png` | Deleted with the log; open items come over to your next map for `carry_over_days` days |
| **Transcript lines in the log** | Only when you run Midas with `MIDAS_DEBUG=1`, in `logs/daemon.log` | Replaced each time Midas starts |
| **Your notes for the copilot** | `context.md` | Until you change it |
| **Panel settings** | `copilot.json` | Until you change them |
| **Claude Code's own output** | `logs/claude.log` | Until you delete it |

For Midas.app these files are in `~/Library/Application Support/Midas` (⚙︎ → **Open folder**); in a terminal setup, in the Midas folder. Nothing said while you're off the record (⌃⌥P) is transcribed or kept; the transcript only marks where the gap was.

Midas.app runs Claude Code without its session history, so the meeting isn't also kept in Claude Code's own history. Versions before November 2026 left those sessions in `~/.claude/projects/`, in a folder whose name ends in `Application-Support-Midas`; you can delete that folder. When you run `/midas` yourself in Claude Code, that session is kept like any other.

## Where text goes

**With the Claude copilot**, Claude Code reads the meeting through Midas's local MCP bridge and sends it to Anthropic, under your Claude account and Anthropic's terms and privacy settings (including whether your conversations may be used to improve their models, which you choose in your Claude account). Claude receives:

- what was said since the last answer, but no more than the last 10 minutes (`recent_minutes`), when you press **Answer** or **Summary** or type a request;
- continuously, as people speak, if you turn on `auto_answer`;
- up to the last 30 lines from those 10 minutes, and any unanswered request, when its session starts or restarts, for example after you change the model;
- for the meeting map, the lines since its last update, after each answer you ask for and when you press **Update** or **Save map** (continuously only with `auto_answer`);
- your `context.md`;
- past meetings' maps and logs, only when Claude looks them up for a request of yours (`search_meetings`, `get_meeting`).

After 15 quiet minutes (`meeting_gap_minutes`), the next speech starts a new meeting: its own log and map, and a new Claude session that knows nothing of the last one.

The line under the **Answer** button always says which copilot answers.

**With the Ollama copilot**, the text goes only to the Ollama server set in `config.toml`, which by default is Ollama on your own Mac (`127.0.0.1:11434`). Nothing leaves your Mac, and the local model keeps the meeting map too. Set `local_only = true` to make sure Claude can't be chosen or read the meeting, its map or past meetings.

**Nothing else.** Once the Whisper model is downloaded, Midas makes no other network requests of its own. Setup downloads that model from Hugging Face, and the installer downloads Python, Claude Code and Midas itself. Claude Code and Ollama are separate programs with their own privacy policies.

## What Midas never does

- It doesn't join the meeting, add a bot or install a virtual audio device.
- It doesn't record or upload audio.
- It doesn't identify speakers by their voice or keep voiceprints.
- It doesn't analyze emotions, attention or engagement.
- It doesn't let web pages read its local API: the daemon on `127.0.0.1:47821` refuses requests from browsers.

## Your part

The transcript holds what other people said, so the law treats it as their personal data too. Tell them you're transcribing, and get consent where your jurisdiction or organization requires it. Midas reminds you at the start of each meeting; [consent/](consent/) has templates for a meeting notice, a privacy notice and a consent form. Don't use Midas where AI help isn't allowed, such as interviews or exams.

Questions or concerns: open an [issue](https://github.com/onurkagan/midas-meeting-copilot/issues), or report security problems privately as described in [SECURITY.md](SECURITY.md).
