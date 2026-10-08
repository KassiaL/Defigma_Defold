#!/usr/bin/env python3
"""run-test-window.py - the Windows counterpart of run-test-env: starts the engine so the person at the
computer never sees it, while it renders on the GPU at full speed and records like a visible window.

WHY
  A hidden desktop (CreateDesktop) renders at 60 fps but nothing can record it: Windows Graphics
  Capture and the automation bridge recorder need a window of the visible desktop. So the window stays
  on the user's desktop, but layered with alpha 1 (one step of 255, invisible to the eye), click-through
  (WS_EX_TRANSPARENT), without a taskbar button or Alt+Tab entry (WS_EX_TOOLWINDOW, no WS_EX_APPWINDOW),
  never activated (WS_EX_NOACTIVATE) and at the bottom of the Z order. Measured 2026-10-08: 60 fps,
  bridge video 1080x2300 at 60 fps in full brightness, no focus change, no effect on a GPU benchmark.

  The engine scales the size it is given by the display scale (175% turns 1080x2300 into 617x1314), so
  this process stays alive next to the engine and turns every size the engine settles on back into
  physical pixels (SetWindowPos with SWP_NOSENDCHANGING, which also lets the window exceed the height
  of the monitor). It exits with the engine.

USAGE (from Git Bash, by build_shell/test/test_instance.sh)
  python run-test-window.py --log <engine log> --pid-file <file> --cwd <dir> -- <exe> [args...]
  The engine pid is written to --pid-file as soon as the process exists.
  Shared by every Defold project and synced by sync_defold_docs.py.
"""

import argparse
import ctypes
import msvcrt
import os
import subprocess
import time
from ctypes import wintypes as W

KERNEL = ctypes.WinDLL("kernel32", use_last_error=True)
USER = ctypes.WinDLL("user32", use_last_error=True)

STARTF_USESHOWWINDOW = 0x1
STARTF_USESTDHANDLES = 0x100
SW_HIDE = 0
SW_SHOWNOACTIVATE = 4
CREATE_NO_WINDOW = 0x08000000
STILL_ACTIVE = 259
GWL_EXSTYLE = -20
WS_EX_TRANSPARENT = 0x20
WS_EX_TOOLWINDOW = 0x80
WS_EX_APPWINDOW = 0x40000
WS_EX_LAYERED = 0x80000
WS_EX_NOACTIVATE = 0x08000000
LWA_ALPHA = 0x2
HWND_BOTTOM = W.HWND(1)
SWP_NOSIZE = 0x1
SWP_NOMOVE = 0x2
SWP_NOZORDER = 0x4
SWP_NOACTIVATE = 0x10
SWP_NOSENDCHANGING = 0x400
DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = W.HANDLE(-4)
HIDDEN_STYLE = WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE


class StartupInfo(ctypes.Structure):
    _fields_ = [
        ("cb", W.DWORD), ("lpReserved", W.LPWSTR), ("lpDesktop", W.LPWSTR), ("lpTitle", W.LPWSTR),
        ("dwX", W.DWORD), ("dwY", W.DWORD), ("dwXSize", W.DWORD), ("dwYSize", W.DWORD),
        ("dwXCountChars", W.DWORD), ("dwYCountChars", W.DWORD), ("dwFillAttribute", W.DWORD),
        ("dwFlags", W.DWORD), ("wShowWindow", W.WORD), ("cbReserved2", W.WORD),
        ("lpReserved2", ctypes.POINTER(W.BYTE)), ("hStdInput", W.HANDLE), ("hStdOutput", W.HANDLE),
        ("hStdError", W.HANDLE),
    ]


class ProcessInfo(ctypes.Structure):
    _fields_ = [("hProcess", W.HANDLE), ("hThread", W.HANDLE), ("dwProcessId", W.DWORD), ("dwThreadId", W.DWORD)]


