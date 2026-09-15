#!/usr/bin/env python3
"""Convierte una imagen a PPM P6 sRGB de 8 bits para ``ce palette`` / ``ce match``.

    uv run --project oracle python oracle/tools/to_ppm.py entrada.(png|jpg|...) salida.ppm
        [--max-side N] [--mask salida.pgm]

Pillow es el único decodificador (sección 5 del plan). Pasos, en este orden:

1. Abrir con Pillow. HEIC/HEIF -> error claro y exit 2 (no se instala ``pillow-heif``;
   exporta la foto a PNG o JPEG sRGB, como hace "Exportar diagnóstico" en la app).
2. ``ImageOps.exif_transpose``: la orientación EXIF se aplica a los píxeles.
3. Perfil ICC: si la imagen lo trae, se convierte a sRGB con ``ImageCms`` (intent
   perceptual) y se registra en stderr; si el perfil embebido ya es sRGB no se toca;
   si no hay perfil se asume sRGB (también en stderr).
4. ``--max-side N``: reducción por factor entero ``ceil(max(w, h) / N)`` con
   ``Image.reduce`` (promedio de bloque), la misma regla que el motor.
5. Escribe P6 (binario, maxval 255). Con ``--mask`` escribe además un P5 con el canal
   alfa (0..255, mismas dimensiones); sin alfa la máscara es 255 en todo el lienzo.

Códigos de salida: 0 ok; 2 uso, fichero ilegible, HEIC o error de conversión.
"""

from __future__ import annotations

import argparse
import io
import math
import sys
from pathlib import Path

from PIL import Image, ImageCms, ImageOps, UnidentifiedImageError

HEIF_SUFFIXES = {".heic", ".heif", ".hif", ".avif"}
HEIF_BRANDS = (b"heic", b"heix", b"hevc", b"hevx", b"mif1", b"msf1", b"avif")


def log(msg: str) -> None:
    print(f"to_ppm: {msg}", file=sys.stderr)


def looks_like_heif(path: Path) -> bool:
    """Detecta el contenedor ISOBMFF 'ftyp' con una marca HEIF/AVIF (independiente de la extensión)."""
    try:
        with path.open("rb") as f:
            head = f.read(32)
    except OSError:
        return False
    return len(head) >= 12 and head[4:8] == b"ftyp" and head[8:12] in HEIF_BRANDS


def to_srgb(img: Image.Image) -> tuple[Image.Image, str]:
    """Devuelve (imagen RGB en sRGB, nota para stderr) aplicando el perfil ICC embebido si lo hay."""
    icc = img.info.get("icc_profile")
    if not icc:
        return img.convert("RGB"), "sin perfil ICC: se asume sRGB"
    try:
        src_profile = ImageCms.ImageCmsProfile(io.BytesIO(icc))
        desc = (ImageCms.getProfileDescription(src_profile) or "").strip() or "(sin descripción)"
    except ImageCms.PyCMSError as exc:
        return img.convert("RGB"), f"perfil ICC ilegible ({exc}); se asume sRGB"
    if "srgb" in desc.lower():
        return img.convert("RGB"), f"perfil ICC '{desc}' ya es sRGB: sin conversión"
    dst_profile = ImageCms.createProfile("sRGB")
    source = img if img.mode in ("RGB", "RGBA", "CMYK", "L", "LAB") else img.convert("RGB")
    try:
        out = ImageCms.profileToProfile(
            source, src_profile, dst_profile,
            renderingIntent=ImageCms.Intent.PERCEPTUAL, outputMode="RGB",
        )
    except ImageCms.PyCMSError as exc:
        raise RuntimeError(f"no se pudo convertir el perfil ICC '{desc}' a sRGB: {exc}") from exc
    return out, f"perfil ICC '{desc}' ({source.mode}) -> sRGB, intent perceptual"


def reduce_factor(width: int, height: int, max_side: int | None) -> int:
    if not max_side or max_side < 1:
        return 1
    return max(1, int(math.ceil(max(width, height) / float(max_side))))


def write_p6(img: Image.Image, path: Path) -> None:
    if img.mode != "RGB":
        img = img.convert("RGB")
    w, h = img.size
    with path.open("wb") as f:
        f.write(f"P6\n{w} {h}\n255\n".encode("ascii"))
        f.write(img.tobytes())


def write_p5(mask: Image.Image, path: Path) -> None:
    if mask.mode != "L":
        mask = mask.convert("L")
    w, h = mask.size
    with path.open("wb") as f:
        f.write(f"P5\n{w} {h}\n255\n".encode("ascii"))
        f.write(mask.tobytes())


def convert(src: Path, dst: Path, max_side: int | None = None, mask_path: Path | None = None) -> tuple[int, int]:
    """Convierte ``src`` a ``dst`` (P6) y opcionalmente escribe la máscara P5. Devuelve (w, h) finales."""
    if src.suffix.lower() in HEIF_SUFFIXES or looks_like_heif(src):
        raise RuntimeError(
            f"{src.name}: HEIC/HEIF/AVIF no soportado (Pillow sin pillow-heif). "
            "Exporta la foto a PNG o JPEG sRGB (Fotos > Exportar, o 'Exportar diagnóstico' en la app)."
        )
    try:
        with Image.open(src) as opened:
            opened.load()
            img = ImageOps.exif_transpose(opened)
    except (UnidentifiedImageError, OSError) as exc:
        raise RuntimeError(f"{src}: no se puede abrir con Pillow ({exc})") from exc
    if img is None:  # exif_transpose(in_place=False) siempre devuelve imagen; por tipado
        raise RuntimeError(f"{src}: imagen vacía")
    alpha = img.getchannel("A") if "A" in img.getbands() else None
    rgb, note = to_srgb(img)
    log(note)
    factor = reduce_factor(rgb.width, rgb.height, max_side)
    if factor > 1:
        log(f"reducción x{factor} ({rgb.width}x{rgb.height} -> {rgb.width // factor}x{rgb.height // factor}, promedio de bloque)")
        rgb = rgb.reduce(factor)
        if alpha is not None:
            alpha = alpha.reduce(factor)
    if rgb.width < 1 or rgb.height < 1:
        raise RuntimeError("la imagen queda vacía tras la reducción")
    write_p6(rgb, dst)
    if mask_path is not None:
        if alpha is None:
            log("sin canal alfa: la máscara es 255 en toda la imagen")
            alpha = Image.new("L", rgb.size, 255)
        write_p5(alpha, mask_path)
    return rgb.width, rgb.height


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", type=Path, help="imagen de entrada (PNG, JPEG, TIFF, WebP, BMP, GIF...)")
    ap.add_argument("output", type=Path, help="PPM P6 de salida")
    ap.add_argument("--max-side", type=int, default=None, help="reduce por factor entero hasta que el lado mayor sea <= N")
    ap.add_argument("--mask", type=Path, default=None, help="escribe el canal alfa como PGM P5 (255 si no hay alfa)")
    try:
        args = ap.parse_args(argv)
    except SystemExit as exc:
        return 2 if exc.code else 0
    if args.max_side is not None and args.max_side < 1:
        log("--max-side debe ser >= 1")
        return 2
    if not args.input.is_file():
        log(f"{args.input}: no existe o no es un fichero")
        return 2
    try:
        w, h = convert(args.input, args.output, args.max_side, args.mask)
    except (RuntimeError, OSError, ValueError) as exc:
        log(str(exc))
        return 2
    log(f"escrito {args.output} ({w}x{h}, P6)" + (f" y {args.mask} (P5)" if args.mask else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
