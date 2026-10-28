"""Marcos de Google Play: titular de marca sobre cada captura cruda.

Adaptación de oracle/tools/make_appstore_frames.py (checkout principal) a
Play: lienzo 1440x2560 (9:16), PNG RGB sin alfa, sin marco de iPhone (la
captura ya trae las barras de Android). Colores de marca del sistema de
diseño (superficie #FCF9F1, primario #144226, secundario #954A00).

Entrada: harness/out/store-raw/<locale>/NN-*.png (de capture_play.py).
Salida:  docs/play/screenshots/<locale>/NN_<nombre>.png (<= 8 MB, se verifica).
Titulares: tools/store/captions.json.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
CANVAS = (1440, 2560)
SURFACE = (0xFC, 0xF9, 0xF1)
PRIMARY = (0x14, 0x42, 0x26)
SECONDARY = (0x95, 0x4A, 0x00)
CORNER = 64
FONT_CANDIDATES = [
    ROOT / "ios/ColorsApp/Resources/Fonts/Literata-VF.ttf",
    Path("/System/Library/Fonts/Supplemental/Georgia Bold.ttf"),
    Path("/System/Library/Fonts/Helvetica.ttc"),
]
OUT_NAMES = {"01-feed": "01_feed", "02-resultado": "02_resultado", "03-extraer": "03_extraer",
             "04-rejilla": "04_rejilla", "05-jardin": "05_jardin", "06-ajustes": "06_ajustes"}


def load_font(size: int):
    for c in FONT_CANDIDATES:
        if c.exists():
            try:
                f = ImageFont.truetype(str(c), size)
                try:
                    f.set_variation_by_axes([600])
                except Exception:  # noqa: BLE001 - fuente no variable
                    pass
                return f
            except OSError:
                continue
    return ImageFont.load_default()


def wrap(draw, text, font, max_w):
    words, lines, line = text.split(), [], ""
    for w in words:
        t = f"{line} {w}".strip()
        if draw.textlength(t, font=font) <= max_w or not line:
            line = t
        else:
            lines.append(line); line = w
    if line:
        lines.append(line)
    return lines


def frame(shot: Image.Image, caption: str) -> Image.Image:
    canvas = Image.new("RGB", CANVAS, SURFACE)
    draw = ImageDraw.Draw(canvas)
    font = load_font(84)
    margin = 90
    y = 150
    for line in wrap(draw, caption, font, CANVAS[0] - 2 * margin):
        w = draw.textlength(line, font=font)
        draw.text(((CANVAS[0] - w) / 2, y), line, font=font, fill=PRIMARY)
        y += 104
    draw.rounded_rectangle(((CANVAS[0] - 160) / 2, y + 14, (CANVAS[0] + 160) / 2, y + 26),
                           radius=6, fill=SECONDARY)
    top = y + 90
    avail_h, avail_w = CANVAS[1] - top - 90, CANVAS[0] - 2 * margin
    scale = min(avail_w / shot.width, avail_h / shot.height)
    size = (round(shot.width * scale), round(shot.height * scale))
    resized = shot.convert("RGB").resize(size, Image.LANCZOS)
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=CORNER, fill=255)
    x = (CANVAS[0] - size[0]) // 2
    shadow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x - 6, top + 16, x + size[0] + 6, top + size[1] + 28),
                                             radius=CORNER + 6, fill=(0x14, 0x42, 0x26, 40))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
    canvas.paste(resized, (x, top), mask)
    return canvas


def main() -> int:
    caps = json.loads((ROOT / "tools/store/captions.json").read_text(encoding="utf-8"))
    ok = True
    for locale in ("es-ES", "de-DE", "en-US"):
        raw_dir = ROOT / "harness/out/store-raw" / locale
        out_dir = ROOT / "docs/play/screenshots" / locale
        out_dir.mkdir(parents=True, exist_ok=True)
        for stem, out_name in OUT_NAMES.items():
            src = raw_dir / f"{stem}.png"
            if not src.exists():
                print(f"FAIL falta {src}"); ok = False; continue
            with Image.open(src) as shot:
                framed = frame(shot, caps[locale][stem])
            dst = out_dir / f"{out_name}.png"
            framed.save(dst, "PNG", optimize=True)
            mb = dst.stat().st_size / 1e6
            with Image.open(dst) as chk:
                good = chk.size == CANVAS and chk.mode == "RGB" and mb <= 8
            print(f"{'PASS' if good else 'FAIL'} {dst} {CANVAS} RGB {mb:.2f} MB «{caps[locale][stem]}»")
            ok = ok and good
    print("RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
