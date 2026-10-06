#!/usr/bin/env python3
"""test_host.py - moves a build_shell/test/linux_test.sh run to another computer of the LAN when this
one is short of RAM.

WHY
  Several agents build and run test instances on the main PC at the same time. When its free RAM runs
  out, the next build is moved to a test host - a Linux PC or a Mac - while the agent keeps editing,
  building with git and driving the game from the main PC. Shared by every Defold project and synced by
  sync_defold_docs.py; how to set a test host up is md/shared/TEST_HOSTS.md.

HOW IT WORKS
  - Every test host runs `test_host.py agent` in the logged-in user session (systemd user unit,
    LaunchAgent), so the engine it starts gets the desktop and the GPU. It answers HTTP on TCP 47800 and
    the discovery broadcast on UDP 47800, both only from private (LAN) addresses.
  - linux_test.sh calls `pick`: enough MemAvailable here -> "local"; otherwise a UDP broadcast finds the
    test hosts of the LAN with their free RAM and the one with the most is printed. Nothing fits -> exit 3.
  - `run` first sends this file to the agent when its copy differs (`/update`, the agent restarts from
    systemd or launchd and keeps the engines it started), then snapshots the checkout as it is (uncommitted and untracked files included, ignored ones not)
    into a parentless commit through a temporary index, sends it as a git bundle that leaves out what the
    host already has, uploads bob.jar of the same Defold version once, and runs
    build_shell/test/linux_test.sh of that snapshot on the host (LINUX_TEST_HOST=local there).
  - `forward` is the local half of a remote instance, its pid is engine.pid of the checkout. It serves the
    engine service on a local port through the agent, so engine.connect(ENGINE_PORT) works unchanged:
    /info gets the port of a local relay to the engine log service, a finished screenshot is downloaded
    and its path rewritten to the local copy. It mirrors the engine log into ENGINE_LOG and relays the
    ports the project names in main_host_ports (local server, CDN) from the LAN address of this PC to
    127.0.0.1, accepting only the test host. SIGTERM stops the remote engine.

COMMANDS
  test host: `python3 test_host.py` installs (or updates) the agent with autostart and runs `check`;
             `check` prints what the host has, each line marked OK or FAIL.
  main PC:   `share` serves this file and prints the one-line install command for a test host;
             `hosts` lists the test hosts that answer the broadcast;
             `address <name>` prints the current IP of the test host whose name starts with <name>
             (the ProxyCommand of the ssh aliases in md/shared/TEST_HOSTS.md).
"""

import argparse
import base64
import ctypes
import ipaddress
import hashlib
import http.client
import http.server
import json
import os
import platform
import re
import secrets
import shutil
import signal
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

PROTOCOL = 2
AGENT_PORT = 47800
SHARE_PORT = 47801
MIN_FREE_MB = 6144
MIN_JAVA = 25
DISCOVERY_REQUEST = b"defold-test-host?"
AGENT_ROOT = Path.home() / "defold_test_host"
CONFIG_PATH = AGENT_ROOT / "config.json"
VIRTUALGL_DIR = Path("/opt/VirtualGL/bin")
VIRTUALGL_DEB = "https://github.com/VirtualGL/virtualgl/releases/download/3.1.5/virtualgl_3.1.5_amd64.deb"
NAME_PATTERN = re.compile(r"^[A-Za-z0-9._ -]+$")
SNAPSHOT_IDENTITY = {
    "GIT_AUTHOR_NAME": "test_host",
    "GIT_AUTHOR_EMAIL": "test_host@localhost",
    "GIT_AUTHOR_DATE": "1970-01-01T00:00:00+0000",
    "GIT_COMMITTER_NAME": "test_host",
    "GIT_COMMITTER_EMAIL": "test_host@localhost",
    "GIT_COMMITTER_DATE": "1970-01-01T00:00:00+0000",
}
FORWARDED_ENV = ("LINUX_RESET", "LINUX_CLEAN", "LINUX_BUILD_ONLY")


def fail(message, code=1):
    print(f"test_host: {message}", file=sys.stderr)
    sys.exit(code)


def load_config():
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def save_config(config):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")


def windows_memory_mb():
    class MemoryStatus(ctypes.Structure):
        _fields_ = [
            ("dwLength", ctypes.c_ulong),
            ("dwMemoryLoad", ctypes.c_ulong),
            ("ullTotalPhys", ctypes.c_ulonglong),
            ("ullAvailPhys", ctypes.c_ulonglong),
            ("ullTotalPageFile", ctypes.c_ulonglong),
            ("ullAvailPageFile", ctypes.c_ulonglong),
            ("ullTotalVirtual", ctypes.c_ulonglong),
            ("ullAvailVirtual", ctypes.c_ulonglong),
            ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
        ]

    status = MemoryStatus()
    status.dwLength = ctypes.sizeof(MemoryStatus)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status))
    return status.ullAvailPhys // 2**20, status.ullTotalPhys // 2**20


def macos_memory_mb():
    page_size = int(subprocess.check_output(["sysctl", "-n", "hw.pagesize"]).strip())
    total = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"]).strip())
    pages = {}
    for line in subprocess.check_output(["vm_stat"], text=True).splitlines()[1:]:
        key, _, value = line.partition(":")
        pages[key.strip()] = int(value.strip().rstrip("."))
    reclaimable = ("Pages free", "Pages inactive", "Pages speculative", "Pages purgeable")
    return sum(pages[key] for key in reclaimable) * page_size // 2**20, total // 2**20


