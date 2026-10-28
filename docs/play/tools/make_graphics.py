#!/usr/bin/env python3
"""Genera los gráficos de Google Play de ChromaSol.

Uso (desde la raíz del repo):
  python3 docs/play/tools/make_graphics.py

Entradas:
  docs/play/icon_master.png        Icono maestro cuadrado (ideal 1024x1024).
                                   Hoy es una copia del icono de iOS
                                   (marcador de posición). Para cambiar el
                                   icono: sustituir este fichero por el nuevo
                                   maestro de 1024x1024 y volver a ejecutar
                                   este script; no hay que tocar nada más.
  data/wada/dictionary.json        Colores reales de las combinaciones de
                                   Wada que se dibujan en el gráfico
                                   destacado (FEATURE_COMBO_IDS).
  ios/ColorsApp/Resources/Fonts/   Literata y Plus Jakarta Sans (las fuentes
                                   de la app, SIL OFL). Si faltan, se usan
                                   Georgia/SFNS del sistema.

Salidas:
  docs/play/icon_512.png                 512x512, PNG de 32 bits (RGBA).
  docs/play/icon_exports/icon_<n>.png    192/144/96/72/48 px, copias de
                                         servicio para el carril de Android
                                         (el icono adaptativo final lo monta
                                         ese carril en android/).
  docs/play/feature_graphic.png          1024x500, RGB sin alfa, sin marcos
                                         de dispositivo y sin texto de precio.
                                         Solo lleva la marca «ChromaSol», el
                                         nombre propio «Sanzo Wada · 1933» y
                                         números de combinación, así que el
                                         mismo fichero sirve para es/de/en.

Estilo (docs/design/DESIGN_SYSTEM.md): fondo crema cálido #FCF9F1, tinta
verde musgo #144226, acento ámbar, y los swatches de datos siempre dentro de
un «pocillo» blanco neutro con filo fino, como en la app.
"""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
PLAY_DIR = ROOT / "docs" / "play"
MASTER = PLAY_DIR / "icon_master.png"
DICTIONARY = ROOT / "data" / "wada" / "dictionary.json"

CREAM = (252, 249, 241)       # Solar.surface (claro)
CREAM_DEEP = (243, 233, 210)  # degradado inferior cálido
MOSS = (20, 66, 38)           # Solar.primary (claro) #144226
WELL = (255, 255, 255)        # pocillo neutro
WELL_EDGE = (214, 214, 214)   # filo del pocillo
WELL_TEXT = (31, 31, 31)      # texto dentro del pocillo
AMBER = (249, 168, 0)         # rayo/sol del icono

# Combinaciones reales del diccionario para las tarjetas del gráfico.
FEATURE_COMBO_IDS = (250, 210, 301)
# Tira bajo la marca: combinación Nº 87 (rosa + citrino) completada con el
# azul de la Nº 67 para que la tira tenga cuatro tonos; ver swatches abajo.
BRAND_STRIP_IDS = (87, 67)


def load_font(candidates: list[Path], size: int) -> ImageFont.FreeTypeFont:
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default(size)


def brand_font(size: int) -> ImageFont.FreeTypeFont:
    return load_font(
        [
            ROOT / "ios/ColorsApp/Resources/Fonts/Literata-VF.ttf",
            Path("/System/Library/Fonts/Supplemental/Georgia Bold.ttf"),
            Path("/System/Library/Fonts/Supplemental/Georgia.ttf"),
        ],
        size,
    )


def ui_font(size: int) -> ImageFont.FreeTypeFont:
    return load_font(
        [
            ROOT / "ios/ColorsApp/Resources/Fonts/PlusJakartaSans-VF.ttf",
            Path("/System/Library/Fonts/SFNS.ttf"),
        ],
        size,
    )


def make_icons() -> None:
    if not MASTER.exists():
        raise SystemExit(f"Falta el icono maestro: {MASTER}")
    master = Image.open(MASTER)
    if master.width != master.height:
        raise SystemExit(f"icon_master.png debe ser cuadrado, es {master.size}")
    if master.width < 512:
        raise SystemExit(f"icon_master.png debe medir al menos 512 px, mide {master.width}")
    rgba = master.convert("RGBA")
    icon512 = rgba.resize((512, 512), Image.LANCZOS)
    icon512.save(PLAY_DIR / "icon_512.png", optimize=True)
    exports = PLAY_DIR / "icon_exports"
    exports.mkdir(exist_ok=True)
    for size in (192, 144, 96, 72, 48):
        rgba.resize((size, size), Image.LANCZOS).save(exports / f"icon_{size}.png", optimize=True)
    print(f"OK icon_512.png desde {MASTER.name} ({master.size[0]} px) + icon_exports/ 192..48")


