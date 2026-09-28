import glob
import os
import re
import subprocess
import sys
import time

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(PROJECT, "automation-bridge-python"))
LOGS = os.path.join(PROJECT, "build", "bench_logs")


def newest_defold():
    root = os.path.expanduser("~/defold_engines")
    versions = sorted((d for d in os.listdir(root) if re.match(r"^\d+\.\d+\.\d+$", d)), key=lambda v: [int(p) for p in v.split(".")])
    return os.path.join(root, versions[-1])


BOB = os.environ.get("BOB", os.path.join(newest_defold(), "bob.jar"))


def bob(args, log_name):
    os.makedirs(LOGS, exist_ok=True)
    log = os.path.join(LOGS, log_name)
    with open(log, "w") as out:
        code = subprocess.run(["java", "-jar", BOB] + args, cwd=PROJECT, stdout=out, stderr=subprocess.STDOUT).returncode
    errors = [line for line in open(log, errors="ignore") if re.search(r"ERROR|error:|The build failed", line) and "protobuf" not in line]
    if code != 0 or errors:
        sys.exit("bob failed (%s):\n%s" % (log, "".join(errors[:20])))


def sleep(seconds):
    time.sleep(seconds)


def bench_lines(text):
    return [line.split("BENCH|", 1)[1].strip() for line in text.splitlines() if "BENCH|" in line]