def linux_memory_mb():
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, _, value = line.partition(":")
        values[key] = int(value.split()[0])
    return values["MemAvailable"] // 1024, values["MemTotal"] // 1024


def linux_process_sizes():
    sizes = {}
    for status_path in Path("/proc").glob("[0-9]*/status"):
        try:
            text = status_path.read_text()
        except OSError:
            continue
        name = re.search(r"^Name:\s*(.+)$", text, re.M)
        rss = re.search(r"^VmRSS:\s*(\d+)", text, re.M)
        if name and rss:
            sizes[name.group(1)] = sizes.get(name.group(1), 0) + int(rss.group(1)) // 1024
    return sizes


def macos_process_sizes():
    sizes = {}
    for line in subprocess.check_output(["ps", "-axo", "rss=,comm="], text=True).splitlines():
        rss, _, command = line.strip().partition(" ")
        name = command.strip().rsplit("/", 1)[-1]
        sizes[name] = sizes.get(name, 0) + int(rss) // 1024
    return sizes


def top_processes(count=5):
    system = platform.system()
    if system == "Linux":
        sizes = linux_process_sizes()
    elif system == "Darwin":
        sizes = macos_process_sizes()
    else:
        return []
    return sorted(sizes.items(), key=lambda item: item[1], reverse=True)[:count]


def memory_mb():
    system = platform.system()
    if system == "Windows":
        return windows_memory_mb()
    if system == "Darwin":
        return macos_memory_mb()
    return linux_memory_mb()


def script_sha():
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


RUNNING_SHA = script_sha()


def is_lan_address(address):
    return ipaddress.ip_address(address).is_private


def git(*args, cwd=None, env=None, text=True):
    return subprocess.run(
        ["git", *args], cwd=cwd, env=env, check=True, capture_output=True, text=text
    ).stdout


def check_name(name):
    if not NAME_PATTERN.match(name) or name in (".", ".."):
        raise ValueError(f"bad name {name!r}")
    return name


def pipe(source, target):
    try:
        while True:
            data = source.recv(65536)
            if not data:
                break
            target.sendall(data)
    except OSError:
        pass
    finally:
        for sock in (source, target):
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def splice(first, second):
    threading.Thread(target=pipe, args=(first, second), daemon=True).start()
    pipe(second, first)
    first.close()
    second.close()


class AgentClient:
    def __init__(self, address, timeout=30):
        host, _, port = address.partition(":")
        self.address = address
        self.host = host
        self.port = int(port or AGENT_PORT)
        self.timeout = timeout

    def request(self, method, path, params=None, body=None, timeout=None, headers=None):
        if params:
            path += "?" + urllib.parse.urlencode(params)
        connection = http.client.HTTPConnection(self.host, self.port, timeout=timeout or self.timeout)
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        data = response.read()
        connection.close()
        return response.status, response.getheaders(), data

    def json(self, method, path, params=None, payload=None, timeout=None):
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        status, _, data = self.request(method, path, params, body, timeout)
        if status != 200:
            raise RuntimeError(f"{self.address} {method} {path}: {status} {data.decode('utf-8', 'replace')}")
        return json.loads(data)

    def upload(self, path, params, file_path):
        size = os.path.getsize(file_path)
        with open(file_path, "rb") as handle:
            status, _, data = self.request(
                "POST", path, params, handle, timeout=3600, headers={"Content-Length": str(size)}
            )
        if status != 200:
            raise RuntimeError(f"{self.address} POST {path}: {status} {data.decode('utf-8', 'replace')}")

    def open_tunnel(self, path):
        sock = socket.create_connection((self.host, self.port), timeout=10)
        sock.sendall(f"CONNECT {path} HTTP/1.0\r\n\r\n".encode("ascii"))
        header = b""
        while b"\r\n\r\n" not in header:
            chunk = sock.recv(1)
            if not chunk:
                raise OSError("tunnel closed")
            header += chunk
        if not header.startswith(b"HTTP/1.0 200"):
            raise OSError(header.decode("ascii", "replace").splitlines()[0])
        sock.settimeout(None)
        return sock


def broadcast_addresses():
    addresses = {"255.255.255.255"}
    for command, pattern in (
        (["ip", "-4", "-o", "addr"], r"brd (\d+\.\d+\.\d+\.\d+)"),
        (["ifconfig"], r"broadcast (\d+\.\d+\.\d+\.\d+)"),
    ):
        if shutil.which(command[0]):
            output = subprocess.run(command, capture_output=True, text=True).stdout
            addresses.update(re.findall(pattern, output))
            break
    return sorted(addresses)


def discover(timeout=1.5):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(0.2)
    for address in broadcast_addresses():
        try:
            sock.sendto(DISCOVERY_REQUEST, (address, AGENT_PORT))
        except OSError:
            pass
    hosts = {}
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            data, (address, _) = sock.recvfrom(65536)
        except socket.timeout:
            continue
        hosts[address] = json.loads(data)
    sock.close()
    return hosts


def describe_host(address, status):
    return f"{status['name']} ({address}, {status['os']}) {status['mem_available_mb']} MB free"


def cmd_pick(_args):
    available, _ = memory_mb()
    if available >= MIN_FREE_MB:
        print("local")
        return
    hosts = discover()
    report = [f"this PC {available} MB free"]
    report += [describe_host(address, status) for address, status in hosts.items()]
    if not hosts:
        report.append("no test host answered in the LAN")
    fitting = [
        (status["mem_available_mb"], address, status)
        for address, status in hosts.items()
        if status["protocol"] >= PROTOCOL and status["mem_available_mb"] >= MIN_FREE_MB
    ]
    if not fitting:
        fail(
            f"not enough free RAM to start a test instance safely (needs {MIN_FREE_MB} MB): " + ", ".join(report),
            3,
        )
    _, address, status = max(fitting)
    print(
        f"test_host: this PC has {available} MB free (< {MIN_FREE_MB}), building on {describe_host(address, status)}",
        file=sys.stderr,
    )
    print(address)


