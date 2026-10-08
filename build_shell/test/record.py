#!/usr/bin/env python3
"""record.py - records a video of the test instance of this checkout, wherever it runs.

    build_shell/test/record.py start <clip>.mp4     returns at once, the recording goes on
    ...drive the game through the automation bridge...
    build_shell/test/record.py stop                 finishes it; the clip is then at <clip>.mp4 here
    build_shell/test/record.py <clip>.mp4 --seconds 5   records 5 seconds and returns

The same commands work wherever `test_instance.sh` started the engine; the script finds it through
`.internal/test_instance/` (engine.pid, engine.port, remote.json) and picks the way to record:
  - Linux, this PC: ffmpeg x11grab of the engine window on its invisible run-test-env display, with the
    sound of the instance from its null sink (`test-<instance>.monitor`, run-test-env).
  - Linux test host: the same ffmpeg over `ssh <alias>` there; the clip is copied here.
  - macOS, Windows (this PC or a test host): the native recorder of the automation bridge in the engine
    (/recording/start, /recording/stop); a clip of a test host comes back through its test host agent.
    The instance is muted there, so these clips have no sound: a task that needs it runs on Linux
    (`TEST_SOUND=1 build_shell/test/test_instance.sh`).
Prints the path of the finished clip and whether it has sound. Python 3.9+, standard library only.
Shared by every Defold project and synced by sync_defold_docs.py.
"""

import argparse
import json
import os
import platform
import re
import shlex
import signal
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUN_DIR = ROOT / ".internal" / "test_instance"
STATE = RUN_DIR / "recording.json"
REMOTE = RUN_DIR / "remote.json"
FPS = 60
AGENT_PORT = 47800
VIDEO = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "16", "-pix_fmt", "yuv420p"]
AUDIO = ["-c:a", "aac", "-b:a", "192k"]


def instance():
    return os.environ.get("TEST_INSTANCE", ROOT.name)


def engine_port():
    return int((RUN_DIR / "engine.port").read_text())


def bridge(path, body=None):
    body = {} if body is None else body
    request = urllib.request.Request(
        f"http://127.0.0.1:{engine_port()}/automation-bridge/v1{path}",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    return json.loads(urllib.request.urlopen(request, timeout=60).read() or b"{}")


def remote():
    return json.loads(REMOTE.read_text()) if REMOTE.exists() else None


def native_system(host):
    system = host["os"] if host else platform.system()
    return system in ("Darwin", "Windows")


class Shell:
    def __init__(self, host):
        self.alias = host["alias"] if host else None
        self.display = host["display"] if host else ""

    def command(self, *args):
        with_display = ["env", f"DISPLAY={self.display}", *args] if self.display else list(args)
        if self.alias is None:
            return with_display
        return ["ssh", self.alias, shlex.join(with_display)]

    def run(self, *args):
        return subprocess.run(self.command(*args), check=True, capture_output=True, text=True).stdout

    def background(self, command, log):
        if self.alias is None:
            with open(log, "wb") as output:
                process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=output, stderr=output,
                                           start_new_session=True)
            return process.pid
        line = f"nohup {shlex.join(command)} </dev/null >{shlex.quote(log)} 2>&1 & echo $!"
        return int(self.run("sh", "-c", line).strip())

    def running(self, pid):
        return subprocess.run(self.command("kill", "-0", str(pid)), capture_output=True).returncode == 0

    def read(self, path):
        return self.run("cat", path)


def engine_pid(shell, host):
    pid_file = host["pid_file"] if host else str(RUN_DIR / "engine.pid")
    return int(shell.read(pid_file).strip())


def engine_display(shell, pid, host):
    if host:
        return host["display"]
    variables = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
    return next(variable[len(b"DISPLAY="):].decode() for variable in variables if variable.startswith(b"DISPLAY="))


def window_area(shell, window_id):
    info = shell.run("xwininfo", "-id", window_id)
    if "IsViewable" not in info:
        return 0
    return int(re.search(r"Width:\s+(\d+)", info).group(1)) * int(re.search(r"Height:\s+(\d+)", info).group(1))


def engine_window(shell, pid):
    ids = subprocess.run(shell.command("xdotool", "search", "--pid", str(pid)), capture_output=True, text=True).stdout.split()
    areas = {window_id: window_area(shell, window_id) for window_id in ids}
    best = max(areas, key=areas.get, default=None)
    if not best or not areas[best]:
        raise SystemExit(f"record.py: engine {pid} has no visible window")
    return best


