"""Capturas de Google Play (carril W7): app real en el emulador, 3 idiomas.

Recorrido (misma historia que el set de la App Store, ver
harness/appstore/captions.*.json del checkout principal):
01 feed · 02 resultado · 03 capas (Extraer) · 04 rejilla · 05 jardin · 06 ajustes.

Sin atajos en la app: maneja la UI pública con uiautomator + toques por
texto (las etiquetas salen de los recursos values/values-de/values-en que
este script lee del repo). Las fotos son las CC0 de harness/people (nunca
fotos personales), subidas a MediaStore y escaneadas con el escaneo día 0.

Salida: capturas crudas 1080x2400 en harness/out/store-raw/<locale>/ y,
con --frame, los PNG finales 1440x2560 RGB en docs/play/screenshots/.

Uso (desde la raíz del worktree, emulador ya arrancado):
  python3 tools/store/capture_play.py --serial emulator-5570 [--frame]
Requiere adb en ~/Library/Android/sdk/platform-tools (o --adb).
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PKG = "com.andreseloy.colorsapp"
LOCALES = ["es-ES", "de-DE", "en-US"]
RES_DIRS = {"es-ES": "values", "de-DE": "values-de", "en-US": "values-en"}


def strings_for(locale: str) -> dict[str, str]:
    out: dict[str, str] = {}
    base = ROOT / "android/app/src/main/res" / RES_DIRS[locale]
    for xml in sorted(base.glob("strings*.xml")):
        for m in re.finditer(r'<string name="([^"]+)">(.*?)</string>', xml.read_text(encoding="utf-8"), re.S):
            out[m.group(1)] = re.sub(r"<[^>]+>", "", m.group(2)).replace("\\'", "'").strip()
    return out


class Device:
    def __init__(self, adb: str, serial: str):
        self.adb, self.serial = adb, serial

    def sh(self, *args: str) -> str:
        return subprocess.run([self.adb, "-s", self.serial, "shell", *args],
                              capture_output=True, text=True).stdout

    def tap(self, x: int, y: int, wait: float = 2.5) -> None:
        self.sh("input", "tap", str(x), str(y)); time.sleep(wait)

    def swipe(self, x1: int, y1: int, x2: int, y2: int, wait: float = 2.0) -> None:
        self.sh("input", "swipe", str(x1), str(y1), str(x2), str(y2), "350"); time.sleep(wait)

    def dump(self) -> ET.Element:
        self.sh("uiautomator", "dump", "/sdcard/store-ui.xml")
        raw = subprocess.run([self.adb, "-s", self.serial, "exec-out", "cat", "/sdcard/store-ui.xml"],
                             capture_output=True).stdout
        return ET.fromstring(raw)

    def find(self, root: ET.Element, text: str) -> tuple[int, int] | None:
        for n in root.iter("node"):
            if (n.get("text") or "") == text or (n.get("content-desc") or "") == text:
                m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds") or "")
                if m:
                    a, b, c, d = map(int, m.groups())
                    return (a + c) // 2, (b + d) // 2
        return None

    def tap_text(self, text: str, wait: float = 2.5, tries: int = 6) -> bool:
        for _ in range(tries):
            p = self.find(self.dump(), text)
            if p:
                self.tap(*p, wait=wait); return True
            time.sleep(2)
        print(f"  !! no encontrado: {text!r}", file=sys.stderr)
        return False

    def has_text(self, text: str) -> bool:
        return self.find(self.dump(), text) is not None

    def shot(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        data = subprocess.run([self.adb, "-s", self.serial, "exec-out", "screencap", "-p"],
                              capture_output=True).stdout
        path.write_bytes(data)
        print(f"  {path} ({len(data)} bytes)")


def capture_locale(dev: Device, locale: str, raw_dir: Path) -> bool:
    s = strings_for(locale)
    tab = {r: s[k] for r, k in
           [("feed", "tab_feed"), ("extract", "tab_extract"), ("grid", "tab_grid"), ("garden", "tab_garden")]}
    print(f"== {locale} (pestañas: {tab})")
    dev.sh("cmd", "locale", "set-app-locales", PKG, "--locales", locale)
    dev.sh("am", "force-stop", PKG); time.sleep(1)
    dev.sh("am", "start", "-n", f"{PKG}/.app.MainActivity"); time.sleep(7)
    # Si la hoja del escaneo día 0 sigue abierta (primer arranque), ciérrala:
    # el escaneo ya se hizo en la preparación; aquí solo navegamos.
    for close in ("Cerrar", "Schließen", "Close"):
        if dev.has_text(close):
            dev.tap_text(close); break
    ok = True

    def go_tab(route: str) -> bool:
        # La barra ofrece la etiqueta dos veces (nodo e hijo); vale cualquiera.
        return dev.tap_text(tab[route], wait=3)

    # 01 feed (inicio: combinación del día + primer post del escaneo)
    go_tab("feed")
    dev.swipe(540, 1500, 540, 1050)  # asoma la foto del primer post
    dev.shot(raw_dir / "01-feed.png")
    dev.swipe(540, 1000, 540, 1600)

    # 02 resultado: abrir el primer post en Extraer (botón con esa descripción)
    open_extract = {"es-ES": "Abrir en Extraer", "de-DE": "In „Extrahieren“ öffnen",
                    "en-US": "Open in Extract"}[locale]
    if not dev.tap_text(open_extract, wait=4):
        # variantes de comillas según recurso real: busca por subcadena en el volcado
        root = dev.dump(); found = None
        for n in root.iter("node"):
            d = n.get("content-desc") or ""
            if "Extra" in d and len(d) < 40:
                found = d; break
        print(f"  (desc real: {found!r})")
        ok = bool(found and dev.tap_text(found, wait=4))
    time.sleep(3)
    dev.shot(raw_dir / "02-resultado.png")

    # Guarda el resultado en el Jardín (si aún no está) para que la
    # captura 05 enseñe la pestaña de guardadas con contenido real.
    dev.swipe(540, 1600, 540, 900)
    if dev.has_text(s.get("w3_save_in_garden_btn", "")):
        dev.tap_text(s["w3_save_in_garden_btn"], wait=2)
    # 03 capas: botón «Ver capas» del resultado
    layers = s.get("w3_view_layers", "Ver capas")
    if not dev.tap_text(layers, wait=3, tries=2):
        dev.swipe(540, 1600, 540, 900)
        ok = dev.tap_text(layers, wait=3) and ok
    time.sleep(2)
    dev.shot(raw_dir / "03-extraer.png")
    dev.sh("input", "keyevent", "4"); time.sleep(2)  # atrás

    # 04 rejilla
    dev.sh("am", "start", "-n", f"{PKG}/.app.MainActivity"); time.sleep(3)
    go_tab("grid"); time.sleep(2)
    dev.shot(raw_dir / "04-rejilla.png")

    # 05 jardín
    go_tab("garden"); time.sleep(2)
    dev.shot(raw_dir / "05-jardin.png")

    # 06 ajustes (engranaje del Jardín, descripción localizada)
    if not dev.tap_text(s.get("settings_title", "Ajustes"), wait=3):
        ok = False
    time.sleep(2)
    # Sin scroll: la cabecera de Ajustes completa se lee mejor en la ficha
    # que una tarjeta cortada a mitad de scroll (revisado sobre las capturas).
    dev.shot(raw_dir / "06-ajustes.png")
    return ok


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--serial", default="emulator-5570")
    ap.add_argument("--adb", default=str(Path.home() / "Library/Android/sdk/platform-tools/adb"))
    ap.add_argument("--locales", default=",".join(LOCALES))
    ap.add_argument("--frame", action="store_true", help="enmarcar al final en docs/play/screenshots/")
    args = ap.parse_args()
    dev = Device(args.adb, args.serial)
    if args.serial not in subprocess.run([args.adb, "devices"], capture_output=True, text=True).stdout:
        print(f"sin dispositivo {args.serial}", file=sys.stderr); return 1
    all_ok = True
    for locale in args.locales.split(","):
        all_ok = capture_locale(dev, locale, ROOT / "harness/out/store-raw" / locale) and all_ok
    if args.frame:
        r = subprocess.run([sys.executable, str(ROOT / "tools/store/make_play_frames.py")])
        all_ok = all_ok and r.returncode == 0
    print("RESULT:", "PASS" if all_ok else "REVISAR (faltó algún toque; mira los !!)")
    return 0 if all_ok else 2


if __name__ == "__main__":
    sys.exit(main())
