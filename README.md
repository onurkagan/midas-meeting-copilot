<p align="center">
  <img src="docs/assets/icon-256.png" width="128" height="128" alt="Midas app icon: a clear glass bubble holding a glowing sound wave, on a sea-blue tile">
</p>

<h1 align="center">Midas: open-source AI meeting copilot for Mac</h1>

<p align="center">
  <b>Live, on-device transcription of Zoom, Google Meet and Microsoft Teams calls, with answers from Claude or a local Ollama model in a panel that screen sharing can't see.</b><br>
  No bot joins the call. Audio never leaves your Mac.
</p>

<p align="center">
  <a href="https://onurkagan.github.io/midas-meeting-copilot/"><b>Website</b></a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#faq">FAQ</a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-3b82f6" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-14.4%2B-1f2937?logo=apple&logoColor=white" alt="macOS 14.4 or later">
  <img src="https://img.shields.io/badge/Apple%20Silicon-M1%E2%80%93M4-1f2937" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Claude%20Code-MCP-d97757" alt="Claude Code over MCP">
  <img src="https://img.shields.io/badge/Whisper-on--device-10b981" alt="On-device Whisper transcription">
  <img src="https://img.shields.io/badge/Ollama-local%20models-1f2937?logo=ollama&logoColor=white" alt="Local models with Ollama">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/panel-dark.png">
    <img src="docs/assets/panel.png" width="420" alt="The Midas panel during a meeting: the live transcript, an answer request and Claude's suggested reply">
  </picture>
</p>

**Midas** is a free, open-source AI meeting assistant for macOS. It listens to the app you're in a call with (Zoom, Google Meet, Microsoft Teams, Webex, Slack huddles…) and transcribes it in real time with Whisper, running locally on Apple Silicon. When someone asks you something, press **Answer**: Claude Code receives the conversation over MCP (the Model Context Protocol) and drafts a reply you can say out loud. Prefer to keep everything on your Mac? Pick a local model in [Ollama](https://ollama.com) instead. The reply appears in a small floating panel that stays out of screen shares, screenshots and recordings.

## Features

- **Works with any meeting app.** Midas listens to the app you're in a call with, Zoom, Google Meet in your browser, Microsoft Teams, Webex, Slack or FaceTime, and only while the call lasts. Nothing to install in the meeting app.
- **Both sides of the call.** While you're in a call, Midas also transcribes your microphone and marks your lines **You**. macOS's echo cancellation keeps the other side out of it, and ⌃⌥V mutes it any time.
- **Only the meeting.** A video in another app or a notification sound doesn't end up in the transcript. Claude reads only the last 10 minutes when you ask, and after a long quiet the next speech starts a new meeting, with its own log and map and a fresh Claude session.
- **No meeting bot.** Nothing joins the call and there's no virtual audio driver: audio comes straight from macOS's Core Audio process tap API. At the start of each meeting Midas reminds you to tell the others, with a message ready to paste into the chat.
- **Private, on-device transcription.** Whisper large-v3-turbo runs locally with MLX. Audio never leaves your Mac; only text goes to Claude, and only when you ask.
- **Or fully local with Ollama.** Choose any model you've pulled into Ollama in the panel's settings. Answers stream in as the model writes them, and the meeting never leaves your Mac. No Claude account needed.
- **Private panel, transparent transcription.** The panel and its menu bar icon are marked `NSWindow.sharingType = .none`, so your notes and drafts stay off your screen share. It has no Dock icon, doesn't appear in ⌘⇥ and never takes focus from the meeting app. It keeps your notes private, not the fact that you're transcribing.
- **Clear about where text goes.** A line under **Answer** shows whether answers stay on your Mac (Ollama) or go to Claude. `local_only` locks Midas to local models, ⌃⌥P takes the meeting off the record, and `keep_sessions_days` deletes old transcripts.
- **Answers on demand.** One press (or ⌃⌥A) and Claude replies to the latest question within seconds. **Summary** lists decisions and action items so far.
- **One timeline.** What was said, where you asked, and Claude's reply, in one scroll, with the sentence being spoken shown live.
- **A map of the meeting.** The **Map** tab gathers the topics, the questions put to you, your answers, decisions, action items and open questions, each tied to the line it came from. **Save map** writes it next to the log as Markdown (with a Mermaid mind map), a JSON Canvas for Obsidian and a picture. What's left open comes over to your next meeting's map.
- **Light on your Claude plan.** About 4k tokens of context per call and no calls until you press. A 30-minute meeting on Opus uses roughly 0.1% of a Max plan's 5-hour limit.
- **Your choice of model.** Claude Opus, Sonnet or Haiku at low to max effort, or any local Ollama model, from the panel.
- **Multilingual.** Turkish and English by default; any of Whisper's languages through `config.toml`.
- **Meeting notes in Markdown.** Each transcript and Claude's replies are saved to `sessions/YYYY-MM-DD_HH-MM.md`.
- **Answers from your codebase and past meetings.** The MCP server also works inside your own repository, so Claude can answer technical questions from your code, and look up what earlier meetings decided.