def sound_source(shell):
    source = f"test-{instance()}.monitor"
    sources = subprocess.run(shell.command("pactl", "list", "short", "sources"), capture_output=True, text=True).stdout
    return source if any(line.split()[1:2] == [source] for line in sources.splitlines()) else None


def start_ffmpeg(host, out):
    shell = Shell(host)
    pid = engine_pid(shell, host)
    display = engine_display(shell, pid, host)
    shell.display = display
    window = engine_window(shell, pid)
    source = sound_source(shell)
    target = f"/tmp/record-{instance()}-{os.getpid()}.mp4" if host else str(out)
    command = ["ffmpeg", "-hide_banner", "-nostats", "-y",
               "-f", "x11grab", "-window_id", window, "-framerate", str(FPS), "-draw_mouse", "0", "-i", display]
    if source:
        command += ["-f", "pulse", "-i", source]
    command += VIDEO + (AUDIO if source else []) + [target]
    log = f"{target}.log" if host else str(RUN_DIR / "record.log")
    return {"backend": "ffmpeg", "pid": shell.background(command, log), "target": target, "log": log,
            "sound": bool(source)}


def agent_file_url(host, path):
    return f"http://{host['address']}:{AGENT_PORT}/file?" + urllib.parse.urlencode({"path": path})


def start_native(host, out):
    if host:
        separator = "\\" if host["os"] == "Windows" else "/"
        target = f"{host['temp_dir']}{separator}record-{instance()}-{os.getpid()}.mp4"
    else:
        target = str(out)
    bridge("/recording/start", {"path": target, "fps": FPS, "audio": False})
    return {"backend": "native", "target": target, "sound": False}


def start(out):
    if STATE.exists():
        raise SystemExit(f"record.py: a recording is already running ({STATE}), stop it first")
    host = remote()
    out = out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    state = start_native(host, out) if native_system(host) else start_ffmpeg(host, out)
    state["out"] = str(out)
    STATE.write_text(json.dumps(state))
    if state["backend"] == "ffmpeg":
        time.sleep(1.0)
        if not Shell(host).running(state["pid"]):
            STATE.unlink()
            raise SystemExit("record.py: ffmpeg stopped at once:\n" + Shell(host).read(state["log"])[-2000:])


def stop_ffmpeg(host, state):
    shell = Shell(host)
    if host:
        shell.run("kill", "-INT", str(state["pid"]))
    else:
        os.kill(state["pid"], signal.SIGINT)
    deadline = time.monotonic() + 30
    while shell.running(state["pid"]) and time.monotonic() < deadline:
        time.sleep(0.2)
    if host:
        subprocess.run(["scp", "-q", f"{host['alias']}:{state['target']}", state["out"]], check=True)
        shell.run("rm", "-f", state["target"], state["log"])


def stop_native(host, state):
    bridge("/recording/stop")
    if not host:
        return
    url = agent_file_url(host, state["target"])
    Path(state["out"]).write_bytes(urllib.request.urlopen(url, timeout=120).read())
    urllib.request.urlopen(urllib.request.Request(url, method="DELETE"), timeout=30).read()


def stop():
    if not STATE.exists():
        raise SystemExit("record.py: no recording is running")
    state = json.loads(STATE.read_text())
    host = remote()
    if state["backend"] == "ffmpeg":
        stop_ffmpeg(host, state)
    else:
        stop_native(host, state)
    STATE.unlink()
    print(f"CLIP={state['out']}")
    print(f"CLIP_SOUND={'yes' if state['sound'] else 'no'}")


def main():
    arguments = sys.argv[1:]
    if arguments[:1] == ["stop"]:
        stop()
        return
    parser = argparse.ArgumentParser(description="Record a video of the test instance of this checkout.")
    parser.add_argument("out", type=Path)
    parser.add_argument("--seconds", type=float)
    if arguments[:1] == ["start"]:
        start(parser.parse_args(arguments[1:]).out)
        return
    args = parser.parse_args(arguments)
    if args.seconds is None:
        parser.error("give --seconds, or use start/stop")
    start(args.out)
    time.sleep(args.seconds)
    stop()


if __name__ == "__main__":
    main()
