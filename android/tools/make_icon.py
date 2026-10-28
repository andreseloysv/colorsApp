#!/usr/bin/env python3
"""Regenera todos los iconos de Android desde el máster de 1024x1024.

Dónde dejar el icono nuevo: sustituye `android/icon/icon_master.png`
(1024x1024, PNG, arte a sangre completa como el de iOS) y ejecuta
`make android-icon` (o este script). Genera:

  - mipmap-*/ic_launcher_foreground.png  (432 px en xxxhdpi: arte completo)
  - mipmap-*/ic_launcher_monochrome.png  (silueta para iconos temáticos)
  - mipmap-*/ic_launcher.png y ic_launcher_round.png (legado pre-API 26 se
    sirve con el redondo a partir del adaptativo; estos cubren launchers
    antiguos dentro de minSdk 26 sin soporte adaptativo completo)
  - values/ic_launcher_background.xml     (color de esquina del máster)

El máster actual es el icono de iOS como marcador de posición: el dueño está
haciendo uno 3D nuevo. La capa "background" del adaptativo es el color
sólido muestreado de la esquina del máster (solo se ve en los bordes con
máscaras agresivas) y la monocroma es una silueta derivada por distancia al
fondo: al cambiar el máster conviene revisar ambas.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
MASTER = ROOT / "android" / "icon" / "icon_master.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

# densidad -> (foreground adaptativo 108dp, icono legado 48dp) en píxeles
DENSITIES = {
    "mdpi": (108, 48),
    "hdpi": (162, 72),
    "xhdpi": (216, 96),
    "xxhdpi": (324, 144),
    "xxxhdpi": (432, 192),
}


def corner_color(im: Image.Image) -> tuple[int, int, int]:
    """Media de las cuatro esquinas (fondo del adaptativo)."""
    w, h = im.size
    px = [im.getpixel(p) for p in [(4, 4), (w - 5, 4), (4, h - 5), (w - 5, h - 5)]]
    return tuple(sum(c[i] for c in px) // len(px) for i in range(3))


def monochrome(im: Image.Image, bg: tuple[int, int, int]) -> Image.Image:
    """Silueta monocroma: alfa según distancia al color de fondo, relleno negro.

    Android tiñe esta capa con el color del tema; solo importa el alfa.
    """
    small = im.resize((432, 432), Image.LANCZOS)
    out = Image.new("RGBA", small.size, (0, 0, 0, 0))
    src = small.load()
    dst = out.load()
    for y in range(small.height):
        for x in range(small.width):
            r, g, b = src[x, y]
            d = max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2]))
            a = 0 if d < 24 else min(255, (d - 24) * 4)
            dst[x, y] = (0, 0, 0, a)
    return out


def round_icon(im: Image.Image, size: int) -> Image.Image:
    """Icono legado redondo: máster recortado en círculo sobre transparente."""
    from PIL import ImageDraw

    base = im.resize((size, size), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (size * 4, size * 4), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    base.putalpha(mask.resize((size, size), Image.LANCZOS))
    return base


def main() -> int:
    if not MASTER.exists():
        print(f"falta el máster: {MASTER}")
        return 2
    im = Image.open(MASTER).convert("RGB")
    if im.size != (1024, 1024):
        print(f"el máster debe ser 1024x1024, es {im.size}")
        return 2
    bg = corner_color(im)
    bg_hex = "#%02X%02X%02X" % bg
    mono = monochrome(im, bg)
    for density, (fg, legacy) in DENSITIES.items():
        d = RES / f"mipmap-{density}"
        d.mkdir(parents=True, exist_ok=True)
        im.resize((fg, fg), Image.LANCZOS).save(d / "ic_launcher_foreground.png")
        mono.resize((fg, fg), Image.LANCZOS).save(d / "ic_launcher_monochrome.png")
        im.resize((legacy, legacy), Image.LANCZOS).save(d / "ic_launcher.png")
        round_icon(im, legacy).save(d / "ic_launcher_round.png")
        print(f"{density}: fg {fg}px, legado {legacy}px")
    (RES / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Generado por android/tools/make_icon.py desde icon/icon_master.png.\n"
        "     Color medio de las esquinas del máster: fondo del icono adaptativo. -->\n"
        f'<resources>\n    <color name="ic_launcher_background">{bg_hex}</color>\n</resources>\n',
        encoding="utf-8",
    )
    print(f"fondo adaptativo: {bg_hex}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