## How it works

```
Call's audio, microphone ──► midas-audio (Swift, Core Audio process tap, voice processing, 16 kHz PCM)
                   │
                   ▼
              Midas daemon (Python)
              VAD → Whisper (local) → event log ──► sessions/*.md
                   │  127.0.0.1:47821      └──► Ollama (local model, optional)
          ┌────────┴─────────┐
          ▼                  ▼
   midas-overlay        MCP bridge (stdio) ◄──► Claude Code (/midas loop)
   (hidden panel)       wait_for_conversation · show_answer · get_transcript
```

Claude Code runs the `/midas` command as a loop. `wait_for_conversation` blocks until you press **Answer** in the panel, then returns everything transcribed since the last answer (from the last 10 minutes at most), plus the sentence still being spoken. Claude drafts a reply to the latest question and posts it to the panel with `show_answer`. To let Claude also suggest replies on its own, set `auto_answer = true` in `config.toml`.

With **Ollama** chosen in the panel, Claude Code isn't involved: the daemon sends the transcript to the local model itself and streams the reply into the panel.

## Quick start

You need an Apple Silicon Mac with macOS 14.4 or later and a Claude account. Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/onurkagan/midas-meeting-copilot/main/install.sh | bash
```

The [installer](install.sh) sets up what's missing (Xcode command line tools, Python, [Claude Code](https://docs.claude.com/claude-code)) and asks you to sign in to Claude Code. It then downloads Midas into `~/midas-meeting-copilot`, builds it, downloads the Whisper model (~1.6 GB) and opens Midas.app from `/Applications`. Run the same command again to update; your settings and meeting logs are kept.

**Manual setup:** with the Xcode command line tools and Claude Code installed. `./midas setup` uses Python 3.11 or later if you have it (Homebrew's too, even when it isn't on your `PATH`); otherwise it installs Python 3.12 with [uv](https://docs.astral.sh/uv/) into `~/.local`, nothing system-wide.

```bash
git clone https://github.com/onurkagan/midas-meeting-copilot.git
cd midas-meeting-copilot
./midas setup
./midas install
```

`./midas setup` builds the Swift components, creates the `.venv` environment, downloads the Whisper model (~1.6 GB) and writes `.mcp.json` for Claude Code. `./midas install` puts `Midas.app` in `/Applications`.

**Audio permission:** On first run, macOS asks for "System Audio Recording" permission for **midas-audio**; allow it. The permission doesn't depend on which terminal launches Midas, because midas-audio holds its own. If you denied it, the panel shows a warning. To enable it later: System Settings → Privacy & Security → Screen & System Audio Recording → **System Audio Recording Only** → midas-audio. Midas picks up the change within a few seconds. macOS may ask again after `./midas setup` rebuilds the components.

## Using the app

Open Midas from Spotlight (⌘Space → Midas): listening starts, the hidden panel appears and Claude Code runs in the background as the copilot. No terminal window opens; you talk to Claude through the panel. To quit, use **Quit Midas** in the panel's settings (⚙︎).

- macOS doesn't let apps run code from the Desktop or Documents folders, so the app runs a copy of this folder from `~/Library/Application Support/Midas`.
- `context.md`, `config.toml` and the meeting logs (`sessions/`) live there too. **Open folder** in the panel's settings (⚙︎) opens that folder.
- After changing code in this folder, run `./midas install` again; your settings and logs are kept.
- Click Midas's bubble in the menu bar to show or hide the panel. Reopening Midas.app also brings a hidden panel back.
- **Listen to** in the panel's settings (⚙︎) picks what Midas hears. **The app in a call**, the default, follows whichever app has its microphone on; you can also pick one app, which is then heard whenever it plays (the one in a call is marked), or **Everything the Mac plays**. The status at the top names the app being heard, or says Midas is waiting for a call.
- The panel's settings (⚙︎) pick Claude's model (Opus, Sonnet, Haiku) and effort (Low, Medium, High, Max). The default is Opus · medium. The choice is saved, and Claude restarts with it within ~10 s.
- **Usage limits:** The app's Claude runs with only the Midas tools and a short system prompt (~4k tokens of context per call). It makes no calls until you press the button, and each **Answer** is a single call. By our measurements, a 30-minute meeting on Opus uses roughly 0.1% of a Max plan's 5-hour limit.

### Midas for Chrome

A call in Chrome (Google Meet, or Zoom or Teams on the web) shares Chrome's audio with every other tab: a video in another tab would be heard too. **Midas for Chrome** sends Midas one tab instead.

1. In Chrome, open `chrome://extensions`, turn on **Developer mode** and choose **Load unpacked**.
2. Pick `~/Library/Application Support/Midas/extension` (press ⌘⇧G in the folder picker and paste the path). `./midas install` puts it there and tells Chrome how to reach Midas.
3. On the call's tab, click the Midas button in Chrome's toolbar. Its badge reads **ON** while Midas hears that tab, and the panel names it. Click it again, or close the tab, to stop.

