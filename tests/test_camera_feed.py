#!/usr/bin/env python3
"""Camera-feed lifecycle regression tests using only temporary fake programs."""

import fcntl
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "bin/camera-feed"

HELPER = r'''#!/usr/bin/env python3
import fcntl, json, os, signal, sys, time
from pathlib import Path
events = Path(os.environ["FAKE_EVENTS"])
def record(kind):
    with events.open("a") as output:
        output.write(json.dumps({"event": kind, "pid": os.getpid(), "args": sys.argv[1:]}) + "\n")
lock = open(Path(os.environ["XDG_RUNTIME_DIR"]) / "surface-camera.lock", "a")
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit("fake helper: camera is busy")
record("start")
def stopped(signum, frame):
    record("stop")
    sys.exit(0)
signal.signal(signal.SIGINT, stopped)
signal.signal(signal.SIGTERM, stopped)
if os.environ.get("FAKE_MODE") == "failure":
    print("fake helper: requested startup failure", flush=True)
    sys.exit(4)
if os.environ.get("FAKE_MODE") != "starting":
    print("Redistribute latency...", flush=True)
while True:
    time.sleep(0.1)
'''

V4L2 = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with Path(os.environ["FAKE_EVENTS"]).open("a") as output:
    output.write(json.dumps({"event": "verify", "pid": os.getpid(), "args": sys.argv[1:]}) + "\n")
