#!/usr/bin/env python3
"""defigma_twin.py - the Defigma web server of an agent worktree.

    defigma_twin.py start <main checkout> <worktree>   prints the port, writes <worktree>/.internal/defigma_port
    defigma_twin.py stop <worktree>

A project whose main checkout runs a Defigma web server under pm2 (`Defigma_Web_Server/index.js` with
the main checkout as its project path) gets a twin of it for the worktree: the same server, the
worktree as project path and in its gui command, a free port, and the worktree folder name as the
pm2 name. An export sent with that port (`defigma.export(nodes, { upload_port })` of Figma Bridge)
lands in the worktree and is synced there. A project without such a server gets nothing.
Called by agent_worktree.sh and agent_worktree_clean.sh; shared by every Defold project and synced by
sync_defold_docs.py.
"""

import json
import os
import socket
import subprocess
import sys

SERVER_SCRIPT = "Defigma_Web_Server/index.js"
FIRST_PORT = 16900
LAST_PORT = 17899


def pm2_processes():
    try:
        output = subprocess.run(["pm2", "jlist"], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return []
    start = output.find("[")
    return json.loads(output[start:]) if start >= 0 else []


def is_defigma(process):
    return process["pm2_env"].get("pm_exec_path", "").endswith(SERVER_SCRIPT)


def server_port(process):
    args = process["pm2_env"].get("args") or []
    for index, arg in enumerate(args):
        if arg in ("--port", "-p") and index + 1 < len(args):
            return int(args[index + 1])
        if arg.startswith("--port="):
            return int(arg.split("=", 1)[1])
    return None


def is_free(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        try:
            probe.bind(("127.0.0.1", port))
        except OSError:
            return False
    return True


def free_port(taken):
    for port in range(FIRST_PORT, LAST_PORT + 1):
        if port not in taken and is_free(port):
            return port
    raise SystemExit("no free port for the Defigma web server")


def stop(worktree):
    name = os.path.basename(worktree)
    for process in pm2_processes():
        if process["name"] == name and is_defigma(process):
            subprocess.run(["pm2", "delete", name], capture_output=True, check=True)
            print("stopped Defigma web server " + name)


def start(main_checkout, worktree):
    processes = pm2_processes()
    servers = [process for process in processes if is_defigma(process)]
    main = next((process for process in servers if (process["pm2_env"].get("args") or [None])[0] == main_checkout), None)
    if main is None:
        return
    stop(worktree)
    args = main["pm2_env"]["args"]
    gui_command = args[1].replace(main_checkout, worktree) if len(args) > 1 else ""
    port = free_port({server_port(process) for process in servers})
    name = os.path.basename(worktree)
    subprocess.run(["pm2", "start", main["pm2_env"]["pm_exec_path"], "--name", name, "--cwd", worktree, "--",
                    worktree, gui_command, "--port", str(port)], capture_output=True, check=True)
    os.makedirs(os.path.join(worktree, ".internal"), exist_ok=True)
    with open(os.path.join(worktree, ".internal", "defigma_port"), "w") as port_file:
        port_file.write(str(port))
    print("DEFIGMA_PORT=%d" % port)


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "start":
        start(os.path.abspath(sys.argv[2]), os.path.abspath(sys.argv[3]))
    elif len(sys.argv) == 3 and sys.argv[1] == "stop":
        stop(os.path.abspath(sys.argv[2]))
    else:
        raise SystemExit(__doc__)


main()
