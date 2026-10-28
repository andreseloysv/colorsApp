#!/usr/bin/env python3
"""Comprueba límites y reglas de la ficha de Google Play.

Uso (desde la raíz del repo):
  python3 docs/play/tools/check_limits.py

Comprueba, para es-ES, de-DE y en-US:
- title.txt <= 30 caracteres y empieza por «ChromaSol».
- short_description.txt <= 80 caracteres.
- full_description.txt <= 4000 caracteres, texto plano sin emojis,
  sin «best»/«#1» ni superlativos equivalentes, sin líneas en mayúsculas
  sostenidas, y con las menciones obligatorias: sin conexión/offline,
  sin cuenta, sin anuncios, sin compras dentro de la app y pago único.
- release_notes.txt <= 500 caracteres.
- Ninguna referencia a iOS: iPhone, iOS, iCloud, App Store, carrete/Fotos
  de Apple (ver FORBIDDEN).
- Si existen, icon_512.png (512x512) y feature_graphic.png (1024x500,
  sin alfa) en docs/play/.

Sale con código 1 si algo falla. No modifica ningún fichero.
"""

import re
import sys
import unicodedata
from pathlib import Path

PLAY_DIR = Path(__file__).resolve().parents[1]
LISTING_DIR = PLAY_DIR / "listing"

LIMITS = {
    "title.txt": 30,
    "short_description.txt": 80,
    "full_description.txt": 4000,
    "release_notes.txt": 500,
}

LOCALES = ("es-ES", "de-DE", "en-US")

# Términos de iOS que nunca deben aparecer en la ficha de Android.
FORBIDDEN = (
    "iphone",
    "ios",
    "icloud",
    "app store",
    "apple vision",
    "vision framework",
    "carrete",
    "fotomediathek",
    "photo library",
    "#1",
    "best app",
    "la mejor",
    "die beste",
)

# Menciones obligatorias en full_description, por idioma:
# (etiqueta, alternativas aceptadas en minúsculas)
REQUIRED = {
    "es-ES": (
        ("sin conexión / offline", ("sin conexión", "offline")),
        ("sin cuenta", ("sin cuenta", "no requiere cuenta", "no tiene cuentas")),
        ("sin anuncios", ("sin anuncios",)),
        ("sin compras dentro de la app", ("sin compras dentro de la app",)),
        ("pago único", ("pago único",)),
        ("348 combinaciones", ("348",)),
        ("Sanzo Wada", ("sanzo wada",)),
    ),
    "de-DE": (
        ("offline", ("offline",)),
        ("ohne Konto", ("ohne konto", "kein konto", "keinen server")),
        ("keine Werbung", ("keine werbung",)),
        ("keine In-App-Käufe", ("keine in-app-käufe",)),
        ("einmaliger Kauf", ("einmaliger kauf",)),
        ("348 Kombinationen", ("348",)),
        ("Sanzo Wada", ("sanzo wada",)),
    ),
    "en-US": (
        ("offline", ("offline",)),
        ("no account", ("no account", "requires no account")),
        ("no ads", ("no ads",)),
        ("no in-app purchases", ("no in-app purchases",)),
        ("one-time purchase", ("one-time purchase",)),
        ("348 combinations", ("348",)),
        ("Sanzo Wada", ("sanzo wada",)),
    ),
}


def has_emoji(text: str) -> bool:
    for ch in text:
        category = unicodedata.category(ch)
        if category == "So" or ord(ch) >= 0x1F300:
            return True
    return False


def caps_lock_lines(text: str) -> list[str]:
    """Líneas con 4 o más letras y todas en mayúsculas (p. ej. cabeceras a gritos)."""
    bad = []
    for line in text.splitlines():
        letters = [c for c in line if c.isalpha()]
        if len(letters) >= 4 and all(c.isupper() for c in letters):
            bad.append(line.strip())
    return bad


def main() -> int:
    failures = 0

    def report(ok: bool, message: str) -> None:
        nonlocal failures
        print(f"{'PASS' if ok else 'FAIL'} {message}")
        failures += 0 if ok else 1

    for locale in LOCALES:
        print(f"== {locale}")
        texts = {}
        for name, limit in LIMITS.items():
            path = LISTING_DIR / locale / name
            if not path.exists():
                report(False, f"{locale}/{name}: no existe")
                continue
            value = path.read_text(encoding="utf-8").strip()
            texts[name] = value
            report(
                len(value) <= limit and len(value) > 0,
                f"{locale}/{name}: {len(value)}/{limit} caracteres",
            )
        title = texts.get("title.txt", "")
        if title:
            report(title.startswith("ChromaSol"), f"{locale}/title.txt: empieza por ChromaSol: {title!r}")
        full = texts.get("full_description.txt", "")
        if full:
            report(not has_emoji(full), f"{locale}/full_description.txt: sin emojis")
            bad_caps = caps_lock_lines(full)
            report(not bad_caps, f"{locale}/full_description.txt: sin mayúsculas sostenidas {bad_caps or ''}".rstrip())
            lowered = full.lower()
            for label, alternatives in REQUIRED[locale]:
                found = any(alt in lowered for alt in alternatives)
                report(found, f"{locale}/full_description.txt: menciona «{label}»")
            # «best» suelto solo se prohíbe en inglés (en alemán es parte de otras palabras).
            if locale == "en-US":
                report(not re.search(r"\bbest\b", lowered), f"{locale}/full_description.txt: sin «best»")
        for name, value in texts.items():
            lowered = value.lower()
            for word in FORBIDDEN:
                # Palabra completa: «ios» suelto como subcadena daría falsos
                # positivos en español («varios», «anuncios»).
                pattern = r"(?<![a-záéíóúüñ])" + re.escape(word) + r"(?![a-záéíóúüñ])"
                if re.search(pattern, lowered):
                    report(False, f"{locale}/{name}: contiene término prohibido «{word}»")
        print(f"   ({locale}: sin términos prohibidos si no hay FAIL encima)")

    print("== gráficos")
    try:
        from PIL import Image

        icon_path = PLAY_DIR / "icon_512.png"
        if icon_path.exists():
            icon = Image.open(icon_path)
            report(icon.size == (512, 512), f"icon_512.png: tamaño {icon.size} (esperado (512, 512))")
            report(icon.mode in ("RGB", "RGBA"), f"icon_512.png: modo {icon.mode} (PNG de 32 bits = RGBA u opaco RGB a 512)")
        else:
            report(False, "icon_512.png: no existe (ejecuta tools/make_graphics.py)")
        feature_path = PLAY_DIR / "feature_graphic.png"
        if feature_path.exists():
            feature = Image.open(feature_path)
            report(feature.size == (1024, 500), f"feature_graphic.png: tamaño {feature.size} (esperado (1024, 500))")
            report(feature.mode == "RGB", f"feature_graphic.png: modo {feature.mode} (esperado RGB, sin alfa)")
        else:
            report(False, "feature_graphic.png: no existe (ejecuta tools/make_graphics.py)")
    except ImportError:
        report(False, "gráficos: falta Pillow (python3 -m pip install Pillow o brew install pillow)")

    print("RESULT:", "PASS" if failures == 0 else f"FAIL ({failures})")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