def cmd_hosts(_args):
    available, total = memory_mb()
    print(f"this PC: {available} of {total} MB free, a test host is used below {MIN_FREE_MB} MB")
    hosts = discover()
    if not hosts:
        print("no test host answered in the LAN")
    for address, status in sorted(hosts.items()):
        protocol = "" if status["protocol"] >= PROTOCOL else f"  OLD AGENT (protocol {status['protocol']}), reinstall it"
        print(f"{describe_host(address, status)} of {status['mem_total_mb']} MB{protocol}")
        if "top_processes" in status:
            print("    most memory: " + ", ".join(f"{name} {size} MB" for name, size in status["top_processes"]))


def cmd_address(args):
    for address, status in discover().items():
        if status["name"].lower().startswith(args.name.lower()):
            print(address)
            return
    fail(f"no test host named {args.name} answered in the LAN")


def lan_addresses():
    output = subprocess.run(["ip", "-4", "-o", "addr", "show", "scope", "global"], capture_output=True, text=True).stdout
    addresses = sorted(set(re.findall(r"inet (\d+\.\d+\.\d+\.\d+)", output)))
    home = [address for address in addresses if address.startswith(("192.168.", "10."))]
    return home or addresses


def install_line(source):
    fetch = f'curl -fsSL {source} -o ~/test_host.py'
    linux = (
        "sudo apt update && sudo apt install -y git python3 openjdk-25-jdk xvfb curl libopenal1 libglu1-mesa"
        f" && curl -fsSLo /tmp/virtualgl.deb {VIRTUALGL_DEB} && sudo apt install -y /tmp/virtualgl.deb"
        f' && sudo loginctl enable-linger "$USER" && {fetch} && python3 ~/test_host.py'
    )
    mac = (
        "brew install bash openjdk python git"
        ' && sudo ln -sfn "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk.jdk'
        f' && sudo pmset -c sleep 0 && {fetch} && "$(brew --prefix)/bin/python3" ~/test_host.py'
    )
    return linux, mac


def cmd_share(_args):
    addresses = lan_addresses()
    linux, mac = install_line(f"http://{addresses[0]}:{SHARE_PORT}/test_host.py")
    print("Run on a Linux test host:\n")
    print(linux + "\n")
    print("Run on a Mac test host:\n")
    print(mac + "\n")
    if len(addresses) > 1:
        print(f"If {addresses[0]} is not reachable from there, use another address of this PC: {', '.join(addresses[1:])}")
    print("Ctrl+C stops serving the file.", flush=True)
    script = Path(__file__).read_bytes()

    class ShareHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            if self.path != "/test_host.py":
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/x-python")
            self.send_header("Content-Length", str(len(script)))
            self.end_headers()
            self.wfile.write(script)

    try:
        http.server.ThreadingHTTPServer(("0.0.0.0", SHARE_PORT), ShareHandler).serve_forever()
    except KeyboardInterrupt:
        pass


def project_name(root):
    common_dir = git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=root).strip()
    return Path(common_dir).parent.name


def make_snapshot(root, instance, run_dir):
    index_path = run_dir / "snapshot.index"
    shutil.copyfile(git("rev-parse", "--path-format=absolute", "--git-path", "index", cwd=root).strip(), index_path)
    env = {**os.environ, **SNAPSHOT_IDENTITY, "GIT_INDEX_FILE": str(index_path)}
    git("add", "--all", cwd=root, env=env)
    tree = git("write-tree", cwd=root, env=env).strip()
    index_path.unlink()
    commit = git("commit-tree", tree, "-m", "test_host snapshot", cwd=root, env=env).strip()
    git("update-ref", f"refs/test-host/{instance}", commit, cwd=root)
    return commit


def local_commit_exists(root, sha):
    return subprocess.run(
        ["git", "cat-file", "-e", f"{sha}^{{commit}}"], cwd=root, capture_output=True
    ).returncode == 0


def send_snapshot(client, root, project, instance, sha, run_dir):
    known = client.json("GET", "/snapshots", {"project": project})
    if sha in known:
        return
    bases = [f"^{base}" for base in known if local_commit_exists(root, base)]
    bundle_path = run_dir / "snapshot.bundle"
    git("bundle", "create", "--quiet", str(bundle_path), f"refs/test-host/{instance}", *bases, cwd=root)
    print(f"test_host: sending the snapshot ({os.path.getsize(bundle_path) // 2**20} MB)", file=sys.stderr)
    client.upload("/bundle", {"project": project, "instance": instance}, bundle_path)
    bundle_path.unlink()


def send_bob(client, bob, status):
    version = Path(bob).parent.name
    if version not in status["bob"]:
        print(f"test_host: sending bob.jar {version}", file=sys.stderr)
        client.upload("/bob", {"version": version}, bob)
    return version


