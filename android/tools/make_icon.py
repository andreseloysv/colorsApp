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
  - mipmap-*/ic_launcher_background.png  (degradado del máster sin la C)

El máster es la C de cristal sobre degradado verde (docs/play/icon_master.png es la
misma imagen). El foreground lleva el máster reducido a la zona segura con el borde
fundido; el background continúa el degradado; la monocroma es la silueta de la C.
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


# Fracción de la capa adaptativa (108 dp) que ocupa el máster: la parte visible es el
# cuadrado central de 72 dp (0,667) y la zona segura un círculo de 66 dp. Con 0,70 el borde
# del máster queda fuera de lo visible y la C entera dentro de la zona segura.
FOREGROUND_FRACTION = 0.70


def edge_gradient(im: Image.Image) -> Image.Image:
    """Fondo del adaptativo: el degradado vertical del máster sin la C.

    Cada fila toma la media de las columnas de los bordes izquierdo y derecho, que en el
    máster son solo fondo; así la capa de fondo continúa el degradado más allá del máster.
    """
    w, h = im.size
    src = im.load()
    out = Image.new("RGB", (1, h))
    for y in range(h):
        cols = [src[x, y] for x in list(range(0, 24)) + list(range(w - 24, w))]
        out.putpixel((0, y), tuple(sum(c[i] for c in cols) // len(cols) for i in range(3)))
    return out.resize((w, h), Image.BILINEAR)


def foreground(im: Image.Image, size: int) -> Image.Image:
    """Máster reducido al centro de la capa, con el borde fundido en transparente."""
    from PIL import ImageDraw, ImageFilter

    inner = round(size * FOREGROUND_FRACTION)
    art = im.resize((inner, inner), Image.LANCZOS).convert("RGBA")
    feather = max(2, inner // 16)
    mask = Image.new("L", (inner, inner), 0)
    ImageDraw.Draw(mask).rectangle((feather, feather, inner - feather - 1, inner - feather - 1), fill=255)
    art.putalpha(mask.filter(ImageFilter.GaussianBlur(feather / 2)))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    off = (size - inner) // 2
    out.alpha_composite(art, (off, off))
    return out


def monochrome(im: Image.Image, size: int) -> Image.Image:
    """Silueta monocroma de la C (cristal claro sobre fondo verde) a la escala del foreground.

    Android tiñe esta capa con el color del tema; solo importa el alfa. El cristal es casi
    blanco (canal mínimo alto) y el fondo verde tiene el rojo bajo: el alfa sale del canal
    mínimo, y las partículas pequeñas desaparecen con un leve desenfoque y el umbral.
    """
    from PIL import ImageFilter

    small = im.resize((512, 512), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.2))
    alpha = Image.new("L", small.size, 0)
    src = small.load(); dst = alpha.load()
    for y in range(small.height):
        for x in range(small.width):
            m = min(src[x, y])
            dst[x, y] = 255 if m > 95 else 0
    # Desenfoque y umbral: rellena los huecos del cristal facetado con un contorno suave,
    # sin cerrar el hueco de la C ni dejar las partículas.
    alpha = alpha.filter(ImageFilter.GaussianBlur(7)).point(lambda v: 255 if v > 60 else 0)
    alpha = alpha.filter(ImageFilter.GaussianBlur(4)).point(lambda v: 255 if v > 128 else 0)
    alpha = alpha.filter(ImageFilter.GaussianBlur(1.2))
    sil = Image.new("RGBA", small.size, (0, 0, 0, 0)); sil.putalpha(alpha)
    inner = round(size * FOREGROUND_FRACTION)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    off = (size - inner) // 2
    out.alpha_composite(sil.resize((inner, inner), Image.LANCZOS), (off, off))
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
    grad = edge_gradient(im)
    for density, (fg, legacy) in DENSITIES.items():
        d = RES / f"mipmap-{density}"
        d.mkdir(parents=True, exist_ok=True)
        foreground(im, fg).save(d / "ic_launcher_foreground.png")
        grad.resize((fg, fg), Image.LANCZOS).save(d / "ic_launcher_background.png")
        monochrome(im, fg).save(d / "ic_launcher_monochrome.png")
        im.resize((legacy, legacy), Image.LANCZOS).save(d / "ic_launcher.png")
        round_icon(im, legacy).save(d / "ic_launcher_round.png")
        print(f"{density}: fg {fg}px, legado {legacy}px")
    old = RES / "values" / "ic_launcher_background.xml"
    if old.exists():
        old.unlink()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
