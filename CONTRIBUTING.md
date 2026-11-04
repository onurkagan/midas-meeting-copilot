# Contributing to Midas

Thanks for taking the time to help. Bug reports, ideas, documentation fixes and code are all welcome, and you don't need to be an expert in Core Audio or SwiftUI to make a useful contribution.

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to help

- **Report a bug:** open an issue with the [bug report form](https://github.com/onurkagan/midas-meeting-copilot/issues/new?template=bug_report.yml). Tell us your macOS version, your Mac and which copilot you use (Claude or a local Ollama model).
- **Suggest a feature:** use the [feature request form](https://github.com/onurkagan/midas-meeting-copilot/issues/new?template=feature_request.yml). Describe the problem first; there may be more than one way to solve it.
- **Improve the docs:** fixes to the README, the [website](docs/) or code comments are small pull requests and always useful.
- **Write code:** issues labelled [good first issue](https://github.com/onurkagan/midas-meeting-copilot/labels/good%20first%20issue) or [help wanted](https://github.com/onurkagan/midas-meeting-copilot/labels/help%20wanted) are a good place to start. For anything bigger than a small fix, open an issue first so we can agree on the approach before you spend time on it.

**Found a security problem?** Please don't open a public issue. See the [security policy](SECURITY.md).

## Development setup

You need an Apple Silicon Mac with macOS 14.4 or later and the Xcode command line tools (`xcode-select --install`). [Claude Code](https://docs.claude.com/claude-code) is needed for the Claude copilot; for the local copilot, [Ollama](https://ollama.com) with a model pulled instead.

```bash
git clone https://github.com/onurkagan/midas-meeting-copilot.git
cd midas-meeting-copilot
./midas setup
```

`./midas setup` builds the Swift helpers into `bin/`, creates `.venv` (it finds Python 3.11 or later, or installs 3.12 with uv), downloads the Whisper model (~1.6 GB) and writes `.mcp.json`. Run it again after changing Swift code.

Ways to run it while you work:

| Command | What it does |
|---|---|
| `./midas run --copilot` | The daemon in the foreground with the panel and the copilot chosen in ⚙︎ (Claude or Ollama); logs go to the terminal. |
| `./midas run --copilot --input meeting.m4a` | The same, but plays an audio file (anything macOS can play) instead of system audio, so you can test without a meeting. |
| `./midas start` | The daemon in the background plus Claude Code with `/midas`. |
| `./midas install` | Installs your working copy as `/Applications/Midas.app`; the app runs from `~/Library/Application Support/Midas`. |

## How the code is organised

| Path | What's there |
|---|---|
| `native/AudioCapture.swift` | `midas-audio`: captures system audio with a Core Audio process tap and streams PCM to the daemon. |
| `native/Overlay/` | `midas-overlay` (the app's main executable): the SwiftUI panel, hidden from screen sharing, and the hotkeys. |
| `src/midas/daemon.py` | Ties it together: audio → segmenter → Whisper → store, and supervises the copilot. |
| `src/midas/transcriber.py`, `segmenter.py`, `audio.py` | Local transcription with mlx-whisper. |
| `src/midas/store.py`, `api.py` | The meeting timeline and the local HTTP API (127.0.0.1) the panel and the MCP bridge use. |
| `src/midas/mcp_server.py`, `prompt.py`, `conversation.py` | The Claude Code copilot over MCP. |
| `src/midas/local_copilot.py`, `ollama.py` | The local copilot with Ollama. |
| `scripts/`, `install.sh` | Setup, app install, the one-line installer and the website build. |
| `docs/` | The project website (GitHub Pages). |

## Checking your change

There is no automated test suite yet; tests are a welcome contribution. Until then:

- **Python:** run `./midas run --copilot --input <audio file>`, press **Answer** in the panel and watch the transcript and the answer arrive. For the Ollama copilot, choose **Ollama · local** in the panel's settings (⚙︎).
- **Panel:** the live panel is hidden from screenshots by design. Render it with sample data instead and look at the PNGs:

  ```bash
  ./bin/midas-overlay --render-preview /tmp/midas-preview
  ```

  Add before and after images to your pull request for any visible change.
- **Audio capture:** after `./midas setup` rebuilds `midas-audio`, macOS may ask for the System Audio Recording permission again.

## Guidelines

These keep Midas true to what it promises:

- **Private by default.** Audio and transcripts stay on the Mac. Don't add telemetry, analytics or network calls beyond the copilot the user chose.
- **Invisible in screen shares.** The panel must not open menus, pop-up buttons, sheets or other separate windows: macOS shares those even when the panel itself is hidden. Use inline controls, as the settings drawer does.
- **Accessible.** Give icon-only buttons an accessibility label, don't rely on color alone, and keep new actions reachable from the keyboard. The [accessibility statement](ACCESSIBILITY.md) lists what still needs work.
- **English** for code, comments, UI text and docs.
- **Few dependencies.** Prefer the standard library and what's already in `requirements.txt`.
- **Match the surrounding style:** type hints in Python, small focused functions, comments that explain why, lines up to about 120 characters.

## Commits and pull requests

- Keep commits small and focused, one change each, with [Conventional Commits](https://www.conventionalcommits.org) messages:

  ```
  feat(panel): show the model name in the status pill
  fix(setup): find Homebrew's Python when it isn't on PATH
  docs(readme): explain the Ollama settings
  ```

  Common types are `feat`, `fix`, `docs`, `refactor` and `build`; the scope is the area you touched (`panel`, `daemon`, `ollama`, `audio`, `setup`, `site`…).
- One topic per pull request. Say what changed and why, how you checked it (macOS version, Mac, copilot and model), and link the issue it closes.
- Update the README and the website when you change how something works.
- By contributing, you agree that your work is licensed under the project's [MIT License](LICENSE).

Thank you for helping make Midas better.
