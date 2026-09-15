#!/usr/bin/env python3
"""Fotos de prueba con personas (CC0, Wikimedia Commons) para la extracción de sujeto.

    # descarga (curl) + normalización + SOURCES.md; los originales se borran al final
    uv run --project oracle python harness/people/build_people.py build --workdir <dir temporal>
    # verificación offline: sha256 de SOURCES.md, lado mayor 1024, perfil sRGB, expected.json
    # coherente (bbox dentro de la imagen, partes y hex válidos), sin JPEG sueltos, directorio < 8 MB
    uv run --project oracle python harness/people/build_people.py check

Normalización (en este orden): ``ImageOps.exif_transpose`` -> perfil ICC a sRGB con
``ImageCms`` (intent perceptual; misma regla que ``oracle/tools/to_ppm.py``: si la
descripción del perfil contiene "sRGB" no se convierte, sin perfil se asume sRGB) ->
RGB 8 bits -> lado mayor 1024 px con ``Image.BICUBIC`` (en espacio sRGB codificado; se
prefirió a LANCZOS porque el PNG sale ~4 % más pequeño y el set cabe en < 8 MB) ->
PNG con el perfil "sRGB built-in" de LittleCMS (fecha fija) embebido y sin EXIF; mismo
JPEG de entrada y misma versión de Pillow -> mismos bytes.

La descarga es la miniatura de 1280 px de ancho que sirve Commons (``iiurlwidth=1280``);
Commons puede regenerar miniaturas, así que ``build`` no garantiza los mismos bytes:
la referencia es el sha256 anotado en SOURCES.md y ``check`` lo comprueba.
Solo red en esta herramienta del harness; la app nunca usa red.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import io
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image, ImageCms, ImageOps

HERE = Path(__file__).resolve().parent
API = "https://commons.wikimedia.org/w/api.php"
UA = "colorsApp-harness/0.1 (test fixtures; curl)"
LONG_SIDE = 1024
MAX_TOTAL_BYTES = 8_000_000  # "< 8 MB" en decimal, más estricto que 8 MiB

# (fichero PNG, título en Commons, categoría del set)
SOURCES = [
    ("01_single_black_outfit.png", "File:Woman Entrance Gate Signs (Unsplash).jpg",
     "1 persona, cuerpo entero, ropa negra"),
    ("02_single_dress_umbrella.png", "File:Woman with umbrella (Unsplash).jpg",
     "1 persona, cuerpo entero, vestido azul marino estampado, paraguas negro"),
    ("03_couple_denim_street.png", "File:Moscow, Taganka, people April 2025 01.jpg",
     "2 personas, denim"),
    ("04_two_women_backlit.png", "File:Females in jeans at Joplin (Unsplash).jpg",
     "2 personas, contraluz, ropa oscura"),
    ("05_three_friends_closeup.png", "File:Friends show off engagement ring (Unsplash).jpg",
     "3 personas, plano medio posado, denim"),
    ("06_group_courier_street.png", "File:Moscow, Taganka, people April 2025 15.jpg",
     "grupo de 4 o más, calle, objeto amarillo saturado, denim"),
    ("07_group_mural_white_outfits.png", "File:Goddesses Among Men (Unsplash).jpg",
     "grupo de 4 o más, mural muy saturado"),
    ("08_artist_colorful_mural.png", "File:Artist spray painting flowers (Unsplash).jpg",
     "fondo muy cargado de color (mural saturado), 1 persona con mascarilla"),
]

CC0_TEMPLATES = re.compile(r"\{\{\s*(self\s*\|\s*cc-zero|cc-zero|unsplash|pd-[a-z0-9-]+)\s*[|}]", re.I)


def api(params: dict) -> dict:
    url = API + "?" + urllib.parse.urlencode({"format": "json", **params})
    for attempt in range(6):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.load(r)
        except urllib.error.HTTPError as exc:  # 429: limitación de Commons
            if exc.code != 429:
                raise
            time.sleep(10 * (attempt + 1))
    raise RuntimeError("Commons devuelve 429 de forma persistente")


def strip_html(s: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", s or "")).strip()


def commons_meta(title: str) -> dict:
    d = api({"action": "query", "titles": title, "prop": "imageinfo|revisions",
             "rvprop": "content", "rvslots": "main", "iiurlwidth": "1280",
             "iiprop": "url|size|extmetadata"})
    page = next(iter(d["query"]["pages"].values()))
    ii = page["imageinfo"][0]
    em = ii["extmetadata"]
    wikitext = page["revisions"][0]["slots"]["main"]["*"]
    lic = strip_html(em.get("LicenseShortName", {}).get("value", ""))
    if lic != "CC0" or not CC0_TEMPLATES.search(wikitext):
        raise RuntimeError(f"{title}: licencia no CC0/PD en la página del fichero ({lic!r})")
    notes = []
    m = re.search(r"photo-(\d{13})", wikitext)
    if m:
        up = dt.datetime.fromtimestamp(int(m.group(1)) / 1000, dt.timezone.utc).date().isoformat()
        notes.append(f"id Unsplash photo-{m.group(1)} = {up} UTC")
    if "Images from Unsplash (review needed)" in wikitext:
        notes.append("categoría Commons *Images from Unsplash (review needed)*")
    return {
        "notes": "; ".join(notes) or "—",
        "page": ii["descriptionurl"],
        "thumb": ii["thumburl"],
        "orig_size": f'{ii["width"]}x{ii["height"]}',
        "thumb_size": f'{ii["thumbwidth"]}x{ii["thumbheight"]}',
        "author": strip_html(em.get("Artist", {}).get("value", "")),
        "license": strip_html(em.get("UsageTerms", {}).get("value", "")),
        "license_url": em.get("LicenseUrl", {}).get("value", ""),
        "template": CC0_TEMPLATES.search(wikitext).group(0).strip("{|} "),
        "date": strip_html(em.get("DateTimeOriginal", {}).get("value", "")),
    }


def to_srgb(img: Image.Image) -> tuple[Image.Image, str]:
    icc = img.info.get("icc_profile")
    if not icc:
        return img.convert("RGB"), "sin perfil ICC: se asume sRGB"
    src = ImageCms.ImageCmsProfile(io.BytesIO(icc))
    desc = (ImageCms.getProfileDescription(src) or "").strip()
    if "srgb" in desc.lower():
        return img.convert("RGB"), f"perfil '{desc}' ya es sRGB"
    out = ImageCms.profileToProfile(img.convert("RGB"), src, ImageCms.createProfile("sRGB"),
                                    renderingIntent=ImageCms.Intent.PERCEPTUAL, outputMode="RGB")
    return out, f"perfil '{desc}' -> sRGB (perceptual)"


def srgb_icc() -> bytes:
    """Perfil "sRGB built-in" de LittleCMS con fecha fija (bytes 24-35 del encabezado ICC).

    LittleCMS estampa la hora de creación; sin fijarla, cada build daría otro sha256.
    El ProfileID (bytes 84-99) va a cero, así que cambiar la fecha no lo invalida.
    """
    icc = bytearray(ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes())
    assert icc[84:100] == bytes(16), "ProfileID calculado: no se puede fijar la fecha"
    icc[24:36] = bytes.fromhex("07ea0009000f000000000000")  # 2026-09-15 00:00:00
    return bytes(icc)


def normalize(src: Path, dst: Path) -> str:
    with Image.open(src) as im:
        im.load()
        img = ImageOps.exif_transpose(im)
        img, note = to_srgb(img)
    w, h = img.size
    scale = LONG_SIDE / max(w, h)
    size = (max(1, round(w * scale)), max(1, round(h * scale)))
    img = img.resize(size, Image.BICUBIC)
    img.save(dst, format="PNG", optimize=True, icc_profile=srgb_icc())
    return f"{w}x{h} -> {size[0]}x{size[1]}; {note}"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_sources_md(rows: list[dict]) -> None:
    lines = [
        "# Fotos de prueba con personas (`harness/people/`)",
        "",
        "Ocho fotografías de Wikimedia Commons con licencia **CC0 1.0** (dedicación al dominio",
        "público), verificada en la página de cada fichero (plantilla de licencia del wikitext y",
        "`LicenseShortName` de la API; las de Unsplash llevan `{{Unsplash}}`, que Commons solo",
        "admite para fotos publicadas en Unsplash antes del 5 de junio de 2017, cuando Unsplash",
        "dejó CC0). No se usó ninguna CC BY/CC BY-SA. Uso: inspección de la extracción de sujeto",
        "(personas, pose, piel, máscara); **no** son verdad de color ni entran en L4.",
        "",
        "Descarga: miniatura de 1280 px de ancho servida por Commons (JPEG recomprimido por su",
        "servidor de miniaturas, no el original de cámara), con `curl`. Normalización y",
        "verificación: `build_people.py` (ver cabecera). Los originales descargados se borraron.",
        "",
        "```sh",
        "uv run --project oracle python harness/people/build_people.py check   # offline",
        "uv run --project oracle python oracle/tools/to_ppm.py harness/people/03_couple_denim_street.png <scratch>/03.ppm",
        "```",
        "",
        "## Cobertura",
        "",
        "| Pedido | Fotos |",
        "|---|---|",
        "| 1 persona de cuerpo entero (una con ropa negra) | 01 (negro), 02 |",
        "| 2 o 3 personas (al menos una con denim) | 03 (denim), 04, 05 (denim) |",
        "| Grupos de 4 o más | 06 (5), 07 (6) |",
        "| Fondo muy cargado de color | 08 (y también 07) |",
        "",
        "Casos difíciles incluidos a propósito: paraguas negro que puede entrar en la máscara (02),",
        "personas de espaldas sin cara (03, 04), contraluz y manta que no es de nadie (04), mano en",
        "primer plano y tamaños empatados (05), oclusiones y objeto amarillo saturado (06), ropa",
        "blanca sobre mural saturado (07), cara tapada por mascarilla y ropa blanca con dominante",
        "azul (08).",
        "",
        "## `expected.json`",
        "",
        "Anotación hecha a mano mirando cada PNG: valores **orientativos para inspección visual de",
        "las capas**, no verdad de color ni gate de ningún umbral.",
        "",
        "- `people`: número aproximado de personas reconocibles (sin contar figuras diminutas).",
        "- `largest_person.bbox_hint`: `[x0, y0, x1, y1]` en píxeles del PNG, origen arriba a la",
        "  izquierda, caja aproximada de la persona que parece mayor en área; si hay empate lo dice",
        "  `notes`.",
        "- `garments[].color_hex`: mediana sRGB de un parche de esa prenda medido sobre el PNG",
        "  (incluye sombra y dominantes de la foto); `part` es `torso`, `legs` o `full`.",
        "- `notes`: resto de personas y prendas, objetos que no son ropa y trampas del fondo.",
        "",
        "## Límites",
        "",
        "- Tamaño: PNG sin pérdidas a 1024 px da ~0,7–1,3 MB por foto; con 8 fotos el límite",
        "  de 8 MB obligó a descartar candidatas con mucho detalle fino (grafiti de cuerpo entero,",
        "  grupos en plaza con 10 personas) y a reescalar con BICUBIC en vez de LANCZOS (−4 %).",
        "- Sin fotos de interior con luz cálida, ni de móvil (todas son de cámara y de fotógrafo);",
        "  ninguna en HEIC ni Display P3. No sustituyen al set dorado de L4.",
        "- Colores de `expected.json` medidos por mí sobre el PNG, sin consenso de jueces.",
        "",
        "## Fuentes",
        "",
        "| PNG | Categoría | Página de Commons | Autor | Licencia | Fecha foto | Evidencia | Descarga | Original → miniatura → PNG | sha256 del PNG |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for r in rows:
        lines.append(
            f'| `{r["file"]}` | {r["category"]} | [{r["title"][5:]}]({r["page"]}) | {r["author"]} | '
            f'{r["license"]} (`{{{{{r["template"].replace("|", chr(92) + "|")}}}}}`, {r["license_url"]}) | {r["date"]} | {r["notes"]} | '
            f'{r["downloaded"]} | {r["orig_size"]} → {r["thumb_size"]} → {r["png_size"]} | `{r["sha256"]}` |'
        )
    lines += [
        "",
        "## Notas de licencia",
        "",
        "- Fotos de Unsplash (plantilla `{{Unsplash}}`): la página de cada fichero dice \"published",
        "  prior to 5 June 2017 under the Creative Commons CC0 1.0\". Evidencia de fecha: campo",
        "  `date` del fichero y, cuando el wikitext archiva la URL `images.unsplash.com/photo-<ms>`,",
        "  su marca de tiempo Unix (columna Evidencia). La más ajustada es la 05 (2017-05-27).",
        "- La categoría *Images from Unsplash (review needed)* indica que ningún revisor de Commons",
        "  ha confirmado aún la licencia; ninguna tenía solicitud de borrado al revisarlas a mano",
        "  (2026-09-15).",
        "- Fotos con `{{self|cc-zero}}`: obra propia del autor en Commons.",
        "- CC0 no exige atribución; se registra igualmente. Hay personas identificables: CC0 cubre",
        "  el copyright, no los derechos de imagen (la página de la 05 lo advierte). Uso interno de",
        "  prueba; no usar en material promocional. Sin menores en primer plano ni contextos",
        "  sensibles. Si alguien pide retirarlas, se borran del repo.",
        "- Los murales de fondo de 07 y 08 son obras con posibles derechos propios (en EE. UU. no",
        "  hay libertad de panorama para obras 2D); Commons no las ha marcado. Aceptable como",
        "  fixture interno de prueba; no redistribuir fuera del repo.",
        "",
        "## Formato",
        "",
        "PNG RGB 8 bits, sRGB (perfil \"sRGB built-in\" embebido), lado mayor 1024 px, sin EXIF.",
        "`oracle/tools/to_ppm.py` las convierte a PPM sin tocar el color.",
        "",
    ]
    (HERE / "SOURCES.md").write_text("\n".join(lines), encoding="utf-8")


def cmd_build(args: argparse.Namespace) -> int:
    work = Path(args.workdir).resolve()
    work.mkdir(parents=True, exist_ok=True)
    today = dt.date.today().isoformat()
    rows = []
    for i, (fname, title, category) in enumerate(SOURCES, start=1):
        meta = commons_meta(title)
        orig = work / f"{i:02d}.jpg"
        if not orig.exists():
            subprocess.run(["curl", "-sS", "-f", "--retry", "5", "--retry-delay", "10",
                            "-A", UA, "-o", str(orig), meta["thumb"]], check=True)
            time.sleep(2)
        dst = HERE / fname
        note = normalize(orig, dst)
        with Image.open(dst) as im:
            png_size = f"{im.width}x{im.height}"
        rows.append({"file": fname, "title": title, "category": category, "downloaded": today,
                     "png_size": png_size, "sha256": sha256(dst), **meta})
        print(f"{fname}: {note}; {meta['author']}; {meta['template']}")
        if not args.keep_originals:
            orig.unlink()
    write_sources_md(rows)
    return cmd_check(args)


def cmd_check(_args: argparse.Namespace) -> int:
    errors = []
    md = (HERE / "SOURCES.md").read_text(encoding="utf-8")
    hashes = dict(re.findall(r"\| `([0-9]{2}_[a-z_]+\.png)` \|.*\| `([0-9a-f]{64})` \|", md))
    exp_path = HERE / "expected.json"
    expected = json.loads(exp_path.read_text(encoding="utf-8")) if exp_path.exists() else []
    if not expected:
        errors.append("expected.json no existe o está vacío")
    by_file = {e["file"]: e for e in expected}
    total = 0
    for fname, _title, _cat in SOURCES:
        p = HERE / fname
        if not p.exists():
            errors.append(f"{fname}: no existe")
            continue
        total += p.stat().st_size
        if hashes.get(fname) != sha256(p):
            errors.append(f"{fname}: sha256 distinto de SOURCES.md")
        with Image.open(p) as im:
            if im.mode != "RGB" or max(im.size) != LONG_SIDE:
                errors.append(f"{fname}: modo {im.mode} tamaño {im.size}")
            icc = im.info.get("icc_profile")
            desc = ImageCms.getProfileDescription(ImageCms.ImageCmsProfile(io.BytesIO(icc))) if icc else ""
            if "srgb" not in desc.lower():
                errors.append(f"{fname}: sin perfil ICC sRGB embebido")
            w, h = im.size
        e = by_file.get(fname)
        if e is None:
            errors.append(f"{fname}: falta en expected.json")
            continue
        x0, y0, x1, y1 = e["largest_person"]["bbox_hint"]
        if not (0 <= x0 < x1 <= w and 0 <= y0 < y1 <= h):
            errors.append(f"{fname}: bbox_hint {e['largest_person']['bbox_hint']} fuera de {w}x{h}")
        if not isinstance(e["people"], int) or e["people"] < 1:
            errors.append(f"{fname}: people inválido")
        for g in e["largest_person"]["garments"]:
            if g["part"] not in ("torso", "legs", "full") or not re.fullmatch(r"#[0-9a-f]{6}", g["color_hex"]):
                errors.append(f"{fname}: prenda inválida {g}")
    extra = set(by_file) - {s[0] for s in SOURCES}
    if extra:
        errors.append(f"expected.json con ficheros desconocidos: {sorted(extra)}")
    stray = sorted(p.name for p in HERE.iterdir() if p.suffix.lower() in (".jpg", ".jpeg"))
    if stray:
        errors.append(f"originales sin borrar: {stray}")
    dir_total = sum(p.stat().st_size for p in HERE.rglob("*") if p.is_file() and "__pycache__" not in p.parts)
    print(f"people: {len(SOURCES)} PNG = {total} B; directorio completo = {dir_total} B ({dir_total / 1e6:.2f} MB)")
    if dir_total >= MAX_TOTAL_BYTES:
        errors.append(f"tamaño total del directorio {dir_total} B >= {MAX_TOTAL_BYTES} B")
    for err in errors:
        print("ERROR", err, file=sys.stderr)
    print("check:", "FAIL" if errors else "OK")
    return 1 if errors else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--workdir", required=True,
                   help="directorio temporal para los JPEG descargados (NN.jpg; si ya existe se reutiliza)")
    b.add_argument("--keep-originals", action="store_true")
    b.set_defaults(func=cmd_build)
    c = sub.add_parser("check")
    c.set_defaults(func=cmd_check)
    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