- The tab keeps playing for you; Midas gets a copy. It goes to Midas through a native messaging host that only this extension may start, and nothing leaves your Mac.
- On Google Meet, muting yourself in Meet mutes Midas's microphone too, and unmuting unmutes it. The extension reads only the microphone button's state on the page.
- While a tab is sent, Midas sets its own capture of the app aside, so nothing is heard twice; afterwards it goes back to **Listen to**.
- The first click opens a page that says what the extension sends and where, and asks you to allow it; its options page shows it again and lets you withdraw your consent.
- `scripts/pack_extension.sh` packs the extension for the Chrome Web Store; [extension/STORE.md](extension/STORE.md) has the listing, the permission justifications and the privacy answers.

### Local models with Ollama

1. Install [Ollama](https://ollama.com/download) and pull a model, for example `ollama pull llama3.2`. Small models (around 3–4B parameters) answer fastest; larger ones such as `qwen3:8b` or `gemma3:12b` give better answers but take longer.
2. In the panel's settings (⚙︎), choose **Ollama · local**, then a model from the list.

- Answers appear in the timeline word by word as the model writes them. For models that can think before answering, thinking is turned off so replies come quickly.
- Ollama keeps the model loaded for 30 minutes between answers; after that, the next answer loads it again.
- `config.toml` sets `ollama_host` (default: `$OLLAMA_HOST` or `127.0.0.1:11434`), the default `ollama_model` and the context window `ollama_context`.
- Claude Code isn't needed in this mode. The installer still sets it up, but you can skip signing in.

### The panel

| Shortcut | Action |
| --- | --- |
| ⌃⌥M | Show/hide the panel (clicking the menu bar icon or reopening Midas also brings it back) |
| ⌃⌥A | **Answer**: have Claude reply to what has been said so far |
| ⌃⌥P | Go off the record (stop transcribing) and back; the timeline marks where |
| ⌃⌥V | Mute your microphone, so what you say isn't transcribed, and unmute it (also the microphone button) |

#### The meeting map

The **Map** tab, next to the timeline, keeps a map of the meeting: its topics and, under each one, the questions put to you, your answers, decisions, action items (with the owner and due date as said), risks and open questions. Click an item to see the lines it came from; nothing is put on the map without one. **Full map** opens it as a graph in its own window, also hidden from screen sharing.

- **When it updates.** With a local model the map follows the meeting by itself, at most once a minute (`map_live`, `map_interval_s`). With Claude it updates only when you ask for something: after each **Answer** or **Summary**, and when you press **Update**. Then the lines since the last update go to Claude (`map_model`, Sonnet by default) in one call with no tools.
- **Your answers.** Answers Midas suggested stay drafts (dashed) until you mark them **I said this**. What you actually said is in the transcript as your own lines.
- **Saving.** The map is kept next to the log as `sessions/YYYY-MM-DD_HH-MM.map.json` and `.map.md` while the meeting goes. **Save map** adds a JSON Canvas (`.canvas`, which Obsidian opens) and a picture (`.png`). When the meeting winds down (after **Summary**, or a few quiet minutes) the timeline offers the map too.
- **Sharing.** **Export** in the Map tab (or PDF, MD and HTML in the map window) saves the map to send: a **PDF** on A4 pages, **Markdown**, or a single **HTML** file that opens in any browser. Each has the picture of the map (HTML and PDF), a summary of the decisions, action items and open points, and every item with its explanation: what kind it is, when it came up, who it's for and whether it's done, and the lines of the meeting it rests on, word for word, marked You or Others. The file goes next to the log (`.map.pdf`, `.map.md`, `.map.html`) and Finder shows it.
- **Next meeting.** Action items not marked done and questions left open come over to your next meeting's map, if it's within `carry_over_days` (14 by default).

#### The timeline

The whole meeting flows in one timeline: what was said, where you asked for an answer, and Claude's reply right below your request. The sentence being spoken appears live at the bottom. When someone asks a question, press **Answer** (or ⌃⌥A); the reply appears within a few seconds. The timeline follows along while you're at the bottom; if you scroll up to reread something, a **New** button takes you back. You can also type a specific request to Claude in the text field, and **Summary** lists the decisions and action items so far. The icon on each reply copies its text. The status pill at the top shows whether Midas is listening and Claude is ready, and the line under **Answer** says where answers are worked out. When a meeting starts, a card reminds you to tell the others and copies a ready-made message (English, plus Turkish if you transcribe Turkish). The settings drawer holds the theme (**Auto** follows your Mac, or always **Light** or **Dark**), the copilot, model and effort choice, the hotkeys, **Open folder** and **Quit Midas**.

### Personalizing

- `context.md`: who you are, your role, your projects, the meeting agenda. Claude reads it at the start of every session.
- `config.toml`: languages (`languages = ["tr", "en"]`), Whisper model, names and terms to spell correctly (`vocabulary`), silence threshold, automatic replies (`auto_answer`), and privacy: the start-of-meeting reminder and its message (`consent_reminder`, `notice_message`), local models only (`local_only`) and how long to keep transcripts (`keep_sessions_days`), and the meeting map (`map_live`, `map_interval_s`, `map_model`, `carry_over_days`). What Midas listens to (`listen_to`), whether it transcribes your microphone (`microphone`), how far back a copilot may read (`recent_minutes`) and the quiet that starts a new meeting (`meeting_gap_minutes`) are there too.
- `.claude/commands/midas.md`: Claude's behavior and reply style (when to answer, length, tone).

## Using it from a terminal

```bash
./midas start
```

The daemon starts in the background, the panel opens at the top right, and Claude Code enters the `/midas` copilot loop. On first launch Claude Code asks you to approve the `midas` server from `.mcp.json`. Quitting Claude Code also stops the daemon.

To give Claude a focus for this particular meeting, inside Claude Code:

```
/midas Pricing call with a customer today, my discount limit is 10%
```

For faster replies, pick a faster model: `./midas start --model sonnet`.

### Using it in your own repository

For technical meetings where Claude should answer from your codebase, add the MCP server at user scope:

```bash
claude mcp add --scope user midas -- "$PWD/midas" mcp   # run from the Midas folder
```

Then start the Midas daemon (`./midas run` or `./midas start`), open `claude` in your repository and run the `/mcp__midas__copilot` prompt.

### Commands

```
./midas setup            install / rebuild
./midas install          install (or update) Midas.app in /Applications
./midas start [args]     daemon + Claude Code (/midas)
./midas run [--input F]  run the daemon in the foreground; --input plays an audio file for testing
./midas stop             stop the daemon
./midas status           status
./midas logs             follow the logs
```

To try it without a meeting: `./midas run --input recording.m4a`, then `claude` → `/midas` in another terminal.

## How Midas compares

| | Midas | Meeting bots | Cloud note-takers |
| --- | --- | --- | --- |
| Joins the call as a participant | No | Yes | Varies |
| Where audio is transcribed | On your Mac | Vendor's cloud | Vendor's cloud |
| Live answers during the call | Yes, on demand | Some | Some |
| Panel hidden from screen sharing | Yes | — | — |
| Works fully offline | Yes, with Ollama | No | No |
| Open source, self-hosted | Yes (MIT) | Usually not | Usually not |

Looking for an open-source alternative to tools like Granola or Otter? Midas transcribes on your Mac without a bot, keeps meeting notes as Markdown files, and drafts live answers with Claude or a local model.

## FAQ

**Can other participants see Midas in Zoom, Google Meet or Microsoft Teams?**
Midas never joins the meeting: there's no bot, no extra participant and no virtual microphone or speaker. The panel asks macOS to keep it out of screen capture (`NSWindow.sharingType = .none`). Whether a capture tool respects that depends on how it records the screen, so do a test share before an important meeting; sharing a single window instead of the whole screen is the safest option.

**Does Midas record my meetings or upload audio?**
No. Audio is transcribed in memory on your Mac and isn't saved or uploaded. The text transcript is saved locally in `sessions/`, and text is sent to Claude only when you press **Answer** or **Summary** (or continuously if you turn on `auto_answer`). With a local Ollama model, no text leaves your Mac either.

**Can I use Midas without Claude, fully offline?**
Yes. Install [Ollama](https://ollama.com), pull a model, and choose **Ollama · local** in the panel's settings. Transcription and answers then both run on your Mac.

**Which languages does it understand?**
Turkish and English by default. Whisper supports about 100 languages; set them with `languages` in `config.toml`.

**Will it pick up a video or music playing on my Mac?**
Not by default. Midas hears only the app that's in a call (its microphone is on), and only during the call. In a browser it hears every tab, and the panel says so while it does. To transcribe a recording or a webinar, pick the app playing it, or **Everything the Mac plays**, under **Listen to** in the panel's settings (⚙︎).

**Does it transcribe my own voice?**
Yes, during calls. While the meeting app is in a call, Midas also listens to your microphone and marks your lines **You**; macOS's echo cancellation keeps the other side out of them. Mute it any time with ⌃⌥V or the microphone button, or turn it off with `microphone = false` in `config.toml`. The people on the other side aren't told apart: they're all **Others**.

**What do I need to run it?**
An Apple Silicon Mac (M1 or later) with macOS 14.4 or later, and either Claude Code signed in to your Claude account or Ollama with a model you've pulled. It doesn't run on Intel Macs, Windows or Linux: it relies on MLX and on Core Audio process taps, added in macOS 14.4.

**How much of my Claude usage does it take?**
By our measurements, a 30-minute meeting on Opus uses about 0.1% of a Max plan's 5-hour limit, because Claude makes a single, small call each time you press **Answer**.

**Is it legal to transcribe a meeting?**
Rules on recording and transcribing conversations differ by country and state. Many US states, and many countries, require everyone's consent, and data protection law such as the GDPR or Turkey's KVKK applies at work. Tell the other participants: Midas reminds you at the start of each meeting and copies a message for the chat. [PRIVACY.md](PRIVACY.md) explains what Midas keeps and sends, and [consent/](consent/) has templates for a meeting notice, a privacy notice and a consent form. This isn't legal advice.

**Can I use Midas in a job interview or an exam?**
Only where AI help is clearly allowed. Don't use Midas in interviews, exams, certifications or assessments that forbid outside help; see [Use it fairly](#use-it-fairly).

## Limitations

- The people on the other side of the call aren't told apart: their lines are all marked **Others**.
- With speakers instead of headphones, echo cancellation may let a few words of the other side into your lines; Midas drops a line of yours that repeats what the call just said.
- The panel's invisibility relies on macOS's window sharing flag. Check with a test share before an important meeting; sharing a single window instead of the whole screen is the safest option.
- Reply latency is ~1 s of transcription after someone stops talking, plus the model's response time. On an M4 MacBook (16 GB) with Claude Opus 5.5 at low effort, the reply arrived a median 2.0 s after pressing **Answer** (95th percentile 2.4 s, 8 answers in a test meeting). With Ollama it depends on the model and your Mac. `./midas status` shows these numbers for your own meetings.

## Use it fairly

- **Tell people.** Let the other participants know you're transcribing, and get their consent where the law or your organization requires it. The reminder card gives you the words.
- **Don't use it to cheat.** Midas isn't for job interviews, exams, certifications or assessments where outside help isn't allowed. The panel stays off screen shares to keep your own notes private, not to deceive anyone.
- **Choose the copilot for the meeting.** With Claude, what was said goes to Anthropic under your Claude account when you ask for an answer. For confidential meetings, use Ollama, and set `local_only = true` to make sure.
- **Keep only what you need.** Go off the record with ⌃⌥P, and set `keep_sessions_days` to delete old transcripts.

See [PRIVACY.md](PRIVACY.md) for exactly what Midas stores and sends.

## Development

- **Panel design:** the panel's look is called Tide: soft glass in sea blue and seafoam, light by day and "Tide at night" in dark mode, following macOS's appearance. Its colors live in `native/Overlay/Theme.swift`. The live panel is hidden from screenshots, so check the design with sample data instead: `./bin/midas-overlay --render-preview <folder>` writes PNGs of a meeting, the settings, the consent reminder, Ollama and the empty state, each in light and dark (`-dark`).
- **App icon:** `assets/icon/Midas.svg` is generated by `assets/icon/src/generate.py`, so change the generator rather than the SVG. The menu bar glyph and the panel's mark (`native/Overlay/Art.swift`) draw the same bubble and sound wave. `assets/icon/src/build.sh` regenerates the SVG and renders `Midas-1024.png` with headless Chrome, which `./midas install` turns into the app icon and `scripts/build_site.sh` into the site's icons.
- **Website:** the project site in `docs/` is served by GitHub Pages. `scripts/build_site.sh` re-renders its images (icon sizes, panel screenshots and the social preview card from `assets/social/card.html`).

## Contributing

Bug reports, ideas and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains how to set up a development copy and what a good pull request looks like, and everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md). Please report security problems privately, as the [security policy](SECURITY.md) describes. The [accessibility statement](ACCESSIBILITY.md) covers what works with assistive technology today and how to report a barrier.

## About the name

In the myth, Apollo gave King Midas the ears of a donkey, and his barber couldn't keep the secret. Midas's ears hear everything said in the meeting, and keep it to themselves.

## License

[MIT](LICENSE). The typeface, Plus Jakarta Sans, is under the [SIL Open Font License](assets/fonts/OFL.txt). Midas isn't affiliated with Anthropic, Zoom, Google or Microsoft.