sys.exit(int(os.environ.get("FAKE_VERIFY_STATUS", "0")))
'''


class Harness:
    def __init__(self, mode="normal", verify_status=0):
        self.temporary = tempfile.TemporaryDirectory(prefix="camera-feed-tests-")
        self.base = Path(self.temporary.name)
        self.runtime = self.base / "runtime"
        self.runtime.mkdir(mode=0o700)
        self.events_file = self.base / "events.jsonl"
        shutil.copyfile(SOURCE, self.base / "camera-feed")
        for name, contents in (("surface-camera", HELPER), ("v4l2-ctl", V4L2)):
            target = self.base / name
            target.write_text(contents)
            target.chmod(0o700)
        self.env = {
            **os.environ,
            "PATH": str(self.base) + os.pathsep + os.environ["PATH"],
            "XDG_RUNTIME_DIR": str(self.runtime),
            "XDG_STATE_HOME": str(self.base / "state"),
            "FAKE_EVENTS": str(self.events_file),
            "FAKE_MODE": mode,
            "FAKE_VERIFY_STATUS": str(verify_status),
            "PYTHONUNBUFFERED": "1",
        }
        self.children = []
        self.output = {}

    def launch(self):
        process = subprocess.Popen(
            [sys.executable, str(self.base / "camera-feed")],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            env=self.env, start_new_session=True,
        )
        self.children.append(process)
        self.output[process.pid] = b""
        return process

    def send(self, process, commands):
        process.stdin.write(commands.encode())
        process.stdin.flush()

    def wait_text(self, process, fragment, timeout=4):
        deadline = time.monotonic() + timeout
        expected = fragment.encode()
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while expected not in self.output[process.pid]:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise AssertionError(f"Missing {fragment!r}: {self.output[process.pid].decode()}")
                for key, _ in selector.select(remaining):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        raise AssertionError(f"Exited before {fragment!r}: {self.output[process.pid].decode()}")
                    self.output[process.pid] += chunk
        return self.output[process.pid].decode()

    def finish(self, process, commands="quit\n"):
        if commands:
            self.send(process, commands)
        output, _ = process.communicate(timeout=7)
        self.output[process.pid] += output
        return self.output[process.pid].decode()

    def events(self, kind=None):
        rows = [json.loads(line) for line in self.events_file.read_text().splitlines()] if self.events_file.exists() else []
        return [row for row in rows if row["event"] == kind] if kind else rows

    def wait_event(self, kind, count=1, timeout=4):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if len(self.events(kind)) >= count:
                return
            time.sleep(0.02)
        raise AssertionError(f"Missing fake {kind} event: {self.events()}")

    def cleanup(self):
        for process in self.children:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=7)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)
            for stream in (process.stdin, process.stdout):
                if stream is not None:
                    stream.close()
        # On a failed regression, clean up only explicitly recorded fake PIDs.
        for event in self.events("start"):
            try:
                cmdline = Path(f"/proc/{event['pid']}/cmdline").read_bytes()
                if str(self.base / "surface-camera").encode() in cmdline:
                    os.kill(event["pid"], signal.SIGKILL)
            except (FileNotFoundError, ProcessLookupError):
                pass
        self.temporary.cleanup()


class CameraFeedTests(unittest.TestCase):
    def harness(self, **kwargs):
        harness = Harness(**kwargs)
        self.addCleanup(harness.cleanup)
        return harness

    def assert_helper_stopped(self, harness):
        self.assertEqual(len(harness.events("start")), len(harness.events("stop")))
        for event in harness.events("start"):
            self.assertFalse(Path(f"/proc/{event['pid']}").exists(), f"Fake helper {event['pid']} survived")

    def test_launch_does_not_capture(self):
        h = self.harness()
        app = h.launch()
        h.wait_text(app, "camera> ")
        self.assertEqual(h.events(), [])
        out = h.finish(app, "status\nquit\n")
        self.assertEqual(h.events(), [])
        self.assertIn("Camera is CLOSED.", out)
        self.assertEqual(app.returncode, 0)

    def test_open_close_are_repeatable_and_idempotent(self):
        h = self.harness()
        app = h.launch()
        out = h.finish(app, "open\nopen\nstatus\nclose\nclose\nopen\nclose\nquit\n")
        self.assertEqual(app.returncode, 0, out)
        self.assertEqual(len(h.events("start")), 2)
        self.assertEqual(len(h.events("verify")), 2)
        self.assertTrue(all(e["args"] == ["webcam", "front"] for e in h.events("start")))
        self.assertIn("Camera is already open.", out)
        self.assertIn("Camera is already closed.", out)
        self.assert_helper_stopped(h)

    def test_startup_failure_returns_to_prompt(self):
        h = self.harness(mode="failure")
        app = h.launch()
        out = h.finish(app, "open\nstatus\nquit\n")
        self.assertEqual(app.returncode, 0, out)
        self.assertIn("Camera could not start.", out)
        self.assertIn("fake helper: requested startup failure", out)
        self.assertEqual(h.events("verify"), [])
        self.assertFalse(Path(f"/proc/{h.events('start')[0]['pid']}").exists())

    def test_failed_frame_verification_stops_helper(self):
        h = self.harness(verify_status=1)
        app = h.launch()
        out = h.finish(app, "open\nquit\n")
        self.assertEqual(app.returncode, 0, out)
        self.assertIn("live frames could not be verified", out)
        self.assert_helper_stopped(h)

    def test_eof_stops_owned_helper(self):
        h = self.harness()
        app = h.launch()
        h.send(app, "open\n")
        h.wait_text(app, "Camera is OPEN.")
        out = h.finish(app, commands="")
        self.assertEqual(app.returncode, 0, out)
        self.assert_helper_stopped(h)

    def test_sighup_stops_owned_helper(self):
        h = self.harness()
        app = h.launch()
        h.send(app, "open\n")
        h.wait_text(app, "Camera is OPEN.")
        app.send_signal(signal.SIGHUP)
        out = h.finish(app, commands="")
        self.assertEqual(app.returncode, 0, out)
        self.assert_helper_stopped(h)

    def test_sighup_during_startup_stops_owned_helper(self):
        h = self.harness(mode="starting")
        app = h.launch()
        h.send(app, "open\n")
        h.wait_event("start")
        app.send_signal(signal.SIGHUP)
        out = h.finish(app, commands="")
        self.assertEqual(app.returncode, 0, out)
        self.assert_helper_stopped(h)

    def test_sigterm_stops_owned_helper(self):
        h = self.harness()
        app = h.launch()
        h.send(app, "open\n")
        h.wait_text(app, "Camera is OPEN.")
        app.send_signal(signal.SIGTERM)
        out = h.finish(app, commands="")
        self.assertEqual(app.returncode, 0, out)
        self.assert_helper_stopped(h)

    def test_ctrl_c_cancels_startup_and_preserves_controller(self):
        h = self.harness(mode="starting")
        app = h.launch()
        h.send(app, "open\n")
        h.wait_event("start")
        app.send_signal(signal.SIGINT)
        h.wait_text(app, "Camera is CLOSED.")
        self.assertIsNone(app.poll())
        out = h.finish(app)
        self.assertEqual(app.returncode, 0, out)
        self.assert_helper_stopped(h)

    def test_external_capture_lock_is_respected(self):
        h = self.harness()
        with (h.runtime / "surface-camera.lock").open("a") as external_lock:
            fcntl.flock(external_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            app = h.launch()
            out = h.finish(app, "open\nclose\nquit\n")
        self.assertEqual(app.returncode, 0, out)
        self.assertIn("Another camera command is running", out)
        self.assertIn("Another terminal owns the camera feed", out)
        self.assertEqual(h.events(), [])

    def test_duplicate_controller_cannot_start_or_stop_feed(self):
        h = self.harness()
        first = h.launch()
        h.send(first, "open\n")
        h.wait_text(first, "Camera is OPEN.")
        second = h.launch()
        out = h.finish(second, commands="")
        self.assertEqual(second.returncode, 0, out)
        self.assertIn("already open in another window", out)
        self.assertEqual(len(h.events("start")), 1)
        self.assertEqual(h.events("stop"), [])
        h.finish(first)
        self.assert_helper_stopped(h)


if __name__ == "__main__":
    unittest.main(verbosity=2)
