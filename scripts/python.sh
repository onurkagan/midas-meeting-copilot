# Finds a Python 3.11+ for Midas's .venv, or installs one. Sourced by setup.sh.
# macOS's own python3 is 3.9, too old for Midas.

# Homebrew's and uv's interpreters count even when the shell profile doesn't put them on PATH.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin"

python_ok() { "$1" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; }

# Sets PYTHON to MIDAS_PYTHON, else to the first interpreter that is 3.11 or later.
find_python() {
  local name
  if [[ -n "${MIDAS_PYTHON:-}" ]]; then
    PYTHON="$MIDAS_PYTHON"
    python_ok "$PYTHON"
    return
  fi
  # The newest versions last: their wheels for MLX and friends tend to arrive later.
  for name in python3.13 python3.12 python3.11 python3.14 python3; do
    PYTHON="$(command -v "$name")" || continue
    python_ok "$PYTHON" && return 0
  done
  command -v uv >/dev/null && PYTHON="$(uv python find '>=3.11' 2>/dev/null)" && python_ok "$PYTHON"
}

# Sets PYTHON, installing Python 3.12 with uv into ~/.local when there is none to use.
ensure_python() {
  find_python && return 0
  if [[ -n "${MIDAS_PYTHON:-}" ]]; then
    echo "MIDAS_PYTHON is $MIDAS_PYTHON ($("$MIDAS_PYTHON" --version 2>&1 || echo "not found")), but Midas needs Python 3.11 or later." >&2
    return 1
  fi
  echo "  No Python 3.11 or later found; installing Python 3.12 with uv into ~/.local"
  if ! command -v uv >/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh >/dev/null || true
  fi
  if command -v uv >/dev/null && uv python install 3.12 >/dev/null && PYTHON="$(uv python find 3.12)" && python_ok "$PYTHON"; then
    return 0
  fi
  echo "Couldn't install Python 3.12. Install Python 3.11 or later (for example from python.org," >&2
  echo "or with Homebrew: brew install python@3.13), then run ./midas setup again." >&2
  return 1
}
