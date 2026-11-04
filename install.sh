#!/usr/bin/env bash
# Midas installer: sets up everything Midas needs and installs Midas.app.
#
#   curl -fsSL https://raw.githubusercontent.com/onurkagan/midas-meeting-copilot/main/install.sh | bash
#
#   1. Checks for an Apple Silicon Mac with macOS 14.4 or later and enough free space.
#   2. Installs the Xcode command line tools if missing (macOS shows its own dialog).
#   3. Finds Python 3.11+, or installs Python 3.12 with uv into ~/.local.
#   4. Installs Claude Code if missing and asks you to sign in.
#   5. Downloads Midas into ~/midas-meeting-copilot (or updates it), builds it, downloads
#      the Whisper model (~1.6 GB) and installs Midas.app into /Applications.
#
# Run it again to update Midas; your settings and meeting logs are kept.
# Options (environment variables): MIDAS_DIR (source folder), MIDAS_REPO (git URL),
# MIDAS_OPEN=0 (don't open Midas at the end), and MIDAS_HOME / MIDAS_APP_DIR (see
# scripts/install_app.sh).
set -euo pipefail

REPO="${MIDAS_REPO:-https://github.com/onurkagan/midas-meeting-copilot.git}"
DIR="${MIDAS_DIR:-$HOME/midas-meeting-copilot}"
APP="${MIDAS_APP_DIR:-/Applications}/Midas.app"
# Where uv, Claude Code and Homebrew put their commands.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if [[ -t 1 ]]; then
  bold=$'\033[1m' blue=$'\033[34m' red=$'\033[31m' reset=$'\033[0m'
else
  bold='' blue='' red='' reset=''
fi
step() { printf '\n%s→ %s%s\n' "$blue$bold" "$1" "$reset"; }
reported=0
fail() { reported=1; printf '\n%sError:%s %s\n' "$red$bold" "$reset" "$1" >&2; exit 1; }
# Steps run quietly, so say so if one of them stops the script without explaining why.
trap 'status=$?; ((status == 0 || reported)) || printf "\n%sError:%s the installation stopped. The lines above say why; if they do not, open an issue at https://github.com/onurkagan/midas-meeting-copilot/issues\n" "$red$bold" "$reset" >&2' EXIT
has_tty() { (exec </dev/tty) 2>/dev/null; }

check_mac() {
  [[ "$(uname -s)" == Darwin ]] || fail "Midas runs on macOS only."
  [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == 1 ]] ||
    fail "Midas needs an Apple Silicon Mac (M1 or later)."
  local version major minor free_gb
  version="$(sw_vers -productVersion)"
  IFS=. read -r major minor _ <<<"$version.0"
  if ((major < 14 || (major == 14 && minor < 4))); then
    fail "Midas needs macOS 14.4 or later; this Mac has $version."
  fi
  # A first install needs room for the Python packages (twice: the app keeps its own copy)
  # and the Whisper model; an update reuses both.
  local need_gb=1
  [[ -d "$DIR/.venv" ]] || need_gb=$((need_gb + 3))
  [[ -d "$HOME/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo" ]] || need_gb=$((need_gb + 2))
  free_gb="$(df -g "$HOME" | awk 'NR == 2 { print $4 }')"
  ((free_gb >= need_gb)) || fail "Midas needs about $need_gb GB of free disk space; $free_gb GB is free."
}

ensure_xcode_tools() {
  xcode_ready() { xcode-select -p >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1; }
  xcode_ready && return
  step "Installing the Xcode command line tools"
  echo "macOS shows a dialog: click Install and wait for it to finish (a few minutes)."
  xcode-select --install >/dev/null 2>&1 || true
  local waited=0
  until xcode_ready; do
    sleep 5
    waited=$((waited + 5))
    ((waited < 1800)) || fail "The Xcode command line tools aren't installed yet. Run this installer again once they are."
  done
}

python_ok() { "$1" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; }

# Sets PYTHON to the first interpreter that is 3.11 or later.
find_python() {
  local name
  # The newest versions last: their wheels for MLX and friends tend to arrive later.
  for name in python3.13 python3.12 python3.11 python3.14 python3; do
    command -v "$name" >/dev/null || continue
    PYTHON="$(command -v "$name")"
    python_ok "$PYTHON" && return 0
  done
  return 1
}

ensure_python() {
  find_python && return
  step "Installing Python 3.12 (with uv, into ~/.local)"
  if ! command -v uv >/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh >/dev/null
  fi
  uv python install 3.12 >/dev/null
  PYTHON="$(uv python find 3.12)"
}

signed_in() { claude auth status 2>/dev/null | grep -q '"loggedIn": *true'; }

ensure_claude() {
  if ! command -v claude >/dev/null; then
    step "Installing Claude Code"
    curl -fsSL https://claude.ai/install.sh | bash
  fi
  signed_in && return
  step "Signing in to Claude Code"
  echo "Midas answers with your own Claude account. Follow the steps in your browser."
  if has_tty; then claude auth login </dev/tty || true; fi
  signed_in || echo "Not signed in yet: run 'claude' in Terminal and sign in before your first meeting."
}

fetch_midas() {
  if [[ -d "$DIR/.git" ]]; then
    step "Updating Midas in $DIR"
    git -C "$DIR" pull --ff-only --quiet
  elif [[ -e "$DIR" ]]; then
    fail "$DIR exists but isn't a copy of Midas. Move it away, or set MIDAS_DIR to another folder."
  else
    step "Downloading Midas into $DIR"
    git clone --depth 1 --quiet "$REPO" "$DIR"
  fi
}

midas_running() { pgrep -f "$APP/Contents/MacOS/Midas" >/dev/null; }

build_and_install() {
  step "Building Midas and downloading the Whisper model (~1.6 GB the first time)"
  MIDAS_PYTHON="$PYTHON" "$DIR/midas" setup >/dev/null
  if midas_running; then
    step "Quitting the running Midas to update it"
    osascript -e 'tell application id "dev.midas.app" to quit' >/dev/null 2>&1 || true
    local waited=0
    while midas_running && ((waited < 20)); do sleep 1; waited=$((waited + 1)); done
  fi
  step "Installing Midas.app"
  "$DIR/midas" install >/dev/null
}

finish() {
  [[ "${MIDAS_OPEN:-1}" == 0 ]] || open "$APP"
  cat <<EOF

${bold}Midas is installed.${reset}

  • macOS asks for "System Audio Recording" permission for midas-audio: click Allow.
  • The panel shows and hides from the bubble in the menu bar, or with ⌃⌥M.
  • In a meeting, press Answer (⌃⌥A) when you want Claude to reply.
  • To update Midas later, run the same install command again.

Source: $DIR · Docs: https://github.com/onurkagan/midas-meeting-copilot
EOF
}

main() {
  printf '%sMidas%s: open-source AI meeting copilot for Mac\n' "$bold" "$reset"
  check_mac
  ensure_xcode_tools
  ensure_python
  ensure_claude
  fetch_midas
  build_and_install
  finish
}

# Everything runs from here, so a download cut short by the network can't run half a script.
main "$@"
