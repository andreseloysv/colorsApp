#!/usr/bin/env python3
"""Informe visual de capas: de qué píxeles sale cada color (``make layers-report``).

    uv run --project oracle python oracle/tools/layers_report.py FOTO... --out harness/out/layers
        [--ce build-seg/tools/ce] [--visionmask build-subject/visionmask | --no-visionmask]
        [--build-visionmask] [--variants none,largest,largest-clothing,largest-clothing-skin]
        [--max-side 256] [--expected expected.json] [--top 3]

Requisito del usuario tras probar la app: «The colors are not right. It will be helpful for me to
see the layers from which the color is being extracted». Para cada foto y cada variante de
recorte ejecuta, sobre el Mac:

1. ``visionmask <foto> --layers`` (una vez por foto): raster exacto de la app (CoreGraphics sRGB,
   lado <= 1024), personas de Vision, pose, región de ropa, muestra de cara, piel quitada y
   máscara final de cada variante (``<foto>.<variante>.layers/``);
2. ``ce match <raster> [--mask <foto>.<variante>.pgm] --top 3 --json --debug-dir DIR``: imagen
   reducida, peso por píxel, clusters de Lloyd con su destino (conservado, fusionado, descartado,
   recortado), label map, qué píxeles alimentan cada swatch y la explicación del top-3
   (``ce_match_explain_combo``: ajuste + cobertura + penalización de hipótesis).

y escribe ``OUT/index.html``: HTML estático autocontenido (imágenes PNG en base64, sin red ni
JavaScript), un resumen arriba y, por foto, una fila por variante y una columna por capa: foto,
raster, reducida, personas, pose y región de ropa, piel quitada (magenta), máscara final, peso,
clusters, label map, paleta con porcentajes y top-3 con «por qué ganó». Las imágenes se reducen
a ``--max-side`` (256) px. Los ficheros intermedios quedan en ``OUT/work/`` con los comandos para
reproducir cada capa desde la terminal; ``OUT/layers.json`` resume los números.

Las fotos personales nunca entran en el repo: ``harness/out/`` está en .gitignore y ``OUT`` puede
estar fuera (``make layers-report IMAGES="~/Fotos/*.jpg" OUT=~/capas``). Sin visionmask solo se
genera la fila ``none`` (raster de Pillow) y las demás quedan marcadas «sin visionmask».

Exit: 0 informe escrito (aunque alguna foto o variante tenga error, que se muestra en el HTML);
1 si ninguna foto pudo analizarse; 2 uso (sin fotos, sin ``ce`` con ``--debug-dir``).
"""

from __future__ import annotations

import argparse
import base64
import glob
import html
import io
import json
import math
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageDraw, ImageOps

ORACLE_DIR = Path(__file__).resolve().parents[1]
if str(ORACLE_DIR) not in sys.path:
    sys.path.insert(0, str(ORACLE_DIR))

from l4 import variants as l4v  # noqa: E402
from oracle.l2 import find_cli_optional  # noqa: E402

REPO_ROOT = ORACLE_DIR.parent
DEFAULT_VARIANTS = ["none", "largest", "largest-clothing", "largest-clothing-skin"]
DEFAULT_OUT = REPO_ROOT / "harness" / "out" / "layers"
DICTIONARY = REPO_ROOT / "data" / "wada" / "dictionary.json"
NAMES_ES = REPO_ROOT / "data" / "wada" / "names.es.json"
PHOTO_SUFFIXES = {".png", ".jpg", ".jpeg", ".heic", ".heif"}
MIN_CONFIDENCE = 0.3  # ce_region_opts_default: min_confidence
BONES = [(0, 1), (1, 2), (1, 3), (2, 3), (2, 4), (4, 6), (3, 5), (5, 7), (2, 8), (3, 9), (8, 9), (1, 14),
         (8, 10), (10, 12), (9, 11), (11, 13)]
FATES = {0: "conservado", 1: "fusionado", 2: "descartado por peso", 3: "recortado (máx. colores)"}
ILLUMINANTS_ES = {"none": "sin cambio", "A": "A (tungsteno)", "D50": "D50", "D75": "D75 (sombra)", "F2": "F2 (fluorescente)"}
SIZE_WARN_BYTES = 30 * 1024 * 1024


# --------------------------------------------------------------------------------------
# Entrada
# --------------------------------------------------------------------------------------


def collect_images(patterns: list[str]) -> list[Path]:
    """Ficheros, directorios o globs (con ``~``) -> fotos PNG/JPEG/HEIC únicas, en orden."""
    out: list[Path] = []
    seen: set[Path] = set()
    for raw in patterns:
        expanded = str(Path(raw).expanduser()) if raw.startswith("~") else raw
        p = Path(expanded)
        if p.is_dir():
            found = sorted(q for q in p.iterdir() if q.suffix.lower() in PHOTO_SUFFIXES)
        elif p.is_file():
            found = [p]
        else:
            found = sorted(Path(g) for g in glob.glob(expanded))
        for q in found:
            r = q.resolve()
            if q.is_file() and q.suffix.lower() in PHOTO_SUFFIXES and r not in seen:
                seen.add(r)
                out.append(q)
    return out


def load_dictionary() -> tuple[dict[int, list[int]], list[dict[str, Any]], dict[int, str]]:
    d = json.loads(DICTIONARY.read_text(encoding="utf-8"))
    combos = {int(c["id"]): [int(i) for i in c["colors"]] for c in d["combinations"]}
    names: dict[int, str] = {}
    if NAMES_ES.is_file():
        for n in json.loads(NAMES_ES.read_text(encoding="utf-8")):
            if isinstance(n, dict) and n.get("name") and n.get("status") != "pending":
                names[int(n["id"])] = str(n["name"])
    return combos, d["colors"], names


def load_expected(path: Path | None, images: list[Path]) -> dict[str, dict[str, Any]]:
    candidates = [path] if path else sorted({img.parent / "expected.json" for img in images})
    out: dict[str, dict[str, Any]] = {}
    for c in candidates:
        if c and c.is_file():
            try:
                for e in json.loads(c.read_text(encoding="utf-8")):
                    if isinstance(e, dict) and isinstance(e.get("file"), str):
                        out[e["file"]] = e
            except (json.JSONDecodeError, TypeError):
                continue
    return out


def has_debug_dir(cli: Path | None) -> bool:
    if cli is None:
        return False
    proc = subprocess.run([str(cli)], capture_output=True, text=True, check=False)
    return "--debug-dir" in (proc.stdout + proc.stderr)


