#!/usr/bin/env python3
"""Trellis daemon entrypoint."""

import argparse
import os
import signal
import sys
import warnings


BASE_DIR = os.path.dirname(__file__)


def configure_environment():
    """Configure ML backend environment before TRELLIS imports."""
    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
    os.environ.setdefault("ATTN_BACKEND", "sdpa")
    os.environ.setdefault("SPARSE_ATTN_BACKEND", "sdpa")
    if "SPARSE_CONV_BACKEND" not in os.environ:
        try:
            import flex_gemm  # noqa: F401
            os.environ["SPARSE_CONV_BACKEND"] = "flex_gemm"
        except (ImportError, RuntimeError):
            os.environ["SPARSE_CONV_BACKEND"] = "none"

    warnings.filterwarnings(
        "ignore",
        message=".*not currently supported on the MPS backend.*",
    )

    sys.path.insert(0, os.path.join(BASE_DIR, "TRELLIS.2"))
    sys.path.append(os.path.join(BASE_DIR, "stubs"))


def parse_args():
    """Parse daemon command-line arguments."""
    from daemon_pipeline import IDLE_TIMEOUT_SECONDS

    parser = argparse.ArgumentParser(description="Trellis 3D generation daemon")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run in mock mode without loading models",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=0,
        help="TCP port to listen on (0 = auto-assign)",
    )
    parser.add_argument(
        "--legacy",
        action="store_true",
        help="Use stdin/stdout mode instead of TCP",
    )
    parser.add_argument(
        "--idle-timeout",
        type=int,
        default=IDLE_TIMEOUT_SECONDS,
        help="Seconds of idle before auto-shutdown (0 = never)",
    )
    parser.add_argument(
        "--default-pipeline",
        type=str,
        default="512",
        choices=["512", "1024", "1024_cascade", "1536_cascade"],
        help="Default pipeline type for initial model loading",
    )
    return parser.parse_args()


def main():
    """Run TCP daemon or legacy stdio mode."""
    configure_environment()

    from daemon_legacy import run_legacy_mode
    from daemon_server import DaemonServer

    args = parse_args()

    def sigterm_handler(signum, frame):
        sys.exit(0)

    signal.signal(signal.SIGTERM, sigterm_handler)

    if args.legacy:
        run_legacy_mode(args)
        return

    server = DaemonServer(args, idle_timeout=args.idle_timeout)
    server.start(port=args.port)


if __name__ == "__main__":
    main()
