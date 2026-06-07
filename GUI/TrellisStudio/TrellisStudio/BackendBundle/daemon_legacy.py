"""Legacy stdin/stdout JSON protocol for fallback daemon mode."""

import json
import sys

from daemon_generation import handle_generate
from daemon_pipeline import load_pipeline
from daemon_transport import send_response


def run_legacy_mode(args):
    """Run original stdin/stdout JSON protocol."""
    send_response({
        "stage": "daemonStatus",
        "status": "ready",
        "pipeline_loaded": False,
        "message": "Daemon ready (legacy mode). Pipeline loads on first generation.",
    })
    pipeline = None
    pipeline_loaded = False

    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            command = _decode_command(line)
            if not command:
                continue
            name = command.get("command")
            if name == "shutdown":
                send_response({"stage": "shutdown", "status": "done"})
                break
            if name == "status":
                send_response({
                    "stage": "daemonStatus",
                    "status": "ready",
                    "pipeline_loaded": pipeline_loaded,
                })
                continue
            if name == "generate":
                if not pipeline_loaded:
                    pipeline = load_pipeline(
                        args,
                        pipeline_type=command.get("pipeline_type", "512"),
                    )
                    pipeline_loaded = True
                handle_generate(command, pipeline, args)
        except KeyboardInterrupt:
            break
        except Exception as error:
            send_response({
                "stage": "failed",
                "reason": "loop_error",
                "message": str(error),
            })


def _decode_command(line):
    line = line.strip()
    if not line:
        return None
    try:
        msg = json.loads(line)
    except json.JSONDecodeError as error:
        send_response({
            "stage": "failed",
            "reason": "invalid_json",
            "message": str(error),
        })
        return None
    return msg.get("command")
