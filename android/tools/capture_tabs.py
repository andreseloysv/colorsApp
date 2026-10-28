#!/usr/bin/env python3
"""Captura las pestañas Extraer/Rejilla/Jardín tocando la barra inferior.

Uso: capture_tabs.py <adb> <directorio-salida>
Lee el tamaño de pantalla (wm size) y toca el centro de cada cuarto de la
barra de pestañas (64 dp desde el borde inferior; aproximación suficiente
para el AVD). La captura del Feed la hace el propio destino make antes.
"""
import subprocess
import sys
import time


def run(adb: str, *args: str) -> str:
    return subprocess.run([adb, *args], capture_output=True, text=True, check=True).stdout


def main() -> int:
    adb, out = sys.argv[1], sys.argv[2]
    size = run(adb, "shell", "wm", "size").strip().split(":")[-1].strip()
    w, h = (int(v) for v in size.split("x"))
    density = int(run(adb, "shell", "wm", "density").strip().split(":")[-1].strip())
    # Centro vertical de la barra de pestañas (64 dp de alto sobre el borde).
    bar_y = h - int(32 * density / 160)
    tabs = [("extract", 3), ("grid", 5), ("garden", 7)]
    for name, eighth in tabs:
        run(adb, "shell", "input", "tap", str(w * eighth // 8), str(bar_y))
        time.sleep(1.5)
        run(adb, "shell", "screencap", "-p", f"/sdcard/tab-{name}.png")
        run(adb, "pull", "-q", f"/sdcard/tab-{name}.png", f"{out}/tab-{name}.png")
        print(f"tab-{name}.png")
    # Volver al Feed para dejar la app como estaba.
    run(adb, "shell", "input", "tap", str(w // 8), str(bar_y))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