def start_forwarder(args, project, run_dir):
    ready_path = run_dir / "forward.json"
    ready_path.unlink(missing_ok=True)
    command = [
        sys.executable, os.path.abspath(__file__), "forward",
        "--host", args.host, "--project", project, "--instance", args.instance,
        "--log", str(run_dir / "engine.log"), "--files", str(run_dir / "remote_files"),
        "--ready", str(ready_path),
    ]
    for port in args.main_port:
        command += ["--main-port", port]
    with open(run_dir / "forward.out", "wb") as output:
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=output, stderr=output, start_new_session=True)
    (run_dir / "engine.pid").write_text(f"{process.pid}\n")
    for _ in range(100):
        if ready_path.exists():
            return process, json.loads(ready_path.read_text())
        if process.poll() is not None:
            break
        time.sleep(0.1)
    process.kill()
    fail(f"forwarder did not start, see {run_dir / 'forward.out'}")


def stream_job(client, job):
    offset = 0
    pending = b""
    while True:
        state = client.json("GET", "/job", {"id": job, "offset": offset}, timeout=60)
        chunk = base64.b64decode(state["output"])
        offset += len(chunk)
        pending += chunk
        *lines, pending = pending.split(b"\n")
        for line in lines:
            if not line.startswith(b"ENGINE_"):
                sys.stdout.buffer.write(line + b"\n")
        sys.stdout.flush()
        if state["exit_code"] is not None and not chunk:
            sys.stdout.buffer.write(pending)
            sys.stdout.flush()
            return state["exit_code"]
        if not chunk:
            time.sleep(0.5)


def wait_engine(proxy_port):
    for _ in range(60):
        try:
            connection = http.client.HTTPConnection("127.0.0.1", proxy_port, timeout=5)
            connection.request("GET", "/info")
            if connection.getresponse().status == 200:
                return
        except OSError:
            pass
        time.sleep(0.5)
    fail("the remote engine does not answer through the forwarder")


def update_agent(client, status):
    if status["script_sha"] == script_sha():
        return
    print(f"test_host: updating the agent on {status['name']}", file=sys.stderr)
    client.upload("/update", {}, __file__)
    for _ in range(60):
        time.sleep(0.5)
        try:
            if client.json("GET", "/status", timeout=3)["script_sha"] == script_sha():
                return
        except (OSError, RuntimeError, ValueError):
            pass
    fail(f"the agent on {status['name']} did not come back after the update")


def cmd_run(args):
    root = Path(args.root)
    run_dir = Path(args.run_dir)
    client = AgentClient(args.host)
    status = client.json("GET", "/status")
    update_agent(client, status)
    project = project_name(root)
    sha = make_snapshot(root, args.instance, run_dir)
    send_snapshot(client, root, project, args.instance, sha, run_dir)
    bob_version = send_bob(client, args.bob, status)
    forwarder, ready = start_forwarder(args, project, run_dir)
    env = {name: os.environ[name] for name in FORWARDED_ENV if name in os.environ}
    env["TEST_MAIN_HOST"] = ready["lan_ip"]
    for port, relay in ready["main_ports"].items():
        env[f"TEST_MAIN_PORT_{port}"] = str(relay)
    job = client.json("POST", "/run", payload={
        "project": project, "instance": args.instance, "sha": sha,
        "bob_version": bob_version, "args": args.engine_args, "env": env,
    })["job"]
    (run_dir / "mirror.start").touch()
    exit_code = stream_job(client, job)
    if exit_code != 0 or os.environ.get("LINUX_BUILD_ONLY") == "1":
        forwarder.terminate()
        (run_dir / "engine.pid").unlink(missing_ok=True)
        sys.exit(exit_code)
    wait_engine(ready["proxy_port"])
    print(f"ENGINE_PORT={ready['proxy_port']}")
    print(f"ENGINE_LOG={run_dir / 'engine.log'}")
    print(f"ENGINE_HOST={args.host}")


def lan_address(host):
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    probe.connect((host, AGENT_PORT))
    address = probe.getsockname()[0]
    probe.close()
    return address


def serve_relay(listener, connect, allowed_ip=None):
    def accept_loop():
        while True:
            sock, peer = listener.accept()
            if allowed_ip is not None and peer[0] != allowed_ip:
                sock.close()
                continue
            threading.Thread(target=relay_connection, args=(sock, connect), daemon=True).start()

    threading.Thread(target=accept_loop, daemon=True).start()


def relay_connection(sock, connect):
    try:
        target = connect()
    except OSError:
        sock.close()
        return
    splice(sock, target)


def listen(address):
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind((address, 0))
    listener.listen(16)
    return listener


def mirror_log(client, project, instance, log_path, start_path):
    while not os.path.exists(start_path):
        time.sleep(0.2)
    offset = 0
    with open(log_path, "ab") as log:
        while True:
            try:
                status, _, data = client.request(
                    "GET", "/log", {"project": project, "instance": instance, "offset": offset}, timeout=10
                )
                if status == 200 and data:
                    log.write(data)
                    log.flush()
                    offset += len(data)
            except OSError:
                pass
            time.sleep(0.3)


def make_proxy_handler(client, project, instance, log_relay_port, files_dir):
    prefix = f"/engine/{urllib.parse.quote(project)}/{urllib.parse.quote(instance)}"

    class ProxyHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def localize(self, data):
            payload = json.loads(data)
            if self.path == "/info":
                payload["log_port"] = log_relay_port
                return json.dumps(payload).encode("utf-8")
            inner = payload.get("data")
            if not isinstance(inner, dict) or inner.get("state") != "complete" or not inner.get("path"):
                return data
            remote_path = inner["path"]
            status, _, file_data = client.request("GET", "/file", {"path": remote_path}, timeout=60)
            if status != 200:
                return data
            local_path = files_dir / re.split(r"[\\/]", remote_path)[-1]
            local_path.write_bytes(file_data)
            inner["path"] = str(local_path)
            return json.dumps(payload).encode("utf-8")

        def forward(self):
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length) if length else None
            headers = {key: value for key, value in self.headers.items() if key.lower() in ("content-type",)}
            try:
                status, response_headers, data = client.request(
                    self.command, prefix + self.path, body=body, timeout=600, headers=headers
                )
            except OSError as error:
                self.send_error(502, str(error))
                return
            content_type = dict((key.lower(), value) for key, value in response_headers).get("content-type", "")
            path = self.path.split("?")[0]
            if status == 200 and (path == "/info" or "/screenshot" in path and "json" in content_type):
                data = self.localize(data)
            self.send_response(status)
            if content_type:
                self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        do_GET = do_POST = do_PUT = do_DELETE = forward

    return ProxyHandler