ENUM_CALLBACK = ctypes.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
KERNEL.CreateProcessW.argtypes = [
    W.LPCWSTR, W.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, W.BOOL, W.DWORD, ctypes.c_void_p, W.LPCWSTR,
    ctypes.POINTER(StartupInfo), ctypes.POINTER(ProcessInfo),
]
KERNEL.GetExitCodeProcess.argtypes = [W.HANDLE, ctypes.POINTER(W.DWORD)]
USER.EnumWindows.argtypes = [ENUM_CALLBACK, W.LPARAM]
USER.GetWindowThreadProcessId.argtypes = [W.HWND, ctypes.POINTER(W.DWORD)]
USER.GetWindowLongPtrW.argtypes = [W.HWND, ctypes.c_int]
USER.GetWindowLongPtrW.restype = ctypes.c_ssize_t
USER.SetWindowLongPtrW.argtypes = [W.HWND, ctypes.c_int, ctypes.c_ssize_t]
USER.SetWindowLongPtrW.restype = ctypes.c_ssize_t
USER.SetLayeredWindowAttributes.argtypes = [W.HWND, W.COLORREF, W.BYTE, W.DWORD]
USER.SetWindowPos.argtypes = [W.HWND, W.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, W.UINT]
USER.ShowWindow.argtypes = [W.HWND, ctypes.c_int]
USER.GetWindowRect.argtypes = [W.HWND, ctypes.POINTER(W.RECT)]
USER.GetClientRect.argtypes = [W.HWND, ctypes.POINTER(W.RECT)]
USER.GetDpiForWindow.argtypes = [W.HWND]
USER.SetThreadDpiAwarenessContext.argtypes = [W.HANDLE]
USER.SetThreadDpiAwarenessContext.restype = W.HANDLE
USER.SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)


def launch(command, cwd, log_path):
    startup = StartupInfo()
    startup.cb = ctypes.sizeof(startup)
    startup.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES
    startup.wShowWindow = SW_HIDE
    info = ProcessInfo()
    with open(log_path, "wb") as log, open(os.devnull, "rb") as stdin:
        os.set_inheritable(log.fileno(), True)
        os.set_inheritable(stdin.fileno(), True)
        startup.hStdInput = msvcrt.get_osfhandle(stdin.fileno())
        startup.hStdOutput = msvcrt.get_osfhandle(log.fileno())
        startup.hStdError = startup.hStdOutput
        command_line = ctypes.create_unicode_buffer(subprocess.list2cmdline(command))
        if not KERNEL.CreateProcessW(
            command[0], command_line, None, None, True, CREATE_NO_WINDOW, None, cwd,
            ctypes.byref(startup), ctypes.byref(info),
        ):
            raise ctypes.WinError(ctypes.get_last_error())
    KERNEL.CloseHandle(info.hThread)
    return info.hProcess, info.dwProcessId


def running(process):
    code = W.DWORD()
    KERNEL.GetExitCodeProcess(process, ctypes.byref(code))
    return code.value == STILL_ACTIVE


def client_size(hwnd):
    rect = W.RECT()
    USER.GetClientRect(hwnd, ctypes.byref(rect))
    return rect.right, rect.bottom


def process_window(pid):
    found = []

    @ENUM_CALLBACK
    def collect(hwnd, _):
        owner = W.DWORD()
        USER.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        width, height = client_size(hwnd)
        if owner.value == pid and width > 100 and height > 100:
            found.append(hwnd)
        return True

    USER.EnumWindows(collect, 0)
    return found[0] if found else None


def hide(hwnd):
    style = USER.GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
    USER.SetWindowLongPtrW(hwnd, GWL_EXSTYLE, (style & ~WS_EX_APPWINDOW) | HIDDEN_STYLE)
    USER.SetLayeredWindowAttributes(hwnd, 0, 1, LWA_ALPHA)
    USER.SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE)
    USER.ShowWindow(hwnd, SW_SHOWNOACTIVATE)


def set_client_size(hwnd, width, height):
    outer = W.RECT()
    USER.GetWindowRect(hwnd, ctypes.byref(outer))
    client_width, client_height = client_size(hwnd)
    frame_width = outer.right - outer.left - client_width
    frame_height = outer.bottom - outer.top - client_height
    USER.SetWindowPos(
        hwnd, None, 0, 0, width + frame_width, height + frame_height,
        SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOSENDCHANGING,
    )


def keep_physical_size(process, hwnd):
    scale = USER.GetDpiForWindow(hwnd) / 96
    expected = None
    while running(process):
        size = client_size(hwnd)
        if size != expected:
            expected = (round(size[0] * scale), round(size[1] * scale))
            set_client_size(hwnd, *expected)
            expected = client_size(hwnd)
        time.sleep(0.2)


def wait_window(process, pid):
    while running(process):
        hwnd = process_window(pid)
        if hwnd:
            return hwnd
        time.sleep(0.02)
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True)
    parser.add_argument("--pid-file", required=True)
    parser.add_argument("--cwd", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[0] == "--" else args.command
    process, pid = launch(command, args.cwd, args.log)
    with open(args.pid_file, "w") as pid_file:
        pid_file.write(f"{pid}\n")
    hwnd = wait_window(process, pid)
    if hwnd:
        hide(hwnd)
        keep_physical_size(process, hwnd)


if __name__ == "__main__":
    main()
