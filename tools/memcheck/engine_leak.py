"""DefigmaShape leak stress on the Linux desktop engine (tests/leak_stress).

    python3 tools/memcheck/engine_leak.py build [--root DIR] [--variant debug|headless|release]
    python3 tools/memcheck/engine_leak.py run   [--root DIR] [--variant debug|headless|release] [--cycles N] [--frames N]
                                                [--ops size,clone,enable,layout|none]
                                                [--tool none|heaptrack|valgrind] [--out DIR] [--snapshot-exit]

`build` compiles the stress scene into build/leak (the benchmark build in build/default is left
alone). `run` starts the engine, optionally under heaptrack or valgrind, waits for the scene to exit
by itself and prints the per-cycle memory, the trend after warm-up and the leak report lines that
come from the extension. `--snapshot-exit` leaves with `os.exit` instead of `sys.exit`, so nothing
is torn down and heaptrack reports everything alive after the last unload as leaked: diff two runs
of different length with `heaptrack_print -d short.zst -f long.zst -l` to see what grows. `--root` builds and runs a copy of the project (a snapshot taken while
other sources are being edited).
"""
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bench"))
from common import BOB, PROJECT

SETTINGS = "tests/leak_stress/leak_settings.ini"
OUTPUT = "build/leak/default"
BINARIES = "build/leak"
WARMUP_CYCLES = 5
EXTENSION_FRAMES = ("dmDefigma", "defigma::")


def option(args, name, default):
    return args[args.index(name) + 1] if name in args else default


def engine_path(root, variant, suffix=""):
    return os.path.join(root, BINARIES, variant, "x86_64-linux", "dmengine" + suffix)


def cmd_build(root, variant):
    log = os.path.join(root, BINARIES, "bob_%s.log" % variant)
    os.makedirs(os.path.dirname(log), exist_ok=True)
    args = ["java", "-jar", BOB, "--platform", "x86_64-linux", "--variant", variant, "--archive=false", "--settings", SETTINGS,
            "--output", OUTPUT, "--binary-output", os.path.join(BINARIES, variant), "build"]
    code = subprocess.run(args, cwd=root, stdout=open(log, "w"), stderr=subprocess.STDOUT).returncode
    if code != 0:
        sys.exit("bob failed, see " + log)
    print("built", engine_path(root, variant))


def wrapper(tool, out):
    if tool == "heaptrack":
        return ["heaptrack", "-o", os.path.join(out, "heaptrack.leak")]
    if tool == "valgrind":
        return ["valgrind", "--leak-check=full", "--show-leak-kinds=definite,indirect,possible", "--num-callers=40",
                "--log-file=" + os.path.join(out, "valgrind.txt")]
    return []


def wait_exit(process, log, timeout):
    started = time.time()
    while process.poll() is None:
        if time.time() - started > timeout:
            port = re.search(r"Engine service started on port (\d+)", open(log, errors="ignore").read())
            if port:
                sys.path.insert(0, os.path.join(PROJECT, "automation-bridge-python"))
                from automation_bridge import engine
                engine.connect(int(port.group(1))).close_engine()
            else:
                process.terminate()
            process.wait()
            print("timeout: engine closed through the bridge")
            break
        time.sleep(1)


def fit_slope(points):
    n = len(points)
    mean_x = sum(x for x, _ in points) / n
    mean_y = sum(y for _, y in points) / n
    return sum((x - mean_x) * (y - mean_y) for x, y in points) / sum((x - mean_x) ** 2 for x, _ in points)


def parse(log):
    rows = {"CYCLE": [], "LOADED": []}
    for line in open(log, errors="ignore"):
        match = re.search(r"LEAK\|(CYCLE|LOADED)\|(\d+)\|lua_kb=([\d.]+)\|mem_kb=(\d+)\|rss_kb=(\d+)", line)
        if match:
            rows[match.group(1)].append((int(match.group(2)), float(match.group(3)), float(match.group(4)), float(match.group(5))))
    return rows