def cmd_forward(args):
    client = AgentClient(args.host)
    lan_ip = lan_address(client.host)
    host_ip = socket.gethostbyname(client.host)
    files_dir = Path(args.files)
    shutil.rmtree(files_dir, ignore_errors=True)
    files_dir.mkdir(parents=True)
    Path(args.log).write_bytes(b"")

    main_ports = {}
    for port in args.main_port:
        listener = listen(lan_ip)
        serve_relay(listener, lambda target=int(port): socket.create_connection(("127.0.0.1", target)), host_ip)
        main_ports[port] = listener.getsockname()[1]

    log_listener = listen("127.0.0.1")
    log_path = f"/tunnel/log/{urllib.parse.quote(args.project)}/{urllib.parse.quote(args.instance)}"
    serve_relay(log_listener, lambda: client.open_tunnel(log_path))

    handler = make_proxy_handler(client, args.project, args.instance, log_listener.getsockname()[1], files_dir)
    proxy = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    start_path = Path(args.ready).with_name("mirror.start")
    start_path.unlink(missing_ok=True)
    threading.Thread(target=mirror_log, args=(client, args.project, args.instance, args.log, start_path), daemon=True).start()

    def stop(*_):
        try:
            client.json("POST", "/stop", payload={"project": args.project, "instance": args.instance}, timeout=10)
        finally:
            os._exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    ready = {"proxy_port": proxy.server_address[1], "main_ports": main_ports, "lan_ip": lan_ip}
    Path(args.ready + ".tmp").write_text(json.dumps(ready))
    os.replace(args.ready + ".tmp", args.ready)
    proxy.serve_forever()


def cmd_remove(args):
    root = Path(args.root)
    subprocess.run(["git", "update-ref", "-d", f"refs/test-host/{args.instance}"], cwd=root, capture_output=True)
    project = project_name(root)
    for address, status in discover().items():
        try:
            AgentClient(address, timeout=5).json(
                "POST", "/remove", payload={"project": project, "instance": args.instance}, timeout=120
            )
            print(f"removed {args.instance} on {status['name']}")
        except (OSError, RuntimeError) as error:
            print(f"skip {status['name']}: {error}")


class Agent:
    def __init__(self, config):
        self.config = config
        self.root = AGENT_ROOT
        self.jobs = {}
        self.lock = threading.Lock()
        self.project_locks = {}

    def project_dir(self, project):
        return self.root / "projects" / check_name(project)

    def repo(self, project):
        repo = self.project_dir(project) / "repo.git"
        if not repo.exists():
            repo.mkdir(parents=True)
            git("init", "--bare", "--quiet", cwd=repo)
            git("config", "core.autocrlf", "false", cwd=repo)
            git("config", "core.longpaths", "true", cwd=repo)
        return repo

    def checkout_dir(self, project, instance):
        return self.project_dir(project) / check_name(instance)

    def project_lock(self, project):
        with self.lock:
            return self.project_locks.setdefault(project, threading.Lock())

    def status(self):
        available, total = memory_mb()
        bob_dir = self.root / "bob"
        return {
            "protocol": PROTOCOL,
            "script_sha": RUNNING_SHA,
            "name": socket.gethostname(),
            "os": platform.system(),
            "arch": platform.machine(),
            "mem_available_mb": available,
            "mem_total_mb": total,
            "top_processes": top_processes(),
            "bob": sorted(path.name for path in bob_dir.iterdir()) if bob_dir.exists() else [],
        }

    def snapshots(self, project):
        output = git("for-each-ref", "--format=%(objectname)", "refs/instances", cwd=self.repo(project))
        return sorted(set(output.split()))

    def receive_bundle(self, project, instance, bundle_path):
        with self.project_lock(project):
            git("fetch", "--quiet", str(bundle_path), f"+refs/test-host/{instance}:refs/instances/{instance}", cwd=self.repo(project))

    def checkout(self, project, instance, sha):
        with self.project_lock(project):
            repo = self.repo(project)
            git("update-ref", f"refs/instances/{instance}", sha, cwd=repo)
            path = self.checkout_dir(project, instance)
            if not path.exists():
                git("worktree", "prune", cwd=repo)
                git("worktree", "add", "--quiet", "--force", "--detach", str(path), sha, cwd=repo)
                return path
        git("checkout", "--quiet", "--force", "--detach", sha, cwd=path)
        git("clean", "-fdq", cwd=path)
        return path

    def job_env(self, bob_version, extra):
        env = dict(os.environ)
        env["PATH"] = os.pathsep.join([str(self.root / "bin"), self.config["path"]])
        env.update(extra)
        env["bob"] = str(self.root / "bob" / check_name(bob_version) / "bob.jar")
        env["LINUX_TEST_HOST"] = "local"
        return env

    def run(self, request):
        project, instance = request["project"], request["instance"]
        job_id = secrets.token_hex(8)
        log_path = self.root / "jobs" / f"{job_id}.log"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        job = {"log": log_path, "exit_code": None}
        self.run_file(project, instance, "engine.log").unlink(missing_ok=True)
        with self.lock:
            self.jobs[job_id] = job

        def work():
            with open(log_path, "wb") as log:
                try:
                    path = self.checkout(project, instance, request["sha"])
                    env = self.job_env(request["bob_version"], {**request["env"], "LINUX_INSTANCE": instance})
                    process = subprocess.Popen(
                        [self.config["bash"], "build_shell/test/linux_test.sh", *request["args"]],
                        cwd=path, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                    )
                    job["exit_code"] = process.wait()
                except (OSError, subprocess.CalledProcessError, ValueError) as error:
                    stderr = getattr(error, "stderr", "") or ""
                    log.write(f"test_host agent: {error} {stderr}\n".encode("utf-8"))
                    job["exit_code"] = 1

        threading.Thread(target=work, daemon=True).start()
        return job_id

    def job_state(self, job_id, offset):
        job = self.jobs[job_id]
        exit_code = job["exit_code"]
        with open(job["log"], "rb") as log:
            log.seek(offset)
            chunk = log.read(1 << 20)
        if exit_code is not None and not chunk:
            job["log"].unlink(missing_ok=True)
            with self.lock:
                del self.jobs[job_id]
        return {"output": base64.b64encode(chunk).decode("ascii"), "exit_code": exit_code}

    def run_file(self, project, instance, name):
        return self.checkout_dir(project, instance) / ".internal" / "linux_test" / name

    def engine_port(self, project, instance):
        return int(self.run_file(project, instance, "engine.port").read_text().strip())

    def stop(self, project, instance):
        pid_path = self.run_file(project, instance, "engine.pid")
        if not pid_path.exists():
            return
        pid = int(pid_path.read_text().strip())
        if platform.system() == "Windows":
            subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
        else:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        pid_path.unlink()

    def remove(self, project, instance):
        self.stop(project, instance)
        with self.project_lock(project):
            repo = self.repo(project)
            path = self.checkout_dir(project, instance)
            if path.exists():
                subprocess.run(["git", "worktree", "remove", "--force", str(path)], cwd=repo, capture_output=True)
                shutil.rmtree(path, ignore_errors=True)
            subprocess.run(["git", "update-ref", "-d", f"refs/instances/{instance}"], cwd=repo, capture_output=True)
            git("worktree", "prune", cwd=repo)


