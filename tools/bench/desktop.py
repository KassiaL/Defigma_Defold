"""Desktop benchmark tools (Linux, debug engine).

    python3 tools/bench/desktop.py build   tests/results_screen/bench_settings.ini
    python3 tools/bench/desktop.py run     [--size 486x1035] [--out results.txt]
    python3 tools/bench/desktop.py shot    <variant> <width>x<height> <out.png>
    python3 tools/bench/desktop.py profile <variant>:<layers>:<moving 0|1>

`build` compiles the scene named by the settings file into build/default. `run` executes the whole
benchmark and prints the BENCH lines, `shot` keeps one variant on screen and saves a screenshot at
the given window size, `profile` keeps one variant and prints the engine profiler scopes
(Remotery on port 17899, so another running engine on the default port does not interfere).
"""
import os
import re
import subprocess
import sys

from common import LOGS, PROJECT, bench_lines, bob, sleep
from automation_bridge import engine

ENGINE = os.path.join(PROJECT, "build", "x86_64-linux", "dmengine")


def launch(config, log_name):
    os.chmod(ENGINE, 0o755)
    os.makedirs(LOGS, exist_ok=True)
    log = os.path.join(LOGS, log_name)
    env = dict(os.environ, DM_SERVICE_PORT="dynamic")
    process = subprocess.Popen([ENGINE, "build/default/game.projectc"] + ["--config=%s" % c for c in config], cwd=PROJECT, env=env,
                               stdout=open(log, "w"), stderr=subprocess.STDOUT)
    for _ in range(60):
        match = re.search(r"Engine service started on port (\d+)", open(log, errors="ignore").read())
        if match:
            return process, log, int(match.group(1))
        sleep(0.5)
    process.kill()
    sys.exit("engine did not start, see " + log)


def close(process, port):
    engine.connect(port).close_engine()
    process.wait()


def cmd_build(settings):
    bob(["--platform", "x86_64-linux", "--variant", "debug", "--archive=false", "--settings", settings, "build"], "bob_desktop.log")
    print("built", settings)


def cmd_run(args):
    size = "486x1035"
    out = None
    if "--size" in args:
        size = args[args.index("--size") + 1]
    if "--out" in args:
        out = args[args.index("--out") + 1]
    width, height = size.split("x")
    process, log, port = launch(["display.width=" + width, "display.height=" + height], "bench_desktop.log")
    for _ in range(1200):
        if "BENCH|DONE" in open(log, errors="ignore").read():
            break
        sleep(1)
    close(process, port)
    lines = bench_lines(open(log, errors="ignore").read())
    print("\n".join(lines))
    if out:
        open(out, "w").write("\n".join(lines) + "\n")


def cmd_shot(variant, size, out):
    width, height = [int(v) for v in size.split("x")]
    process, _, port = launch(["bench.hold=%s:1:0" % variant, "display.update_frequency=60"], "bench_shot.log")
    sleep(2)
    game = engine.connect(port)
    game.resize(width, height)
    shot = game.screenshot(wait=True, after_frames=10)
    open(out, "wb").write(shot.read_bytes())
    print(out, shot.width, shot.height)
    close(process, port)


def print_profile(capture):
    rows = sorted(((s.path, s.self.avg_us / 1000, s.total.avg_us / 1000) for s in capture.scopes()), key=lambda r: -r[2])
    keys = ("Step", "OpenGLFlip", "RenderNodes", "OpenGLSetVertexBufferData", "DefigmaShape", "OpenGLDraw", "RunScript", "CalcVertexCount")
    for path, self_ms, total_ms in rows:
        if path == "Step" or any(path.endswith(k) for k in keys[1:]) or "gui_script" in path:
            print("%-70s self %6.3f total %6.3f" % (path[-70:], self_ms, total_ms))
    for counter in capture.counters():
        if any(k in counter.path for k in ("DrawCalls", "GuiVertexCount")):
            print("counter %s %d" % (counter.path.split("/")[-1], round(counter.values.avg)))


def cmd_profile(hold):
    process, _, port = launch(["bench.hold=" + hold, "profiler.remotery_port=17899", "display.width=486", "display.height=1035"], "bench_profile.log")
    sleep(4)
    game = engine.connect(port)
    game._remotery_url = "ws://127.0.0.1:17899/rmt"
    print_profile(game.profiler.capture(frames=300, warmup_frames=60))
    close(process, port)


def main():
    command, args = sys.argv[1], sys.argv[2:]
    if command == "build":
        cmd_build(args[0])
    elif command == "run":
        cmd_run(args)
    elif command == "shot":
        cmd_shot(*args)
    elif command == "profile":
        cmd_profile(args[0])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
