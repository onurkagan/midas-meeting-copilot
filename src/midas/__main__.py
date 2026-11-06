import argparse
import logging
import os
import sys


def main():
    parser = argparse.ArgumentParser(prog="midas", description="Invisible meeting copilot")
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("run", help="audio capture + transcription + panel")
    run.add_argument("--input", help="play an audio file instead of system audio (for testing)")
    run.add_argument("--no-overlay", action="store_true", help="don't open the panel")
    run.add_argument("--model", help="mlx-community Whisper model")
    run.add_argument("--copilot", action="store_true", help="run Claude Code in the background as the copilot")
    commands.add_parser("mcp", help="MCP server for Claude Code (stdio)")
    args = parser.parse_args()

    if args.command == "mcp":
        from .mcp_server import main as mcp_main

        mcp_main()
        return

    logging.basicConfig(
        # MIDAS_DEBUG=1 also logs what was said, for working on Midas; the log is otherwise
        # free of meeting content.
        level=logging.DEBUG if os.environ.get("MIDAS_DEBUG") else logging.INFO,
        format="%(asctime)s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stderr,
    )
    from .config import load_config
    from .daemon import Daemon

    config = load_config()
    if args.no_overlay:
        config.overlay = False
    if args.model:
        config.model = args.model
    Daemon(config, input_file=args.input, copilot=args.copilot).run()
    # Model download/inference pools would otherwise block interpreter exit.
    logging.shutdown()
    os._exit(0)


if __name__ == "__main__":
    main()