def wada_colors() -> dict[int, list[tuple[int, int, int]]]:
    data = json.loads(DICTIONARY.read_text(encoding="utf-8"))
    by_index = {c["index"]: tuple(c["rgb"]) for c in data["colors"]}
    return {
        combo["id"]: [by_index[i] for i in combo["colors"]]
        for combo in data["combinations"]
    }


def swatch_row(img: Image.Image, box, colors, radius: int = 8) -> None:
    """Rectángulos planos de color dentro de `box`, sin brillos ni degradados.

    Se dibujan como una sola tira recortada con una máscara redondeada, para
    que las uniones entre colores queden rectas y sin muescas.
    """
    x0, y0, x1, y1 = (round(v) for v in box)
    strip = Image.new("RGB", (x1 - x0, y1 - y0), colors[0])
    sdraw = ImageDraw.Draw(strip)
    step = (x1 - x0) / len(colors)
    for i, rgb in enumerate(colors):
        sdraw.rectangle((round(i * step), 0, round((i + 1) * step), y1 - y0), fill=rgb)
    mask = Image.new("L", strip.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, strip.width - 1, strip.height - 1), radius=radius, fill=255)
    img.paste(strip, (x0, y0), mask)


def make_feature_graphic() -> None:
    """Gráfico destacado con la identidad del icono: degradado verde, C de cristal y marca.

    El fondo continúa el degradado del máster (media de sus columnas de borde, fila a fila);
    la C se recorta del máster y se funde con ese fondo; a la derecha, la marca y una tira
    de colores de Wada en pocillo oscuro translúcido.
    """
    from PIL import ImageFilter

    combos = wada_colors()
    w, h = 1024, 500
    master = Image.open(MASTER).convert("RGB")
    mw, mh = master.size
    src = master.load()
    rows = []
    for y in range(mh):
        cols = [src[x, y] for x in list(range(0, 24)) + list(range(mw - 24, mw))]
        rows.append(tuple(sum(c[i] for c in cols) // len(cols) for i in range(3)))
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)
    for y in range(h):
        draw.line((0, y, w, y), fill=rows[min(mh - 1, round(y * (mh - 1) / (h - 1)))])

    # C de cristal: recorte del máster con borde fundido sobre el fondo.
    crop = master.crop((round(mw * 0.13), round(mh * 0.10), round(mw * 0.87), round(mh * 0.90)))
    ch = 470
    cw = round(crop.width * ch / crop.height)
    crop = crop.resize((cw, ch), Image.LANCZOS).convert("RGBA")
    feather = 46
    mask = Image.new("L", crop.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((feather, feather, cw - feather, ch - feather), radius=60, fill=255)
    crop.putalpha(mask.filter(ImageFilter.GaussianBlur(feather / 2)))
    base = img.convert("RGBA")
    base.alpha_composite(crop, (40, (h - ch) // 2))
    img = base.convert("RGB")
    draw = ImageDraw.Draw(img)

    # Marca (derecha).
    gold = (240, 214, 150)
    x0 = 520
    draw.text((x0 + 4, 150), "SANZO  WADA  ·  1933", font=ui_font(24), fill=gold)
    size = 108
    title_font = brand_font(size)
    while draw.textlength("ChromaSol", font=title_font) > 460 and size > 40:
        size -= 4
        title_font = brand_font(size)
    draw.text((x0, 178), "ChromaSol", font=title_font, fill=(250, 250, 244))
    # Tira de colores de Wada en pocillo oscuro translúcido.
    strip_colors = combos[BRAND_STRIP_IDS[0]] + combos[BRAND_STRIP_IDS[1]][:1] + [AMBER]
    well = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(well).rounded_rectangle((x0 + 4, 322, x0 + 444, 378), radius=14, fill=(255, 255, 255, 40),
                                           outline=(255, 255, 255, 90), width=2)
    img = Image.alpha_composite(img.convert("RGBA"), well).convert("RGB")
    swatch_row(img, (x0 + 16, 333, x0 + 432, 367), strip_colors)

    img.save(PLAY_DIR / "feature_graphic.png", optimize=True)
    print("OK feature_graphic.png 1024x500 RGB (degradado y C del icono, marca y tira de Wada)")


def verify() -> None:
    icon = Image.open(PLAY_DIR / "icon_512.png")
    assert icon.size == (512, 512), f"icon_512.png: {icon.size}"
    assert icon.mode == "RGBA", f"icon_512.png: modo {icon.mode}, se espera RGBA (32 bits)"
    feature = Image.open(PLAY_DIR / "feature_graphic.png")
    assert feature.size == (1024, 500), f"feature_graphic.png: {feature.size}"
    assert feature.mode == "RGB", f"feature_graphic.png: modo {feature.mode}, se espera RGB sin alfa"
    print("PASS icon_512.png (512, 512) RGBA · feature_graphic.png (1024, 500) RGB")


def main() -> int:
    make_icons()
    make_feature_graphic()
    verify()
    return 0


if __name__ == "__main__":
    sys.exit(main())