def summarize(name, rows):
    if len(rows) <= WARMUP_CYCLES + 1:
        print("%s: %d cycles, too few for a trend" % (name, len(rows)))
        return
    steady = rows[WARMUP_CYCLES:]
    for label, column in (("profiler", 2), ("rss", 3), ("lua", 1)):
        print("%s %s KB: start %.0f, after warm-up (cycle %d) %.0f, end (cycle %d) %.0f, slope %.2f KB/cycle over %d cycles" % (
            name, label, rows[0][column], steady[0][0], steady[0][column], steady[-1][0], steady[-1][column],
            fit_slope([(r[0], r[column]) for r in steady]), len(steady)))


def extension_report(tool, out):
    if tool == "heaptrack":
        data = next(os.path.join(out, f) for f in sorted(os.listdir(out)) if f.startswith("heaptrack.leak"))
        text = subprocess.run(["heaptrack_print", "-f", data, "-l", "-p", "0", "-a", "0", "-T", "0"], capture_output=True, text=True).stdout
        open(os.path.join(out, "heaptrack_leaks.txt"), "w").write(text)
        print("\n".join(line for line in text.splitlines() if line.startswith(("total runtime", "calls to allocation", "peak heap", "total memory leaked"))))
        blocks = text.split("\n\n")
        hits = [b for b in blocks if any(k in b for k in EXTENSION_FRAMES)]
        print("heaptrack leak backtraces through the extension: %d" % len(hits))
        print("\n\n".join(hits[:10]))
    elif tool == "valgrind":
        text = open(os.path.join(out, "valgrind.txt"), errors="ignore").read()
        print("\n".join(line for line in text.splitlines() if re.search(r"(definitely|indirectly|possibly) lost:|ERROR SUMMARY|Invalid (read|write)", line)))
        records = re.split(r"\n==\d+== \n", text)
        hits = [r for r in records if any(k in r for k in EXTENSION_FRAMES) and re.search(r"lost in loss record|Invalid|uninitialised", r)]
        print("valgrind records through the extension: %d" % len(hits))
        print("\n\n".join(hits[:10]))


def cmd_run(root, variant, args):
    tool = option(args, "--tool", "none")
    out = os.path.abspath(option(args, "--out", os.path.join(root, BINARIES, "run_" + tool)))
    os.makedirs(out, exist_ok=True)
    for name in os.listdir(out):
        os.remove(os.path.join(out, name))
    config = ["--config=leak.cycles=" + option(args, "--cycles", "40"), "--config=leak.frames=" + option(args, "--frames", "300"),
              "--config=leak.ops=" + option(args, "--ops", "size,clone,enable,layout"),
              "--config=leak.snapshot_exit=%d" % ("--snapshot-exit" in args)]
    engine = engine_path(root, variant, "" if tool == "none" else "_unstripped")
    os.chmod(engine, 0o755)
    log = os.path.join(out, "engine.log")
    env = dict(os.environ, DM_SERVICE_PORT="dynamic")
    command = wrapper(tool, out) + [engine] + config + [os.path.join(OUTPUT, "game.projectc")]
    process = subprocess.Popen(command, cwd=root, env=env, stdout=open(log, "w"), stderr=subprocess.STDOUT)
    wait_exit(process, log, float(option(args, "--timeout", "3600")))
    print("exit code %d, log %s" % (process.returncode, log))
    rows = parse(log)
    summarize("unloaded", rows["CYCLE"])
    summarize("loaded", rows["LOADED"])
    extension_report(tool, out)


def main():
    command, args = sys.argv[1], sys.argv[2:]
    root = os.path.abspath(option(args, "--root", PROJECT))
    variant = option(args, "--variant", "debug")
    if command == "build":
        cmd_build(root, variant)
    elif command == "run":
        cmd_run(root, variant, args)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
