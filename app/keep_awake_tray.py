#!/usr/bin/env python3
"""
keep-awake tray app v1.0 (Windows)

System-tray app that keeps the machine awake for long-running AI agent tasks.
- Toggle on/off from the tray menu
- Optional "keep display awake" checkbox
- Optional "prevent disk sleep" (disables disk idle timeout while active, restores on stop)
- No admin rights needed
- Everything is restored on stop / exit

Run:  keep-awake-tray.exe            (tray app)
      keep-awake-tray.exe --test 12  (headless self-test: run 12s, toggle, exit)
Stop: tray menu -> 退出 (Exit)
"""

import ctypes
import os
import re
import subprocess
import sys
import threading
import time

APP_VERSION = "1.4.0"

ES_CONTINUOUS = 0x80000000
ES_SYSTEM_REQUIRED = 0x00000001
ES_DISPLAY_REQUIRED = 0x00000002

LOG_DIR = os.path.join(os.environ.get("LOCALAPPDATA", "."), "keep-awake")
LOG_PATH = os.path.join(LOG_DIR, "tray.log")


def log(msg: str) -> None:
    os.makedirs(LOG_DIR, exist_ok=True)
    with open(LOG_PATH, "a", encoding="utf-8") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")


def set_execution_state(flags: int) -> None:
    r = ctypes.windll.kernel32.SetThreadExecutionState(ctypes.c_uint(flags))
    if r == 0:
        raise OSError("SetThreadExecutionState failed")


CREATE_NO_WINDOW = 0x08000000  # subprocess.CREATE_NO_WINDOW (py3.7+: use attribute)


def _run(cmd):
    return subprocess.run(cmd, capture_output=True,
                          creationflags=CREATE_NO_WINDOW)


def query_disk_timeout(which: str):
    """Current disk-idle timeout in seconds (0 = never). Last two hex = AC/DC."""
    p = _run(["powercfg", "/q", "SCHEME_CURRENT", "SUB_DISK", "DISKIDLE"])
    out = p.stdout.decode("gbk", errors="replace")
    hexes = re.findall(r"0x([0-9A-Fa-f]{8})", out)
    if len(hexes) < 2:
        return None
    idx = len(hexes) - 2 if which == "ac" else len(hexes) - 1
    return int(hexes[idx], 16)


def set_disk_timeout(ac_min: int, dc_min: int) -> None:
    _run(["powercfg", "/change", "disk-timeout-ac", str(ac_min)])
    _run(["powercfg", "/change", "disk-timeout-dc", str(dc_min)])


class KeepAwake:
    def __init__(self) -> None:
        self.active = False
        self.keep_display = False
        self.keep_disk = True
        self.orig_ac = None
        self.orig_dc = None

    def start(self) -> None:
        if self.active:
            return
        flags = ES_CONTINUOUS | ES_SYSTEM_REQUIRED
        if self.keep_display:
            flags |= ES_DISPLAY_REQUIRED
        set_execution_state(flags)
        if self.keep_disk:
            self.orig_ac = query_disk_timeout("ac")
            self.orig_dc = query_disk_timeout("dc")
            set_disk_timeout(0, 0)
        self.active = True
        log(f"ON display={self.keep_display} disk_orig_ac={self.orig_ac}s dc={self.orig_dc}s")

    def stop(self) -> None:
        if not self.active:
            return
        set_execution_state(ES_CONTINUOUS)
        if self.keep_disk and self.orig_ac is not None:
            ac_min = round(self.orig_ac / 60)
            dc_min = round(self.orig_dc / 60) if self.orig_dc is not None else 0
            set_disk_timeout(ac_min, dc_min)
        self.active = False
        log("OFF (restored)")

    def toggle_display(self) -> None:
        self.keep_display = not self.keep_display
        log(f"keep_display={self.keep_display}")
        if self.active:  # re-apply
            self.stop()
            self.start()

    def toggle_disk(self) -> None:
        self.keep_disk = not self.keep_disk
        log(f"keep_disk={self.keep_disk}")


def run_tray() -> None:
    import pystray
    from PIL import Image, ImageDraw

    ka = KeepAwake()

    def icon_img(color: str):
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.ellipse((6, 6, 58, 58), fill=color)
        d.ellipse((22, 22, 42, 42), fill="white")
        return img

    def refresh(icon):
        icon.icon = icon_img("#2ecc71" if ka.active else "#95a5a6")
        icon.update_menu()

    def on_toggle(icon, item):
        if ka.active:
            ka.stop()
        else:
            ka.start()
        refresh(icon)

    def on_display(icon, item):
        ka.toggle_display()
        refresh(icon)

    def on_disk(icon, item):
        ka.toggle_disk()
        refresh(icon)

    def on_quit(icon, item):
        ka.stop()
        icon.stop()

    menu = pystray.Menu(
        pystray.MenuItem(
            lambda item: "停止保持唤醒" if ka.active else "开始保持唤醒",
            on_toggle),
        pystray.MenuItem(
            lambda item: "屏幕常亮" + ("  ✓" if ka.keep_display else ""),
            on_display),
        pystray.MenuItem(
            lambda item: "防止硬盘休眠" + ("  ✓" if ka.keep_disk else ""),
            on_disk),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("退出", on_quit),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem(f"keep-awake v{APP_VERSION}", None, enabled=False),
    )
    ka.start()
    log(f"tray started v{APP_VERSION}")
    icon = pystray.Icon("keep-awake", icon_img("#2ecc71"),
                        f"keep-awake v{APP_VERSION}", menu)
    icon.run()


def run_test(seconds: int) -> int:
    print(f"[test] keep-awake tray v{APP_VERSION}", flush=True)
    print("[test] baseline disk timeout: ac=%s dc=%s" %
          (query_disk_timeout("ac"), query_disk_timeout("dc")), flush=True)
    ka = KeepAwake()
    ka.start()
    print("[test] active=%s disk timeout during run: ac=%s dc=%s" %
          (ka.active, query_disk_timeout("ac"), query_disk_timeout("dc")),
          flush=True)
    time.sleep(seconds)
    ka.stop()
    print("[test] after stop disk timeout: ac=%s dc=%s" %
          (query_disk_timeout("ac"), query_disk_timeout("dc")), flush=True)
    print("[test] done. log: %s" % LOG_PATH, flush=True)
    return 0


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--test":
        sys.exit(run_test(int(sys.argv[2])))
    run_tray()