def make_agent_handler(agent):
    class AgentHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def authorized(self):
            if is_lan_address(self.client_address[0]):
                return True
            self.send_error(403)
            return False

        def reply(self, status, data, content_type="application/json"):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def reply_json(self, value):
            self.reply(200, json.dumps(value).encode("utf-8"))

        def body(self):
            return self.rfile.read(int(self.headers.get("Content-Length", 0)))

        def body_to_file(self, path):
            remaining = int(self.headers["Content-Length"])
            with open(path, "wb") as handle:
                while remaining:
                    chunk = self.rfile.read(min(remaining, 1 << 20))
                    handle.write(chunk)
                    remaining -= len(chunk)

        def route(self):
            url = urllib.parse.urlsplit(self.path)
            query = {key: values[0] for key, values in urllib.parse.parse_qs(url.query).items()}
            return url.path, query

        def do_GET(self):
            if not self.authorized():
                return
            path, query = self.route()
            try:
                if path.startswith("/engine/"):
                    self.proxy_engine()
                elif path == "/status":
                    self.reply_json(agent.status())
                elif path == "/snapshots":
                    self.reply_json(agent.snapshots(query["project"]))
                elif path == "/job":
                    self.reply_json(agent.job_state(query["id"], int(query["offset"])))
                elif path == "/log":
                    log_path = agent.run_file(query["project"], query["instance"], "engine.log")
                    with open(log_path, "rb") as log:
                        log.seek(int(query["offset"]))
                        self.reply(200, log.read(1 << 20), "application/octet-stream")
                elif path == "/file":
                    self.reply(200, Path(query["path"]).read_bytes(), "application/octet-stream")
                else:
                    self.send_error(404)
            except (OSError, KeyError, ValueError) as error:
                self.reply(404, str(error).encode("utf-8"), "text/plain")

        def do_POST(self):
            if not self.authorized():
                return
            path, query = self.route()
            try:
                if path.startswith("/engine/"):
                    self.proxy_engine()
                elif path == "/bundle":
                    with tempfile.TemporaryDirectory() as temp:
                        bundle_path = Path(temp) / "snapshot.bundle"
                        self.body_to_file(bundle_path)
                        agent.receive_bundle(query["project"], check_name(query["instance"]), bundle_path)
                    self.reply_json({})
                elif path == "/bob":
                    target = agent.root / "bob" / check_name(query["version"]) / "bob.jar"
                    target.parent.mkdir(parents=True, exist_ok=True)
                    self.body_to_file(target.with_suffix(".part"))
                    os.replace(target.with_suffix(".part"), target)
                    self.reply_json({})
                elif path == "/run":
                    self.reply_json({"job": agent.run(json.loads(self.body()))})
                elif path == "/stop":
                    request = json.loads(self.body())
                    agent.stop(request["project"], request["instance"])
                    self.reply_json({})
                elif path == "/update":
                    script = Path(__file__)
                    self.body_to_file(script.with_suffix(".part"))
                    os.replace(script.with_suffix(".part"), script)
                    self.reply_json({})
                    threading.Timer(0.5, os._exit, args=(0,)).start()
                elif path == "/quit":
                    self.reply_json({})
                    os._exit(0)
                elif path == "/remove":
                    request = json.loads(self.body())
                    agent.remove(request["project"], request["instance"])
                    self.reply_json({})
                else:
                    self.send_error(404)
            except (OSError, KeyError, ValueError, subprocess.CalledProcessError) as error:
                stderr = getattr(error, "stderr", "") or ""
                self.reply(500, f"{error} {stderr}".encode("utf-8"), "text/plain")

        def proxy_engine(self):
            parts = self.path.split("/", 4)
            project, instance = urllib.parse.unquote(parts[2]), urllib.parse.unquote(parts[3])
            port = agent.engine_port(project, instance)
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=600)
            headers = {key: value for key, value in self.headers.items() if key.lower() == "content-type"}
            connection.request(self.command, "/" + parts[4], body=self.body() or None, headers=headers)
            response = connection.getresponse()
            data = response.read()
            connection.close()
            self.reply(response.status, data, response.getheader("Content-Type", "application/octet-stream"))

        def do_PUT(self):
            if not self.authorized():
                return
            if self.route()[0].startswith("/engine/"):
                self.proxy_engine()
            else:
                self.send_error(404)

        do_DELETE = do_PUT

        def do_CONNECT(self):
            if not self.authorized():
                return
            _, _, kind, project, instance = self.path.split("/")
            project, instance = urllib.parse.unquote(project), urllib.parse.unquote(instance)
            info = http.client.HTTPConnection("127.0.0.1", agent.engine_port(project, instance), timeout=10)
            info.request("GET", "/info")
            log_port = json.loads(info.getresponse().read())["log_port"]
            target = socket.create_connection(("127.0.0.1", int(log_port)))
            self.wfile.write(b"HTTP/1.0 200 Connection established\r\n\r\n")
            self.wfile.flush()
            self.close_connection = True
            splice(self.connection, target)

    return AgentHandler


class AgentServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def answer_discovery(agent):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", AGENT_PORT))
    while True:
        data, peer = sock.recvfrom(1024)
        if data == DISCOVERY_REQUEST and is_lan_address(peer[0]):
            sock.sendto(json.dumps(agent.status()).encode("utf-8"), peer)


def cmd_agent(_args):
    config = load_config()
    os.environ["PATH"] = config["path"]
    agent = Agent(config)
    threading.Thread(target=answer_discovery, args=(agent,), daemon=True).start()
    AgentServer(("0.0.0.0", AGENT_PORT), make_agent_handler(agent)).serve_forever()


def msys_path(path):
    drive, rest = os.path.splitdrive(str(path))
    return "/" + drive.rstrip(":").lower() + rest.replace("\\", "/")


def find_bash():
    if platform.system() != "Windows":
        return shutil.which("bash")
    git_path = Path(shutil.which("git")).resolve()
    return str(git_path.parent.parent / "bin" / "bash.exe")


def install_python_shim(bin_dir):
    bin_dir.mkdir(parents=True, exist_ok=True)
    if platform.system() == "Windows":
        shim = bin_dir / "python3"
        shim.write_text(f'#!/bin/sh\nexec "{msys_path(sys.executable)}" "$@"\n', newline="\n")
        return
    shim = bin_dir / "python3"
    shim.unlink(missing_ok=True)
    shim.symlink_to(sys.executable)


def install_autostart(script):
    system = platform.system()
    if system == "Linux":
        unit_dir = Path.home() / ".config" / "systemd" / "user"
        unit_dir.mkdir(parents=True, exist_ok=True)
        (unit_dir / "defold-test-host.service").write_text(
            "[Unit]\nDescription=Defold test host agent\n\n"
            f"[Service]\nExecStart={sys.executable} {script} agent\nRestart=always\nRestartSec=2\nKillMode=process\n\n"
            "[Install]\nWantedBy=default.target\n"
        )
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
        subprocess.run(["systemctl", "--user", "enable", "defold-test-host.service"], check=True)
        subprocess.run(["systemctl", "--user", "restart", "defold-test-host.service"], check=True)
    elif system == "Darwin":
        plist = Path.home() / "Library" / "LaunchAgents" / "defold.test-host.plist"
        plist.parent.mkdir(parents=True, exist_ok=True)
        log = AGENT_ROOT / "agent.log"
        plist.write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0"><dict>\n'
            "<key>Label</key><string>defold.test-host</string>\n"
            f"<key>ProgramArguments</key><array><string>{sys.executable}</string><string>{script}</string><string>agent</string></array>\n"
            "<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>AbandonProcessGroup</key><true/>\n"
            f"<key>StandardOutPath</key><string>{log}</string><key>StandardErrorPath</key><string>{log}</string>\n"
            "</dict></plist>\n"
        )
        domain = f"gui/{os.getuid()}"
        subprocess.run(["launchctl", "bootout", domain, str(plist)], capture_output=True)
        subprocess.run(["launchctl", "bootstrap", domain, str(plist)], check=True)
    else:
        pythonw = Path(sys.executable).with_name("pythonw.exe")
        startup = Path(os.environ["APPDATA"]) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Startup"
        (startup / "defold_test_host.cmd").write_text(f'@start "" "{pythonw}" "{script}" agent\r\n')
        try:
            AgentClient("127.0.0.1", timeout=3).json("POST", "/quit")
            time.sleep(1)
        except (OSError, RuntimeError):
            pass
        subprocess.Popen([str(pythonw), str(script), "agent"], creationflags=subprocess.DETACHED_PROCESS, close_fds=True)
        print("allow TCP port 47800 in the Windows firewall when it asks, or as administrator:")
        print('  netsh advfirewall firewall add rule name="defold test host" dir=in action=allow protocol=TCP localport=47800')


