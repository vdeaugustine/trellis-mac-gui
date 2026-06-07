"""TCP server for persistent JSON-over-TCP daemon communication."""

import json
import os
import socket
import time

import daemon_transport
from daemon_generation import handle_generate
from daemon_pipeline import (
    APP_SUPPORT_DIR,
    IDLE_TIMEOUT_SECONDS,
    PID_FILE,
    PORT_FILE,
    load_pipeline,
)
from daemon_transport import send_response


class DaemonServer:
    """TCP server that handles one client at a time and persists between jobs."""

    def __init__(self, args, idle_timeout=IDLE_TIMEOUT_SECONDS):
        self.args = args
        self.idle_timeout = idle_timeout
        self.pipeline = None
        self.pipeline_loaded = False
        self.pipeline_type = args.default_pipeline
        self.server_socket = None
        self.running = True
        self.last_activity = time.time()

    def start(self, port=0):
        """Bind, write port/pid files, and enter accept loop."""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind(("127.0.0.1", port))
        self.server_socket.listen(1)
        self.server_socket.settimeout(60)

        actual_port = self.server_socket.getsockname()[1]
        os.makedirs(APP_SUPPORT_DIR, exist_ok=True)
        with open(PORT_FILE, "w") as file:
            file.write(str(actual_port))
        with open(PID_FILE, "w") as file:
            file.write(str(os.getpid()))

        send_response({
            "stage": "daemonStatus",
            "status": "ready",
            "pipeline_loaded": False,
            "port": actual_port,
            "message": "Daemon listening. Pipeline loads on first generation.",
        })
        self._accept_loop()

    def _accept_loop(self):
        while self.running:
            try:
                conn, _ = self.server_socket.accept()
            except socket.timeout:
                if self._check_idle_timeout():
                    break
                continue
            except OSError:
                break

            self.last_activity = time.time()
            self._handle_client(conn)

        self._cleanup()

    def _handle_client(self, conn):
        def client_send(data):
            try:
                line = json.dumps({"response": data}) + "\n"
                conn.sendall(line.encode("utf-8"))
            except (BrokenPipeError, ConnectionResetError, OSError):
                pass

        with daemon_transport._send_lock:
            daemon_transport._active_client_send = client_send

        client_send({
            "stage": "daemonStatus",
            "status": "ready",
            "pipeline_loaded": self.pipeline_loaded,
        })

        buffer = b""
        conn.settimeout(5)
        while self.running:
            try:
                data = conn.recv(8192)
            except socket.timeout:
                self.last_activity = time.time()
                continue
            except (ConnectionResetError, OSError):
                break

            if not data:
                break

            buffer += data
            while b"\n" in buffer:
                line_bytes, buffer = buffer.split(b"\n", 1)
                line = line_bytes.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                self.last_activity = time.time()
                if self._process_message(line):
                    self.running = False
                    break

        with daemon_transport._send_lock:
            daemon_transport._active_client_send = None
        try:
            conn.close()
        except OSError:
            pass

    def _process_message(self, line):
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as error:
            send_response({
                "stage": "failed",
                "reason": "invalid_json",
                "message": str(error),
            })
            return False

        command = msg.get("command")
        if not command:
            return False

        name = command.get("command")
        if name == "shutdown":
            send_response({"stage": "shutdown", "status": "done"})
            return True
        if name == "status":
            send_response({
                "stage": "daemonStatus",
                "status": "ready",
                "pipeline_loaded": self.pipeline_loaded,
            })
            return False
        if name == "generate":
            self._generate(command)
        return False

    def _generate(self, command):
        pipeline_type = command.get("pipeline_type", self.pipeline_type)
        if not self.pipeline_loaded:
            try:
                self.pipeline = load_pipeline(self.args, pipeline_type=pipeline_type)
                self.pipeline_loaded = True
            except Exception:
                return
        self.pipeline_type = pipeline_type
        handle_generate(command, self.pipeline, self.args)

    def _check_idle_timeout(self):
        if self.idle_timeout <= 0:
            return False
        elapsed = time.time() - self.last_activity
        if elapsed <= self.idle_timeout:
            return False
        send_response({
            "stage": "shutdown",
            "status": "done",
            "reason": "idle_timeout",
            "message": f"Shutting down after {int(elapsed)}s idle",
        })
        return True

    def _cleanup(self):
        for path in (PORT_FILE, PID_FILE):
            try:
                os.remove(path)
            except OSError:
                pass
        if self.server_socket:
            try:
                self.server_socket.close()
            except OSError:
                pass
