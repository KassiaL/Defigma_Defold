"""Android benchmark tools.

    python3 tools/bench/android.py build tests/results_screen/bench_settings_android.ini
    python3 tools/bench/android.py run [--serial <adb serial>] [--no-install] [--profile] [--out results.txt]

`build` bundles a debug APK for arm64-v8a and armeabi-v7a into bench_bundles/ (bob refuses
build/), signed with DEBUG_KEYSTORE (default: the Dexfut debug keystore). `run`
installs it (`--no-install` reuses the installed build, no MIUI prompt), starts it, streams logcat
into build/bench_logs/android_logcat.txt (the device ring buffer does not hold a whole run), waits
for BENCH|DONE and prints the BENCH lines; `--profile`
also forwards the engine service (8001) and Remotery (17815 -> 17899) ports and prints the
profiler scopes of every variant during its BENCH|HOLD window.
"""
import os
import subprocess
import sys

from common import LOGS, PROJECT, bench_lines, bob, sleep

OUT = os.path.join(PROJECT, "bench_bundles")
KEYSTORE = os.environ.get("DEBUG_KEYSTORE", os.path.expanduser("~/defold_projects/Dexfut/debug.keystore"))
PACKAGE = "com.defigma.bench"
ACTIVITY = PACKAGE + "/com.dynamo.android.DefoldActivity"


def adb(serial, *args, capture=True):
    command = ["adb"] + (["-s", serial] if serial else []) + list(args)
    return subprocess.run(command, capture_output=capture, text=True).stdout


def apk_path():
    for root, _, files in os.walk(OUT):
        for name in files:
            if name.endswith(".apk"):
                return os.path.join(root, name)
    sys.exit("no apk in " + OUT)


def cmd_build(settings):
    subprocess.run(["rm", "-rf", OUT])
    os.makedirs(OUT)
    bob(["--platform", "arm64-android", "--architectures", "arm64-android,armv7-android", "--variant", "debug", "--archive",
         "--texture-compression", "true", "--settings", settings, "--keystore", KEYSTORE, "--keystore-pass", KEYSTORE + ".pass.txt",
         "--bundle-output", OUT, "build", "bundle"], "bob_android.log")
    print("built", apk_path())


def cmd_run(args):
    serial = args[args.index("--serial") + 1] if "--serial" in args else None
    out = args[args.index("--out") + 1] if "--out" in args else None
    if "--no-install" not in args:
        install(serial)
    adb(serial, "shell", "am", "force-stop", PACKAGE)
    adb(serial, "logcat", "-c")
    log_path = os.path.join(LOGS, "android_logcat.txt")
    os.makedirs(LOGS, exist_ok=True)
    with open(log_path, "w") as log:
        command = ["adb"] + (["-s", serial] if serial else []) + ["logcat", "-v", "brief", "defold:V", "*:S"]
        stream = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        adb(serial, "shell", "input", "keyevent", "KEYCODE_WAKEUP")
        adb(serial, "shell", "am", "start", "-n", ACTIVITY)
        if "--profile" in args:
            profile(serial, log_path)
        text = wait_for(log_path, "BENCH|HOLD_DONE" if "--profile" in args else "BENCH|DONE")
        stream.terminate()
    adb(serial, "shell", "am", "force-stop", PACKAGE)
    lines = bench_lines(text)
    print("\n".join(lines))
    if "ERROR:CRASH" in text:
        print("CRASH, see: adb logcat -b crash")
    if out:
        open(out, "w").write("\n".join(lines) + "\n")


def install(serial):
    installed = adb(serial, "install", "-r", apk_path()).strip().splitlines()[-1]
    print(installed)
    if installed != "Success":
        sys.exit("install failed (MIUI: confirm the USB install prompt on the phone)")


def wait_for(log_path, marker):
    for _ in range(1800):
        text = open(log_path).read()
        if marker in text or "ERROR:CRASH" in text:
            return text
        sleep(1)
    return open(log_path).read()


def profile(serial, log_path):
    sys.path.insert(0, os.path.join(PROJECT, "automation-bridge-python"))
    from automation_bridge import engine
    from desktop import print_profile
    adb(serial, "forward", "tcp:8001", "tcp:8001")
    adb(serial, "forward", "tcp:17899", "tcp:17815")
    seen = set()
    for _ in range(3600):
        text = open(log_path).read()
        holds = [line.split("BENCH|HOLD|", 1)[1].strip() for line in text.splitlines() if "BENCH|HOLD|" in line]
        new = [h for h in holds if h not in seen]
        if new:
            seen.add(new[-1])
            sleep(3)
            game = engine.connect(8001)
            game._remotery_url = "ws://127.0.0.1:17899/rmt"
            print("===== profile", new[-1], flush=True)
            print_profile(game.profiler.capture(frames=120, warmup_frames=20))
        if "BENCH|HOLD_DONE" in text or "ERROR:CRASH" in text:
            return
        sleep(1)


def main():
    command, args = sys.argv[1], sys.argv[2:]
    if command == "build":
        cmd_build(args[0])
    elif command == "run":
        cmd_run(args)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