def command_output(*command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return result.stdout + result.stderr


def version_major(output, pattern):
    match = re.search(pattern, output)
    return int(match.group(1)) if match else 0


def java_major():
    return version_major(command_output("java", "-version"), r'version "(\d+)')


def bash_major(bash):
    return version_major(command_output(bash, "--version"), r"version (\d+)") if bash else 0


def gpu_renderer():
    system = platform.system()
    if system == "Darwin":
        match = re.search(r"Chipset Model: (.+)", command_output("system_profiler", "SPDisplaysDataType"))
        return match.group(1).strip() if match else ""
    if system == "Linux":
        output = command_output(
            "xvfb-run", "-a", str(VIRTUALGL_DIR / "vglrun"), "-d", "egl", str(VIRTUALGL_DIR / "glxinfo"), "-B"
        )
        match = re.search(r"OpenGL renderer string: (.+)", output)
        return match.group(1).strip() if match else ""
    return ""


def agent_status():
    try:
        return AgentClient("127.0.0.1", timeout=3).json("GET", "/status")
    except (OSError, RuntimeError, ValueError):
        return None


def report_line(ok, name, value):
    print(f"{'OK  ' if ok else 'FAIL'}  {name}: {value}")
    return ok


def cmd_check(_args):
    available, total = memory_mb()
    bash = find_bash()
    java = java_major()
    renderer = gpu_renderer()
    status = agent_status()
    name = socket.gethostname()
    discovered = any(host["name"] == name for host in discover().values())
    results = [
        report_line(True, "host", f"{name}, {platform.system()} {platform.machine()}"),
        report_line(available >= MIN_FREE_MB, "free RAM", f"{available} MB of {total} MB (needs {MIN_FREE_MB})"),
        report_line(sys.version_info >= (3, 9), "python", platform.python_version()),
        report_line(shutil.which("git") is not None, "git", command_output("git", "--version").strip()),
        report_line(java >= MIN_JAVA, "java", f"{java} (needs {MIN_JAVA}+)"),
        report_line(bash_major(bash) >= 4, "bash", f"{bash} {bash_major(bash)} (needs 4+)"),
    ]
    if platform.system() == "Linux":
        results.append(report_line(shutil.which("Xvfb") is not None, "Xvfb", shutil.which("Xvfb")))
        results.append(report_line((VIRTUALGL_DIR / "vglrun").exists(), "VirtualGL", VIRTUALGL_DIR))
    results.append(report_line(bool(renderer) and "llvmpipe" not in renderer, "GPU", renderer or "not found"))
    results.append(report_line(status is not None, "agent", "running on TCP 47800" if status else "not running"))
    results.append(report_line(discovered, "broadcast", "answers UDP 47800" if discovered else "no answer"))
    print("\nREADY: this computer can take test builds" if all(results) else "\nNOT READY: fix the FAIL lines")


def cmd_install(_args):
    bash = find_bash()
    java = java_major()
    if shutil.which("git") is None or java < MIN_JAVA or bash_major(bash) < 4:
        cmd_check(_args)
        fail("install the missing tools first (md/shared/TEST_HOSTS.md)")
    AGENT_ROOT.mkdir(parents=True, exist_ok=True)
    script = AGENT_ROOT / "test_host.py"
    if Path(__file__).resolve() != script.resolve():
        shutil.copyfile(__file__, script)
    install_python_shim(AGENT_ROOT / "bin")
    save_config({"path": os.environ["PATH"], "bash": bash})
    install_autostart(script)
    time.sleep(2)
    print(f"agent installed into {AGENT_ROOT}, it starts by itself after every login\n")
    cmd_check(_args)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.set_defaults(func=cmd_install)
    commands = parser.add_subparsers(dest="command")
    commands.add_parser("pick").set_defaults(func=cmd_pick)
    commands.add_parser("hosts").set_defaults(func=cmd_hosts)
    commands.add_parser("share").set_defaults(func=cmd_share)
    address = commands.add_parser("address")
    address.add_argument("name")
    address.set_defaults(func=cmd_address)
    commands.add_parser("check").set_defaults(func=cmd_check)
    run = commands.add_parser("run")
    run.add_argument("--host", required=True)
    run.add_argument("--root", required=True)
    run.add_argument("--instance", required=True)
    run.add_argument("--bob", required=True)
    run.add_argument("--run-dir", required=True)
    run.add_argument("--main-port", action="append", default=[])
    run.add_argument("engine_args", nargs=argparse.REMAINDER)
    run.set_defaults(func=cmd_run)
    forward = commands.add_parser("forward")
    forward.add_argument("--host", required=True)
    forward.add_argument("--project", required=True)
    forward.add_argument("--instance", required=True)
    forward.add_argument("--log", required=True)
    forward.add_argument("--files", required=True)
    forward.add_argument("--ready", required=True)
    forward.add_argument("--main-port", action="append", default=[])
    forward.set_defaults(func=cmd_forward)
    remove = commands.add_parser("remove")
    remove.add_argument("--root", required=True)
    remove.add_argument("--instance", required=True)
    remove.set_defaults(func=cmd_remove)
    commands.add_parser("agent").set_defaults(func=cmd_agent)
    commands.add_parser("install").set_defaults(func=cmd_install)
    args = parser.parse_args()
    if getattr(args, "engine_args", None) and args.engine_args[0] == "--":
        args.engine_args = args.engine_args[1:]
    args.func(args)


if __name__ == "__main__":
    main()