def read_pose(path: Path) -> list[tuple[float, float, float]] | None:
    if not path.is_file():
        return None
    pts: list[tuple[float, float, float]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 3:
            pts.append((float(parts[0]), float(parts[1]), float(parts[2])))
    return pts if len(pts) >= 15 else None


# --------------------------------------------------------------------------------------
# Imágenes
# --------------------------------------------------------------------------------------


def thumb_size(w: int, h: int, max_side: int) -> tuple[int, int]:
    f = min(1.0, max_side / float(max(w, h)))
    return max(1, round(w * f)), max(1, round(h * f))


def png_data_uri(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def open_rgb(path: Path) -> Image.Image:
    with Image.open(path) as im:
        return im.convert("RGB")


def open_mask(path: Path, size: tuple[int, int]) -> Image.Image | None:
    """Máscara PGM reescalada a ``size`` con promedio de caja (bordes suaves, 0..255)."""
    if not path.is_file():
        return None
    with Image.open(path) as im:
        m = im.convert("L")
    return m if m.size == size else m.resize(size, Image.Resampling.BOX)


def gray_base(photo: Image.Image, dim: float) -> Image.Image:
    g = ImageOps.grayscale(photo).point(lambda v: int(v * dim))
    return Image.merge("RGB", (g, g, g))


def checker(size: tuple[int, int], a: int = 58, b: int = 78, cell: int = 8) -> Image.Image:
    img = Image.new("RGB", size, (a, a, a))
    draw = ImageDraw.Draw(img)
    for y in range(0, size[1], cell):
        for x in range((y // cell) % 2 * cell, size[0], 2 * cell):
            draw.rectangle([x, y, x + cell - 1, y + cell - 1], fill=(b, b, b))
    return img


def tint(base: Image.Image, mask: Image.Image | None, color: tuple[int, int, int], alpha: float) -> Image.Image:
    if mask is None:
        return base
    layer = Image.new("RGB", base.size, color)
    return Image.composite(layer, base, mask.point(lambda v: int(v * alpha)))


def draw_pose(img: Image.Image, pose: list[tuple[float, float, float]], scale: float) -> None:
    draw = ImageDraw.Draw(img)
    ok = [c > 0 and math.isfinite(x) and math.isfinite(y) for x, y, c in pose]
    for a, b in BONES:
        if ok[a] and ok[b]:
            draw.line([(pose[a][0] * scale, pose[a][1] * scale), (pose[b][0] * scale, pose[b][1] * scale)],
                      fill=(255, 214, 0), width=2)
    for (x, y, c), good in zip(pose, ok):
        if not good:
            continue
        r = 3
        box = [x * scale - r, y * scale - r, x * scale + r, y * scale + r]
        if c >= MIN_CONFIDENCE:
            draw.ellipse(box, fill=(0, 200, 255), outline=(0, 0, 0))
        else:
            draw.ellipse(box, outline=(0, 200, 255))


# --------------------------------------------------------------------------------------
# Ejecución por foto
# --------------------------------------------------------------------------------------


def safe_name(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", text)[:80] or "foto"


def run_ce_match(cli: Path, raster: Path, mask: Path | None, top: int, debug_dir: Path) -> dict[str, Any]:
    cmd = [str(cli), "match", str(raster)] + (["--mask", str(mask)] if mask else []) + ["--top", str(top), "--json", "--debug-dir", str(debug_dir)]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=120)
    out: dict[str, Any] = {"cmd": cmd}
    if proc.returncode != 0:
        out["error"] = f"ce match -> exit {proc.returncode}: {proc.stderr.strip()[:300]}"
        return out
    try:
        out["result"] = json.loads(proc.stdout)
        out["debug"] = json.loads((debug_dir / "debug.json").read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        out["error"] = f"ce match: salida ilegible ({exc})"
    return out


def shell_join(cmd: list[str]) -> str:
    return " ".join(c if re.fullmatch(r"[A-Za-z0-9_./=:,+-]+", c) else "'" + c.replace("'", "'\\''") + "'" for c in cmd)


def analyze_photo(index: int, photo: Path, *, cli: Path, visionmask: Path | None, vm_reason: str, variants: list[str],
                  work_root: Path, top: int, log=print) -> dict[str, Any]:
    stem = photo.stem
    work = work_root / f"{index:02d}-{safe_name(stem)}"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    rec: dict[str, Any] = {"file": str(photo), "name": photo.name, "work": str(work), "variants": {}, "commands": []}
    doc = None
    if visionmask is not None:
        masked = [v for v in variants if v != "none"]
        try:
            doc = l4v.run_visionmask(visionmask, photo, work, masked or ["none"], layers=True)
            rec["commands"].append(shell_join([str(visionmask), str(photo), "--out-dir", str(work), "--variants", ",".join(masked or ["none"]), "--layers"]))
        except l4v.VariantError as exc:
            rec["vision_error"] = str(exc)
            log(f"  [error] {exc}")
    if doc is not None:
        raster = Path(doc["raster"])
        rec.update({"raster": str(raster), "raster_source": "visionmask (CoreGraphics sRGB, como la app)", "people": int(doc.get("people_count") or 0),
                    "people_detail": doc.get("people") or [], "vision": doc.get("vision") or {}, "width": doc.get("width"), "height": doc.get("height"),
                    "source_size": [doc.get("source_width"), doc.get("source_height")], "orientation": doc.get("orientation")})
    else:
        from tools import to_ppm

        raster = work / f"{safe_name(stem)}.ppm"
        try:
            w, h = to_ppm.convert(photo, raster, max_side=1024)
        except RuntimeError as exc:
            rec["error"] = str(exc)
            return rec
        rec.update({"raster": str(raster), "raster_source": "Pillow (tools/to_ppm.py; sin visionmask: puede diferir 1/255 del de la app)",
                    "people": None, "people_detail": [], "width": w, "height": h})
    for v in variants:
        cell: dict[str, Any] = {"variant": v}
        vm_entry = l4v.variant_entry(doc, v) if doc is not None else None
        if v != "none":
            if doc is None:
                cell["skipped"] = f"sin visionmask ({rec.get('vision_error') or vm_reason})"
                rec["variants"][v] = cell
                continue
            if vm_entry is None or "error" in vm_entry:
                cell["error"] = (vm_entry or {}).get("error") or f"visionmask no devolvió {v}"
                rec["variants"][v] = cell
                continue
            cell["vm"] = vm_entry
            cell["layers_dir"] = vm_entry.get("layers")
        mask = Path(vm_entry["mask"]) if vm_entry and isinstance(vm_entry.get("mask"), str) else None
        cell["mask"] = str(mask) if mask else None
        debug_dir = work / f"{safe_name(stem)}.{v}.debug"
        m = run_ce_match(cli, raster, mask, top, debug_dir)
        cell.update({k: m[k] for k in ("result", "debug", "error") if k in m})
        cell["debug_dir"] = str(debug_dir)
        rec["commands"].append(shell_join(m["cmd"]))
        if cell.get("layers_dir") and (Path(cell["layers_dir"]) / "repro.sh").is_file():
            rec["commands"].append(shell_join(["sh", str(Path(cell["layers_dir"]) / "repro.sh"), str(cli)]) + "   # recalcula región/piel con ce y compara byte a byte")
        rec["variants"][v] = cell
    return rec


# --------------------------------------------------------------------------------------
# Pistas y números
# --------------------------------------------------------------------------------------


def dominant(result: dict[str, Any] | None) -> dict[str, Any] | None:
    sw = (result or {}).get("swatches") or []
    return max(sw, key=lambda s: float(s["weight"])) if sw else None


def garment_de(result: dict[str, Any] | None, garments: list[dict[str, Any]]) -> float | None:
    dom = dominant(result)
    labs = [g["color_hex"] for g in garments if isinstance(g.get("color_hex"), str)]
    if dom is None or not labs:
        return None
    from l4 import people_smoke as ps

    return min(ps.de00(dom["lab"], ps.hex_to_lab(h)) for h in labs)


def hints(v: str, cell: dict[str, Any], expected_de: float | None) -> list[str]:
    out: list[str] = []
    vm = cell.get("vm") or {}
    steps = list(vm.get("steps") or [])
    if v != "none":
        if cell.get("mask") is None:
            out.append("sin máscara: se analizó la foto completa (" + (" → ".join(steps) or "sin pasos") + ")")
        cov = vm.get("mask_coverage")
        if isinstance(cov, (int, float)) and cell.get("mask") and cov < 0.05:
            out.append(f"la máscara final cubre solo el {100 * cov:.1f} % del raster: pocos píxeles, paleta frágil")
        if "wholePerson" in steps:
            out.append("la región de ropa quedó bajo la cobertura mínima: se usó la persona completa (entra pelo, cara y piel)")
        if "headCut" in steps:
            out.append("sin pose utilizable: se cortó la cabeza (18 % superior) en vez de recortar la ropa")
        if "skinGuard" in steps:
            out.append("salvaguarda de piel: se habría quitado demasiado; la máscara no se tocó")
        for p in vm.get("persons") or []:
            if p.get("skin_note"):
                out.append(f"piel: {p['skin_note']}")
        if v.endswith("-skin") and not any(s in steps for s in ("skinExcluded", "skinGuard")) and cell.get("mask"):
            out.append("piel adaptativa sin efecto (sin muestra de cara utilizable o nada que quitar)")
    dbg = cell.get("debug") or {}
    lost = sum(float(c["weight"]) for c in (dbg.get("palette_debug") or {}).get("clusters", []) if c.get("fate") in (2, 3))
    if lost >= 0.15:
        out.append(f"{100 * lost:.0f} % del peso quedó en clusters descartados o recortados: colores que no llegan a la paleta")
    dom = dominant(cell.get("result"))
    if dom is not None and float(dom["weight"]) >= 0.6:
        out.append(f"un solo color domina la paleta ({100 * float(dom['weight']):.0f} %)")
    if (cell.get("result") or {}).get("ambiguous") == 1:
        out.append("match ambiguo: el 2.º candidato está a menos de 1 punto de score")
    if expected_de is not None and expected_de > 10:
        out.append(f"el color dominante no se parece a la ropa anotada (ΔE00 {expected_de:.1f})")
    return out


# --------------------------------------------------------------------------------------
# HTML
# --------------------------------------------------------------------------------------

CSS = """
:root{--ink:#1d1d1f;--muted:#5f6368;--line:#d9d9de;--bg:#f6f6f4;--card:#fff;--accent:#0b57d0;--warn:#a04100}
body{margin:0;padding:24px 16px;background:var(--bg);color:var(--ink);font:14px/1.45 -apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif}
main{margin:0 auto}
h1{font-size:26px;margin:0 0 4px}h2{font-size:19px;margin:0 0 6px}h3{font-size:15px;margin:14px 0 6px}
p,li{max-width:1100px}.muted{color:var(--muted)}code,pre{font:12px/1.4 ui-monospace,Menlo,monospace}
pre{background:#fff;border:1px solid var(--line);padding:8px;overflow-x:auto;white-space:pre}
section.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;margin:18px 0}
.scroll{overflow-x:auto}
table{border-collapse:collapse}th,td{border:1px solid var(--line);padding:6px;vertical-align:top;text-align:left}
th{background:#eef0f3;font-weight:600;position:sticky;top:0}
table.layers>tbody>tr>td{min-width:170px;max-width:250px;font-size:12px}
table.layers>tbody>tr>td.variant{min-width:190px;background:#fafafa}
table.layers>tbody>tr>td.why{min-width:270px;max-width:330px}
table.layers img{display:block;width:100%;max-width:250px;height:auto;background:#222;border-radius:4px}
table.mini{width:100%}
img.px{image-rendering:pixelated}
tr.official td.variant{background:#e8f0fe;border-left:4px solid var(--accent)}
.badge{display:inline-block;padding:1px 6px;border-radius:9px;background:var(--accent);color:#fff;font-size:11px;margin-left:4px}
.step{display:inline-block;padding:0 5px;border-radius:4px;background:#eceff1;margin:1px 2px 1px 0;font:11px ui-monospace,Menlo,monospace}
.chip{display:inline-block;width:14px;height:14px;border-radius:3px;border:1px solid rgba(0,0,0,.25);vertical-align:-3px;margin-right:4px}
.big{width:22px;height:22px;vertical-align:-6px}
ul.hints{margin:6px 0 0;padding-left:16px;color:var(--warn)}ul.hints li{margin:2px 0}
.cap{color:var(--muted);margin-top:4px}
.sw{display:flex;align-items:center;gap:6px;margin:3px 0}.sw img{width:56px!important;max-width:56px!important}
table.mini{font-size:11px;margin-top:4px}table.mini td,table.mini th{padding:2px 4px}
.hit{border-top:1px solid var(--line);padding-top:4px;margin-top:4px}.pc{white-space:nowrap;font-size:11px}.hit:first-child{border-top:0;margin-top:0;padding-top:0}
.err{color:#b3261e}.na{color:var(--muted);font-style:italic}
table.summary td{font-size:12px}table.summary img{width:72px;height:auto;display:block}
td.off{background:#e8f0fe}
"""


def esc(x: Any) -> str:
    return html.escape(str(x), quote=True)


def chip(hex_color: str | None, big: bool = False) -> str:
    if not hex_color:
        return ""
    return f'<span class="chip{" big" if big else ""}" style="background:{esc(hex_color)}" title="{esc(hex_color)}"></span>'


def img_tag(uri: str | None, alt: str, pixelated: bool = False) -> str:
    if uri is None:
        return f'<div class="na">{esc(alt)}: no disponible</div>'
    return f'<img src="{uri}" alt="{esc(alt)}"{" class=\"px\"" if pixelated else ""}>'


def combo_label(cid: int, names: dict[int, str]) -> str:
    return f"Nº {cid:03d}" + (f" · {names[cid]}" if cid in names else "")


class Renderer:
    def __init__(self, max_side: int, combos: dict[int, list[int]], colors: list[dict[str, Any]], names: dict[int, str]):
        self.max_side = max_side
        self.combos = combos
        self.colors = colors
        self.names = names
        self.images = 0
        self.image_bytes = 0

    def uri(self, img: Image.Image) -> str:
        u = png_data_uri(img)
        self.images += 1
        self.image_bytes += len(u)
        return u

    # --- capas de visionmask (resolución del raster) ---

    def photo_cells(self, rec: dict[str, Any]) -> dict[str, Any]:
        raster = open_rgb(Path(rec["raster"]))
        size = thumb_size(raster.width, raster.height, self.max_side)
        thumb = raster.resize(size, Image.Resampling.BOX)
        out = {"size": size, "scale": size[0] / float(raster.width), "raster_thumb": thumb, "raster_size": raster.size}
        out["raster_uri"] = self.uri(thumb)
        try:
            with Image.open(rec["file"]) as im:
                orig = ImageOps.exif_transpose(im).convert("RGB")
            osize = thumb_size(orig.width, orig.height, self.max_side)
            othumb = orig.resize(osize, Image.Resampling.BOX)
            out["orig_size"] = orig.size
            out["orig_same"] = othumb.size == thumb.size and othumb.tobytes() == thumb.tobytes()
            out["orig_uri"] = None if out["orig_same"] else self.uri(othumb)
        except OSError:
            out.update({"orig_size": None, "orig_same": False, "orig_uri": None})
        return out

    def persons_uri(self, pc: dict[str, Any], layers: Path, rec: dict[str, Any], chosen: int | None) -> str | None:
        inst = layers / "instances.ppm"
        if not inst.is_file():
            return None
        base = gray_base(pc["raster_thumb"], 0.75)
        with Image.open(inst) as im:
            colored = im.convert("RGB").resize(pc["size"], Image.Resampling.NEAREST)
        with Image.open(layers / "instances.pgm") as im:
            ids = im.convert("L").resize(pc["size"], Image.Resampling.NEAREST)
        img = Image.composite(colored, base, ids.point(lambda v: 150 if v > 0 else 0))
        draw = ImageDraw.Draw(img)
        s = pc["scale"]
        for p in rec.get("people_detail") or []:
            bb = p.get("bbox_xyxy")
            if isinstance(bb, list) and len(bb) == 4:
                width = 3 if p.get("index") == chosen else 1
                draw.rectangle([bb[0] * s, bb[1] * s, bb[2] * s - 1, bb[3] * s - 1], outline=(255, 255, 255), width=width)
                draw.text((bb[0] * s + 3, bb[1] * s + 2), str(p.get("index")), fill=(255, 255, 255))
        return self.uri(img)

    def region_uri(self, pc: dict[str, Any], layers: Path, all_people: bool) -> str | None:
        size = pc["size"]
        region = open_mask(layers / "region.pgm", size)
        person = open_mask(layers / "person.pgm", size)
        shown = region if region is not None else person
        if shown is None:
            return None
        img = Image.composite(pc["raster_thumb"], gray_base(pc["raster_thumb"], 0.35), shown)
        if region is not None and person is not None:
            # Persona fuera de la región (cabeza, manos, antebrazos...) en azul tenue: lo que quitó la geometría.
            outside = ImageChops.subtract(person, region).point(lambda v: int(v * 0.45))
            img = Image.composite(Image.new("RGB", size, (70, 90, 200)), img, outside)
        poses = sorted(layers.glob("pose_*.txt")) if all_people else []
        for pf in poses or [layers / "pose.txt"]:
            pose = read_pose(pf)
            if pose:
                draw_pose(img, pose, pc["scale"])
        return self.uri(img)

    def skin_uri(self, pc: dict[str, Any], layers: Path) -> str | None:
        size = pc["size"]
        removed = open_mask(layers / "skin_removed.pgm", size)
        face = open_mask(layers / "face_sample.pgm", size)
        if removed is None and face is None:
            return None
        base_mask = open_mask(layers / "region.pgm", size)
        if base_mask is None:
            base_mask = open_mask(layers / "person.pgm", size)
        img = gray_base(pc["raster_thumb"], 0.35)
        if base_mask is not None:
            img = Image.composite(pc["raster_thumb"], img, base_mask.point(lambda v: int(v * 0.8)))
        img = tint(img, face, (0, 230, 118), 0.75)
        img = tint(img, removed, (255, 0, 255), 0.9)
        return self.uri(img)

    def final_uri(self, pc: dict[str, Any], mask_path: Path | None) -> str | None:
        if mask_path is None:
            return None
        m = open_mask(mask_path, pc["size"])
        if m is None:
            return None
        return self.uri(Image.composite(pc["raster_thumb"], checker(pc["size"]), m))

    # --- capas de ce --debug-dir (resolución reducida) ---

    def debug_uri(self, dbg_dir: Path, name: str, gray: bool = False) -> str | None:
        p = dbg_dir / name
        if not p.is_file():
            return None
        with Image.open(p) as im:
            img = im.convert("L" if gray else "RGB")
        if max(img.size) > self.max_side:
            img = img.resize(thumb_size(img.width, img.height, self.max_side), Image.Resampling.NEAREST)
        return self.uri(img)

    def index_map_uri(self, dbg_dir: Path, pgm: str, ppm: str) -> str | None:
        """Mapa de clusters o de labels con los píxeles sin peso en cuadros (el negro puede ser un
        color real) y los descartados (254) en rayas rojas."""
        if not (dbg_dir / pgm).is_file() or not (dbg_dir / ppm).is_file():
            return None
        with Image.open(dbg_dir / ppm) as im:
            color = im.convert("RGB")
        with Image.open(dbg_dir / pgm) as im:
            idx = im.convert("L")
        none = idx.point(lambda v: 255 if v == 255 else 0)
        img = Image.composite(checker(color.size, 70, 100, 4), color, none)
        discarded = idx.point(lambda v: 255 if v == 254 else 0)
        if discarded.getbbox():
            stripes = Image.new("RGB", color.size, (255, 255, 255))
            draw = ImageDraw.Draw(stripes)
            for x in range(-color.size[1], color.size[0], 6):
                draw.line([(x, color.size[1]), (x + color.size[1], 0)], fill=(220, 30, 30), width=2)
            img = Image.composite(stripes, img, discarded)
        if max(img.size) > self.max_side:
            img = img.resize(thumb_size(img.width, img.height, self.max_side), Image.Resampling.NEAREST)
        return self.uri(img)

    def swatch_uri(self, dbg_dir: Path, k: int, rgb: list[int]) -> str | None:
        p = dbg_dir / f"swatch_{k}.pgm"
        if not p.is_file():
            return None
        with Image.open(p) as im:
            m = im.convert("L")
        m = m.resize(thumb_size(m.width, m.height, 96), Image.Resampling.NEAREST)
        return self.uri(Image.composite(Image.new("RGB", m.size, tuple(rgb)), checker(m.size, 70, 100, 4), m))

    # --- celdas de texto ---

    def palette_html(self, cell: dict[str, Any]) -> str:
        dbg = cell.get("debug") or {}
        dbg_dir = Path(cell["debug_dir"])
        rows = []
        for s in dbg.get("swatches") or []:
            thumb = self.swatch_uri(dbg_dir, int(s["index"]), s["rgb"])
            rows.append(f'<div class="sw">{img_tag(thumb, "píxeles del swatch", True) if thumb else ""}<div>{chip(s["hex"], True)}'
                        f'<b>s{int(s["index"])} · {100 * float(s["weight"]):.1f} %</b><br><code>{esc(s["hex"])}</code> · {int(s.get("pixels", 0))} px</div></div>')
        return "".join(rows) + '<div class="cap">Miniatura = píxeles de la imagen reducida que alimentan cada swatch.</div>'

    def clusters_html(self, cell: dict[str, Any]) -> str:
        pd = (cell.get("debug") or {}).get("palette_debug") or {}
        ctab = ['<table class="mini"><tr><th>cluster</th><th>peso</th><th>destino</th></tr>']
        for c in pd.get("clusters") or []:
            fate = int(c.get("fate", -1))
            dest = FATES.get(fate, str(fate))
            if fate == 0:
                dest += f" → s{c.get('final_index')}"
            elif fate == 1:
                dest += f" en c{c.get('group_head')}" + (f" → s{c.get('final_index')}" if c.get("final_index") is not None else "")
            ctab.append(f'<tr><td>{chip(c.get("hex"))}c{c.get("index")}</td><td>{100 * float(c.get("weight", 0)):.1f} %</td><td>{esc(dest)}</td></tr>')
        ctab.append("</table>")
        return "".join(ctab)

    def color_name(self, idx: int) -> tuple[str, str]:
        c = self.colors[idx]
        return c["hex"], c["name"]

    def hits_html(self, cell: dict[str, Any]) -> str:
        dbg = cell.get("debug") or {}
        explain = dbg.get("explain") or []
        result = cell.get("result") or {}
        if not explain:
            return '<div class="na">sin explicación</div>'
        sw = dbg.get("swatches") or []
        head = ""
        if len(explain) >= 2:
            gap = float(explain[1]["score"]) - float(explain[0]["score"])
            head = (f'<div class="cap"><b>Gana por {gap:.2f}</b> puntos de score'
                    + (" (ambiguo: &lt; 1)" if result.get("ambiguous") == 1 else "") + ' (menor es mejor).</div>')
        parts = [head]
        for e in explain:
            cid = int(e["id"])
            colors = "".join(chip(self.color_name(i)[0]) for i in self.combos.get(cid, []))
            illum = ILLUMINANTS_ES.get(str(e.get("illuminant_name")), str(e.get("illuminant_name")))
            hyp = "" if float(e["hypothesis_penalty"]) == 0 else f' · {float(e["exposure_ev"]):+.1f} EV, {esc(illum)}'
            per_color = []
            for pc in e.get("per_color") or []:
                ns = int(pc["nearest_swatch"])
                swhex = sw[ns]["hex"] if 0 <= ns < len(sw) else None
                per_color.append(f'<div class="pc">{chip(pc.get("hex"))}{esc(pc.get("name", ""))} → {chip(swhex)}s{ns} · ΔE {float(pc["de"]):.1f}</div>')
            per_sw = []
            for ps_ in e.get("per_swatch") or []:
                k = int(ps_["swatch"])
                swhex = sw[k]["hex"] if 0 <= k < len(sw) else None
                w = float(sw[k]["weight"]) if 0 <= k < len(sw) else 0.0
                per_sw.append(f'<div class="pc">{chip(swhex)}s{k} ({100 * w:.0f} %) → {chip(ps_.get("nearest_color_hex"))}ΔE {float(ps_["de"]):.1f}</div>')
            parts.append(
                f'<div class="hit"><b>{e["rank"]}. {esc(combo_label(cid, self.names))}</b> {colors}<br>'
                f'<b>{float(e["score"]):.2f}</b> = ajuste {float(e["fit_term"]):.2f} + cobertura {float(e["coverage_term"]):.2f}'
                f' + hipótesis {float(e["hypothesis_penalty"]):.1f}<span class="muted">{hyp}</span>'
                f'{"".join(per_color)}'
                f'<details><summary class="muted">cada swatch → su color más cercano</summary>{"".join(per_sw)}</details></div>')
        parts.append('<div class="cap">Ajuste = Σ peso·ΔE00 de cada swatch a su color más cercano de la combinación; cobertura = λ·media '
                     'del ΔE00 de cada color a su swatch más cercano; hipótesis = penalización por suponer otra exposición o iluminante.</div>')
        return "".join(parts)

    def steps_html(self, steps: list[str]) -> str:
        return "".join(f'<span class="step">{esc(s)}</span>' for s in steps) or '<span class="step">persona completa</span>'


def render_html(records: list[dict[str, Any]], args: argparse.Namespace, renderer: Renderer, expected: dict[str, dict[str, Any]],
                variants: list[str], meta: dict[str, Any]) -> tuple[str, list[dict[str, Any]]]:
    body: list[str] = []
    summary_rows: list[str] = []
    json_rows: list[dict[str, Any]] = []
    official = l4v.OFFICIAL_VARIANT
    for pi, rec in enumerate(records):
        anchor = f"p{pi:02d}"
        exp = expected.get(rec["name"], {})
        garments = list(((exp.get("largest_person") or {}).get("garments")) or [])
        jrow: dict[str, Any] = {"file": rec["file"], "raster": rec.get("raster"), "people": rec.get("people"), "work": rec["work"], "variants": {}}
        json_rows.append(jrow)
        if "error" in rec:
            body.append(f'<section class="card" id="{anchor}"><h2>{esc(rec["name"])}</h2><p class="err">{esc(rec["error"])}</p></section>')
            summary_rows.append(f'<tr><td><a href="#{anchor}">{esc(rec["name"])}</a></td><td colspan="{len(variants) + 1}" class="err">{esc(rec["error"])}</td></tr>')
            jrow["error"] = rec["error"]
            continue
        pc = renderer.photo_cells(rec)
        head = ("<tr><th>variante</th><th>Foto</th><th>Raster del motor</th><th>Reducida (motor)</th><th>Personas (Vision)</th>"
                "<th>Pose y región de ropa</th><th>Piel quitada</th><th>Máscara final</th><th>Peso por píxel</th><th>Clusters (Lloyd)</th>"
                "<th>Label map</th><th>Paleta</th><th>Top-3 y por qué</th></tr>")
        rows_html: list[str] = []
        first_masked = next((v for v in variants if v != "none"), None)
        n_masked = sum(1 for v in variants if v != "none")
        sum_cells: list[str] = []
        people_txt = "—" if rec.get("people") is None else str(rec["people"])
        if exp.get("people") is not None:
            people_txt += f" (anotadas {exp['people']})"
        for vi, v in enumerate(variants):
            cell = rec["variants"].get(v, {})
            vm = cell.get("vm") or {}
            steps = list(vm.get("steps") or [])
            exp_de = garment_de(cell.get("result"), garments) if garments else None
            hs = hints(v, cell, exp_de) if not cell.get("skipped") else []
            jrow["variants"][v] = {"mask": cell.get("mask"), "steps": steps, "coverage": vm.get("mask_coverage"), "debug_dir": cell.get("debug_dir"),
                                   "layers_dir": cell.get("layers_dir"), "skipped": cell.get("skipped"), "error": cell.get("error"),
                                   "swatches": [[s["hex"], round(float(s["weight"]), 4)] for s in (cell.get("result") or {}).get("swatches", [])],
                                   "top": [int(h["id"]) for h in (cell.get("result") or {}).get("hits", [])],
                                   "ambiguous": (cell.get("result") or {}).get("ambiguous"), "dominant_vs_expected_de00": exp_de, "hints": hs}
            label = f'<b>{esc(v)}</b>{"<span class=badge>app</span>" if v == official else ""}<div class="muted">{esc(l4v.VARIANT_LABELS.get(v, v))}</div>'
            tr_class = ' class="official"' if v == official else ""
            cells: list[str] = []
            # Columnas comunes (rowspan): foto, raster, reducida.
            if vi == 0:
                span = f' rowspan="{len(variants)}"'
                osz = pc.get("orig_size")
                orig = (img_tag(pc["orig_uri"], "foto") if pc["orig_uri"] else img_tag(pc["raster_uri"], "foto")) + \
                    f'<div class="cap">{esc(rec["name"])}' + (f" · {osz[0]}×{osz[1]}" if osz else "") + "</div>"
                rs = pc["raster_size"]
                raster = (img_tag(pc["raster_uri"], "raster") if pc["orig_uri"] else '<div class="na">idéntico a la foto a este tamaño</div>') + \
                    f'<div class="cap">{rs[0]}×{rs[1]} px · {esc(rec.get("raster_source", ""))}' + \
                    (f' · orientación EXIF {rec["orientation"]} ignorada (como la app)' if rec.get("orientation") not in (None, 1) else "") + "</div>"
                none_dbg = next((rec["variants"][x] for x in variants if (rec["variants"].get(x) or {}).get("debug")), None)
                reduced = '<div class="na">sin análisis</div>'
                if none_dbg:
                    d = none_dbg["debug"]
                    reduced = img_tag(renderer.debug_uri(Path(none_dbg["debug_dir"]), "reduced.ppm"), "reducida", True) + \
                        f'<div class="cap">{d.get("reduced_width")}×{d.get("reduced_height")} px: lo que agrupa el motor (promedio de bloque)</div>'
                cells += [f"<td{span}>{orig}</td>", f"<td{span}>{raster}</td>", f"<td{span}>{reduced}</td>"]
            if v == "none":
                cells += ['<td class="na">sin recorte: no usa personas</td>', '<td class="na">—</td>', '<td class="na">—</td>',
                          '<td class="na">sin máscara: todos los píxeles, con peso al centro</td>']
            elif cell.get("skipped") or cell.get("error"):
                msg = cell.get("skipped") or cell.get("error")
                if v == first_masked:
                    cells.append(f'<td rowspan="{n_masked}" class="na">{esc(msg)}</td>')
                cells += [f'<td class="{"na" if cell.get("skipped") else "err"}" colspan="3">{esc(msg)}</td>']
            else:
                layers = Path(cell["layers_dir"]) if cell.get("layers_dir") else None
                if v == first_masked:
                    chosen = vm.get("chosen_index")
                    puri = renderer.persons_uri(pc, layers, rec, chosen) if layers else None
                    vis = rec.get("vision") or {}
                    cap = f"{people_txt} personas; recuadro grueso = la más grande (índice 0)"
                    if vis.get("unassigned_poses") or vis.get("unassigned_faces"):
                        cap += f"; poses sin persona {vis.get('unassigned_poses', 0)}, caras sin persona {vis.get('unassigned_faces', 0)}"
                    if (rec.get("people") or 0) >= 4:
                        cap += "; Vision devuelve como mucho 4 instancias"
                    cells.append(f'<td rowspan="{n_masked}">{img_tag(puri, "personas")}<div class="cap">{esc(cap)}</div></td>')
                persons = vm.get("persons") or []
                p0 = persons[0] if persons else {}
                if layers and (layers / "region.pgm").is_file():
                    rcap = f"región de ropa: {p0.get('region_pixels', '—')} px de {p0.get('person_pixels', '—')} de la persona · " + \
                        ("pose (amarillo), puntos < 0,3 de confianza huecos" if "poseRegions" in steps else "corte de cabeza (sin pose)")
                elif layers:
                    rcap = "persona completa (sin recorte de ropa); esqueleto de la pose si existe"
                else:
                    rcap = ""
                cells.append(f"<td>{img_tag(renderer.region_uri(pc, layers, v.startswith('allPeople')) if layers else None, 'región')}<div class=\"cap\">{esc(rcap)}</div></td>")
                if v.endswith("-skin") or "skin" in v.split("-"):
                    skin_img = renderer.skin_uri(pc, layers) if layers else None
                    model = p0.get("skin_model") or {}
                    scap = (f"magenta = piel quitada ({p0.get('skin_removed_pixels', 0)} px); verde = muestra de cara ({p0.get('face_sample_pixels') or 0} px)"
                            + (f"; modelo n={model.get('n')}" if model else "") + ("; salvaguarda activada: no se quitó" if "skinGuard" in steps else "")
                            + (f"; {p0['skin_note']}" if p0.get("skin_note") else ""))
                    cells.append(f"<td>{img_tag(skin_img, 'piel') if skin_img else '<div class=na>sin muestra de cara ni piel quitada</div>'}<div class=\"cap\">{esc(scap)}</div></td>")
                else:
                    cells.append('<td class="na">sin piel adaptativa en esta variante</td>')
                fmask = Path(cell["mask"]) if cell.get("mask") else None
                cov = vm.get("mask_coverage")
                fcap = (f"cobertura {100 * float(cov):.1f} % del raster (cuadros = fuera)" if fmask and isinstance(cov, (int, float))
                        else "sin máscara: la app analiza la foto completa")
                cells.append(f"<td>{img_tag(renderer.final_uri(pc, fmask), 'máscara final') if fmask else '<div class=na>sin máscara</div>'}<div class=\"cap\">{esc(fcap)}</div></td>")
            # Capas del motor.
            if cell.get("debug"):
                d = cell["debug"]
                dd = Path(cell["debug_dir"])
                pdg = d.get("palette_debug") or {}
                lc = d.get("label_counts") or {}
                npx = max(1, int(d.get("reduced_width", 1)) * int(d.get("reduced_height", 1)))
                cells.append(f'<td>{img_tag(renderer.debug_uri(dd, "weights.pgm", gray=True), "peso", True)}<div class="cap">blanco = peso máximo, negro = 0 · '
                             f'{100 * float(pdg.get("zero_weight_fraction", 0)):.0f} % de píxeles sin peso · σ centro {float(pdg.get("center_sigma_px", 0)):.0f} px</div></td>')
                cells.append(f'<td>{img_tag(renderer.index_map_uri(dd, "clusters.pgm", "clusters.ppm"), "clusters", True)}<div class="cap">{pdg.get("n_clusters")} clusters de Lloyd antes de fusionar '
                             f'({pdg.get("lloyd_iterations")} iteraciones); cuadros = sin peso</div>{renderer.clusters_html(cell)}</td>')
                cells.append(f'<td>{img_tag(renderer.index_map_uri(dd, "labels.pgm", "labels.ppm"), "label map", True)}<div class="cap">color del swatch al que va cada píxel; cuadros = sin peso '
                             f'({100 * int(lc.get("none", 0)) / npx:.0f} %), rayas rojas = cluster descartado o recortado ({100 * int(lc.get("discarded", 0)) / npx:.0f} %)</div></td>')
                cells.append(f"<td>{renderer.palette_html(cell)}</td>")
                cells.append(f"<td class=\"why\">{renderer.hits_html(cell)}</td>")
            elif cell.get("error") and not cell.get("vm"):
                cells.append(f'<td colspan="5" class="err">{esc(cell["error"])}</td>')
            elif cell.get("error"):
                cells.append(f'<td colspan="5" class="err">{esc(cell["error"])}</td>')
            else:
                cells.append('<td colspan="5" class="na">sin análisis del motor</td>')
            vcell = label + (f'<div>{renderer.steps_html(steps)}</div>' if v != "none" and vm else "")
            if hs:
                vcell += '<ul class="hints">' + "".join(f"<li>{esc(h)}</li>" for h in hs) + "</ul>"
            rows_html.append(f"<tr{tr_class}><td class=\"variant\">{vcell}</td>{''.join(cells)}</tr>")
            # Resumen
            res = cell.get("result") or {}
            dom = dominant(res)
            if cell.get("skipped") or cell.get("error"):
                sum_cells.append(f'<td class="{"off" if v == official else ""}"><span class="na">{esc(cell.get("skipped") or cell.get("error"))}</span></td>')
            else:
                top = (res.get("hits") or [{}])[0]
                cov = vm.get("mask_coverage")
                txt = (" → ".join(steps) if steps else ("—" if v == "none" else "persona completa"))
                if v != "none":
                    txt += f" · {100 * float(cov):.1f} %" if cell.get("mask") and isinstance(cov, (int, float)) else " · sin máscara"
                s = f'{esc(txt)}<br>{chip(dom["hex"] if dom else None, True)}{100 * float(dom["weight"]):.0f} % · ' if dom else f"{esc(txt)}<br>"
                s += f'<b>{esc(combo_label(int(top["id"]), renderer.names)) if top.get("id") else "—"}</b>'
                if exp_de is not None:
                    s += f"<br>ΔE00 dominante→ropa {exp_de:.1f}"
                if hs:
                    s += f'<br><span class="muted">{len(hs)} aviso{"s" if len(hs) != 1 else ""}</span>'
                sum_cells.append(f'<td class="{"off" if v == official else ""}">{s}</td>')
        ex = ""
        if garments:
            ex = "<p>Ropa anotada de la persona más grande: " + "; ".join(f"{chip(g.get('color_hex'))}{esc(g.get('part'))} <code>{esc(g.get('color_hex'))}</code> {esc(g.get('name', ''))}" for g in garments) + "</p>"
        cmds = "\n".join(rec["commands"])
        body.append(
            f'<section class="card" id="{anchor}"><h2>{esc(rec["name"])}</h2>'
            f'<p class="muted">Personas detectadas por Vision: {esc(people_txt)} · raster {pc["raster_size"][0]}×{pc["raster_size"][1]} · trabajo: <code>{esc(rec["work"])}</code></p>{ex}'
            f'<div class="scroll"><table class="layers"><thead>{head}</thead><tbody>{"".join(rows_html)}</tbody></table></div>'
            f'<details><summary>Reproducir estas capas desde la terminal</summary><pre>{esc(cmds)}</pre></details></section>')
        thumb_uri = renderer.uri(pc["raster_thumb"].resize(thumb_size(*pc["size"], 96), Image.Resampling.BOX))
        summary_rows.append(f'<tr><td><a href="#{anchor}"><img src="{thumb_uri}" alt=""></a><a href="#{anchor}">{esc(rec["name"])}</a></td>'
                            f'<td>{esc(people_txt)}</td>{"".join(sum_cells)}</tr>')
    vhead = "".join(f'<th>{esc(v)}{"<span class=badge>app</span>" if v == official else ""}</th>' for v in variants)
    legend = """
<ol>
<li><b>Foto</b> y <b>raster del motor</b>: los píxeles sRGB que recibe el motor (lado ≤ 1024, como en la app).</li>
<li><b>Reducida</b>: el motor promedia bloques hasta ≤ 256 px; sobre esa imagen agrupa colores.</li>
<li><b>Personas</b>: instancias de Vision (color por persona; recuadro grueso = la más grande, que es la que usa la app).</li>
<li><b>Pose y región de ropa</b>: esqueleto de Vision y región de torso, brazos y piernas que calcula el motor (sin cabeza, manos ni antebrazos); sin pose, corte de cabeza.</li>
<li><b>Piel quitada</b>: modelo de piel muestreado de la cara (verde); en magenta lo que se excluye de la ropa.</li>
<li><b>Máscara final</b>: lo que entra en el análisis (cuadros = fuera).</li>
<li><b>Peso por píxel</b>: máscara × peso gaussiano al centro.</li>
<li><b>Clusters (Lloyd)</b>: grupos de color antes de fusionar; su tabla dice si cada uno se conservó, se fusionó, se descartó (&lt; 5 %) o se recortó (máx. 5 colores).</li>
<li><b>Label map</b>: a qué color de la paleta alimenta cada píxel.</li>
<li><b>Paleta</b>: swatches con su peso y los píxeles que los forman.</li>
<li><b>Top-3 y por qué</b>: score = ajuste + cobertura + hipótesis de exposición/iluminante; para cada color de la combinación, su swatch más cercano y el ΔE00.</li>
</ol>"""
    total = meta["seconds"]
    doc = f"""<title>Capas del color · colorsApp</title>
<meta charset="utf-8">
<style>{CSS}</style>
<main>
<h1>Capas del color</h1>
<p class="muted">Generado {esc(meta["generated_at"])} · motor {esc(meta.get("engine") or "?")} · diccionario {esc(meta.get("dict_version") or "?")} ·
visionmask {esc(meta.get("visionmask") or "no disponible: " + meta.get("visionmask_reason", ""))} · {len(records)} fotos · {total} s.</p>
<p>Cada fila es una <b>variante de recorte</b> y cada columna una <b>capa</b> del pipeline, en orden: si el color sale mal, busca la primera columna donde la imagen deja de parecerse a lo que esperas.
La variante marcada <span class="badge">app</span> es la que usa la app por defecto ({esc(official)}). Las listas naranjas son avisos automáticos, no diagnósticos.</p>
<details><summary>Cómo leer las columnas</summary>{legend}</details>
<section class="card"><h2>Resumen</h2>
<p class="muted">Por variante: pasos de la cadena · cobertura de la máscara · color dominante y su peso · combinación ganadora{" · ΔE00 del dominante frente a la ropa anotada (expected.json)" if expected else ""}.</p>
<div class="scroll"><table class="summary"><thead><tr><th>foto</th><th>personas</th>{vhead}</tr></thead><tbody>{"".join(summary_rows)}</tbody></table></div>
</section>
{"".join(body)}
<p class="muted">Ficheros intermedios y comandos: <code>{esc(meta["out"])}/work/</code>. Resumen en <code>layers.json</code>. {renderer.images} imágenes PNG embebidas (≤ {renderer.max_side} px).</p>
</main>
"""
    return doc, json_rows


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("images", nargs="*", help="fotos, directorios o globs (con ~)")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--ce", type=str, default=None, help="CLI ce con --debug-dir (defecto build/tools/ce o $COLORSAPP_CE_CLI)")
    ap.add_argument("--visionmask", type=str, default=None)
    ap.add_argument("--no-visionmask", action="store_true")
    ap.add_argument("--build-visionmask", action="store_true")
    ap.add_argument("--variants", type=str, default=",".join(DEFAULT_VARIANTS))
    ap.add_argument("--max-side", type=int, default=256)
    ap.add_argument("--expected", type=Path, default=None)
    ap.add_argument("--top", type=int, default=3)
    args = ap.parse_args(argv)
    images = collect_images(args.images)
    if not images:
        print("layers-report: no hay fotos (PNG/JPEG/HEIC) en " + " ".join(args.images or ["(nada)"]), file=sys.stderr)
        return 2
    cli = find_cli_optional(args.ce)
    if args.ce and (cli is None or cli != Path(args.ce)):
        cli = None  # --ce explícito que no existe: no se sustituye por otro CLI
    if not has_debug_dir(cli):
        print(f"layers-report: {cli or 'ce'} no existe o no tiene --debug-dir (make build)", file=sys.stderr)
        return 2
    variants = [v.strip() for v in args.variants.split(",") if v.strip()]
    if any(not l4v.VARIANT_RE.match(v) for v in variants) or not variants:
        print(f"layers-report: variantes inválidas: {args.variants}", file=sys.stderr)
        return 2
    variants = ["none"] + [v for v in variants if v != "none"]
    vm: Path | None = None
    vm_reason = "--no-visionmask"
    if not args.no_visionmask:
        vm, vm_reason = l4v.ensure_visionmask(args.visionmask, args.build_visionmask)
        if vm is None:
            print(f"layers-report: AVISO: {vm_reason}; solo la variante none", file=sys.stderr)
    started = time.perf_counter()
    out: Path = args.out.expanduser()
    out.mkdir(parents=True, exist_ok=True)
    combos, colors, names = load_dictionary()
    expected = load_expected(args.expected, images)
    records = []
    for i, img in enumerate(images):
        print(f"[{i + 1}/{len(images)}] {img.name}", flush=True)
        records.append(analyze_photo(i, img, cli=cli, visionmask=vm, vm_reason=vm_reason, variants=variants, work_root=out / "work", top=args.top))
    analyzed = [r for r in records if any((c or {}).get("debug") for c in r.get("variants", {}).values())]
    first = next((c["result"] for r in analyzed for c in r["variants"].values() if c.get("result")), {})
    meta = {"generated_at": time.strftime("%Y-%m-%d %H:%M"), "engine": first.get("engine"), "dict_version": first.get("dict_version"),
            "visionmask": str(vm) if vm else None, "visionmask_reason": vm_reason, "out": str(out),
            "seconds": round(time.perf_counter() - started, 1)}
    renderer = Renderer(args.max_side, combos, colors, names)
    page, rows = render_html(records, args, renderer, expected, variants, meta)
    (out / "index.html").write_text(page, encoding="utf-8")
    (out / "layers.json").write_text(json.dumps({"meta": meta, "variants": variants, "photos": rows}, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    size = (out / "index.html").stat().st_size
    print(f"layers-report: {out / 'index.html'} ({size / 1e6:.1f} MB, {renderer.images} imágenes, {len(analyzed)}/{len(records)} fotos analizadas, "
          f"{round(time.perf_counter() - started, 1)} s)")
    if size > SIZE_WARN_BYTES:
        print(f"layers-report: AVISO: el HTML pesa {size / 1e6:.0f} MB; usa menos fotos o --max-side menor", file=sys.stderr)
    return 0 if analyzed else 1


if __name__ == "__main__":
    sys.exit(main())
