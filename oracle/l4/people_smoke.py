"""Smoke test de recorte con personas (``make l4-people-smoke``): sin set dorado todavía.

    uv run --project oracle python -m l4.people_smoke --cli build-seg/tools/ce [--visionmask PATH]
        [--build-visionmask] [--people-dir harness/people] [--out harness/out] [--variants LISTA]

Usa ``harness/people/*.png`` (8 fotos CC0 con varias personas) y ``expected.json`` como manifest
**informativo**: no hay combinación verdadera, así que no hay recall. Por foto y variante
(``none``, ``allPeople``, ``largest``, ``largest-clothing``, ``largest-clothing-skin``):

1. ``visionmask`` escribe el raster exacto de la app (``<foto>.ppm``, CoreGraphics sRGB, <= 1024
   px) y la máscara de cada variante; ``ce batch`` analiza todas las líneas ``"ppm" ["pgm"]`` en
   una sola invocación (``none`` sin máscara, sobre el mismo raster).
2. Frente a las prendas anotadas de la persona más grande (``largest_person.garments[].color_hex``,
   parches medidos a mano: guía aproximada, no verdad de color) se mide con el ΔE00 del oráculo
   (colour, ``oracle.reference``) sobre el Lab del motor:
   - ``de_dominant``: ΔE00 entre el swatch dominante (mayor peso) y la prenda anotada más cercana;
   - ``de_garments``: media, sobre las prendas, del ΔE00 al swatch más cercano (¿aparece cada
     prenda en la paleta?);
   - ``garment_weight``: peso de la paleta en swatches a ΔE00 <= 10 de alguna prenda (cuánto de
     la paleta es la ropa anotada y no fondo o piel).
3. Por variante: mediana y p90 (percentil lineal de numpy) de ``de_dominant``, mediana de
   ``de_garments`` y ``garment_weight``, fotos con persona detectada y con máscara, pasos más
   frecuentes y el delta de la mediana frente a ``none``.

4. **Prendas** (``ce batch --garments``, CONTEXT §13): para cada variante con máscara y pose
   (``visionmask --layers`` escribe ``pose.txt``), el mapa de regiones de ``ce garment-regions``
   (silueta corporal de la pose) y la paleta por prenda: colores por región (1 arriba, 2 abajo,
   3 prenda entera), ``de_garment_region`` (media, sobre las prendas anotadas, del ΔE00 al swatch
   de prenda de su región: torso -> arriba o entera, piernas -> abajo o entera) y el top-1 por
   ese camino. Sin pose la variante usa una sola región (``none``).

Escribe ``<out>/l4_people_smoke.json`` y ``.md``. Es el único número disponible hoy para saber si
el recorte ayuda; con 8 fotos y colores anotados a mano solo sirve para detectar regresiones
gruesas. Exit: 0 ok (también con variantes ``skipped`` si no hay visionmask); 1 error de
visionmask o de ``ce batch``; 2 uso.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Any

import numpy as np

from l4 import variants as l4v
from oracle import l3
from oracle import reference as ref
from oracle.l2 import find_cli_optional

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PEOPLE = REPO_ROOT / "harness" / "people"
DEFAULT_OUT = REPO_ROOT / "harness" / "out"
GARMENT_DE = 10.0
PHOTO_SUFFIXES = (".png", ".jpg", ".jpeg")


def sc_read_ppm_shape(path: Path) -> tuple[int, int]:
    """(alto, ancho) de un PPM P6 leyendo solo la cabecera."""
    from synth import compose as sc

    return sc.read_ppm(path).shape[:2]


def hex_to_lab(hex_color: str) -> np.ndarray:
    s = hex_color.strip().lstrip("#")
    rgb = [int(s[i:i + 2], 16) for i in (0, 2, 4)]
    return np.asarray(ref.srgb8_to_lab_strict(rgb), dtype=float)


def de00(a: np.ndarray, b: np.ndarray) -> float:
    return float(ref.de2000(np.asarray(a, dtype=float), np.asarray(b, dtype=float)))


def photo_metrics(result: dict[str, Any], garments: list[dict[str, Any]]) -> dict[str, Any]:
    """ΔE00 del resultado de ``ce`` frente a las prendas anotadas (sin prendas: solo el dominante)."""
    swatches = result.get("swatches") if isinstance(result.get("swatches"), list) else []
    if not swatches:
        return {"error": result.get("error") or "sin swatches"}
    dom = max(swatches, key=lambda s: float(s["weight"]))
    out: dict[str, Any] = {"dominant_hex": dom.get("hex"), "dominant_weight": float(dom["weight"]),
                           "top": l3.ranked_ids(result), "ambiguous": result.get("ambiguous"),
                           "swatches": [[s.get("hex"), round(float(s["weight"]), 4)] for s in swatches]}
    labs = [hex_to_lab(g["color_hex"]) for g in garments if isinstance(g.get("color_hex"), str)]
    if not labs:
        out.update({"de_dominant": None, "de_first": None, "de_garments": None, "garment_weight": None})
        return out
    dom_lab = np.asarray(dom["lab"], dtype=float)
    out["de_first"] = de00(dom_lab, labs[0])
    out["de_dominant"] = min(de00(dom_lab, g) for g in labs)
    sw_labs = [np.asarray(s["lab"], dtype=float) for s in swatches]
    out["de_garments"] = float(np.mean([min(de00(g, s) for s in sw_labs) for g in labs]))
    out["garment_weight"] = float(sum(float(s["weight"]) for s, lab in zip(swatches, sw_labs)
                                      if min(de00(lab, g) for g in labs) <= GARMENT_DE))
    return out


#: Región de prenda que corresponde a cada parte anotada en expected.json (3 = prenda entera vale siempre).
PART_REGIONS: dict[str, tuple[int, ...]] = {"torso": (1, 3), "legs": (2, 3), "full": (1, 2, 3)}


def garment_metrics(result: dict[str, Any], garments: list[dict[str, Any]]) -> dict[str, Any]:
    """Colores por región y ΔE00 de cada prenda anotada al swatch de prenda de su región."""
    gs = result.get("garments") if isinstance(result.get("garments"), list) else []
    if not gs:
        return {"garments_error": result.get("error") or "sin swatches de prenda"}
    counts: Counter = Counter(int(g["region"]) for g in gs)
    out: dict[str, Any] = {
        "garment_swatches": [[g.get("hex"), int(g["region"]), round(float(g["weight"]), 4), int(g["n_merged_clusters"])]
                             for g in gs],
        "garment_counts": {str(k): v for k, v in sorted(counts.items())},
        "garment_max_per_region": max(counts.values()),
        "garment_top": l3.ranked_ids(result),
        "garment_regions": bool(result.get("regions")),
    }
    des = []
    for g in garments:
        if not isinstance(g.get("color_hex"), str):
            continue
        allowed = PART_REGIONS.get(str(g.get("part")), (0, 1, 2, 3))
        pool = [s for s in gs if int(s["region"]) in allowed or int(s["region"]) == 0] or gs
        des.append(min(de00(hex_to_lab(g["color_hex"]), np.asarray(s["lab"], dtype=float)) for s in pool))
    out["de_garment_region"] = float(np.mean(des)) if des else None
    return out


def _stat(values: list[float], q: float | None = None) -> float | None:
    if not values:
        return None
    return float(np.percentile(values, q)) if q is not None else float(np.median(values))


def aggregate(variants: list[str], rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Resumen por variante a partir de las filas por foto (``rows[i]["variants"][v]``)."""
    out: dict[str, Any] = {}
    for v in variants:
        cells = [r["variants"].get(v) or {} for r in rows]
        done = [c for c in cells if c.get("status") == "ok" and "error" not in c]
        de_dom = [c["de_dominant"] for c in done if c.get("de_dominant") is not None]
        de_g = [c["de_garments"] for c in done if c.get("de_garments") is not None]
        gw = [c["garment_weight"] for c in done if c.get("garment_weight") is not None]
        steps: Counter = Counter()
        for c in done:
            for s in dict.fromkeys(c.get("steps") or []):
                steps[s] += 1
        top1 = Counter(c["top"][0] for c in done if c.get("top"))
        entry = {
            "variant": v, "official": v == l4v.OFFICIAL_VARIANT, "label": l4v.VARIANT_LABELS.get(v, v),
            "n": len(done), "n_photos": len(rows),
            "skipped": sum(1 for c in cells if c.get("status") == "skipped"),
            "errors": sum(1 for c in cells if c.get("status") == "error" or "error" in c),
            "de_dominant_median": _stat(de_dom), "de_dominant_p90": _stat(de_dom, 90),
            "de_dominant_mean": float(np.mean(de_dom)) if de_dom else None,
            "de_garments_median": _stat(de_g), "garment_weight_median": _stat(gw),
            "person_detected": sum(1 for c in done if c.get("people")) if v != "none" else None,
            "with_mask": sum(1 for c in done if c.get("mask")) if v != "none" else None,
            "top_steps": [[s, n] for s, n in sorted(steps.items(), key=lambda kv: (-kv[1], kv[0]))[:4]],
            "distinct_top1": len(top1),
        }
        gdone = [c for c in done if c.get("garment_swatches")]
        entry["garments_n"] = len(gdone)
        entry["garments_with_regions"] = sum(1 for c in gdone if c.get("garment_regions"))
        entry["garment_swatches_median"] = _stat([float(len(c["garment_swatches"])) for c in gdone])
        entry["garment_max_per_region_max"] = max((int(c["garment_max_per_region"]) for c in gdone), default=None)
        entry["de_garment_region_median"] = _stat([c["de_garment_region"] for c in gdone if c.get("de_garment_region") is not None])
        entry["palette_swatches_median"] = _stat([float(len(c["swatches"])) for c in done if c.get("swatches")])
        out[v] = entry
    base = out.get("none", {})
    for v, e in out.items():
        for key in ("de_dominant_median", "de_dominant_p90", "de_garments_median", "garment_weight_median"):
            e[f"delta_{key}"] = (e[key] - base[key]) if v != "none" and e.get(key) is not None and base.get(key) is not None else None
    return out


def _f(x: float | None, digits: int = 1) -> str:
    return "—" if x is None else f"{x:.{digits}f}"


def _d(x: float | None, digits: int = 1) -> str:
    return "—" if x is None else f"{x:+.{digits}f}"


def render_markdown(doc: dict[str, Any]) -> str:
    variants = doc["variants"]
    agg = doc["aggregate"]
    lines = [
        "# L4 people-smoke: recorte con personas sin set dorado",
        "",
        f"Generado por `make l4-people-smoke` ({doc['generated_at']}). Motor {doc.get('engine') or '?'}, diccionario "
        f"{doc.get('dict_version') or '?'}, visionmask `{doc.get('visionmask') or '—'}`, {len(doc['photos'])} fotos de "
        f"`{doc['people_dir']}`.",
        "",
        "> **Informativo, no es la capa 4.** No hay combinación verdadera para estas fotos: no hay recall. Es el **único "
        "número disponible hoy** para saber si el recorte ayuda: ΔE00 entre la paleta del motor y los colores de ropa "
        "anotados a mano (`expected.json`, persona más grande; parches medidos a ojo, guía aproximada y no verdad de color). "
        "Con 8 fotos solo detecta regresiones gruesas. La decisión de la variante por defecto se toma con el set dorado "
        "(`make l4-variants` / `make eval` con `COLORSAPP_GOLDEN_DIR`).",
        "",
        "- **ΔE00 dominante**: swatch de mayor peso frente a la prenda anotada más cercana (mediana y p90; menor es mejor).",
        "- **ΔE00 prendas→paleta**: media por foto del ΔE00 de cada prenda a su swatch más cercano (¿aparece la ropa en la paleta?).",
        f"- **peso ropa**: fracción de la paleta en swatches a ΔE00 <= {GARMENT_DE:.0f} de alguna prenda (mayor es mejor: menos fondo y piel).",
        f"- Δ = diferencia frente a `none` (foto completa). Variante oficial de la app: **{l4v.OFFICIAL_VARIANT}**.",
        "",
        "## Por variante",
        "",
        "| variante | fotos | ΔE00 dominante mediana | p90 | Δ mediana vs none | ΔE00 prendas→paleta mediana | Δ | peso ropa mediana | Δ | persona detectada | con máscara | pasos más frecuentes | top-1 distintos |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for v in variants:
        e = agg[v]
        label = f"**{v} (oficial)**" if e["official"] else v
        if not e["n"]:
            lines.append(f"| {label} | 0/{e['n_photos']} (skipped {e['skipped']}, errores {e['errors']}) | — | — | — | — | — | — | — | — | — | — | — |")
            continue
        is_none = v == "none"
        cells = [label, f"{e['n']}/{e['n_photos']}", _f(e["de_dominant_median"]), _f(e["de_dominant_p90"]),
                 "—" if is_none else _d(e["delta_de_dominant_median"]), _f(e["de_garments_median"]),
                 "—" if is_none else _d(e["delta_de_garments_median"]),
                 _f(None if e["garment_weight_median"] is None else 100 * e["garment_weight_median"], 0) + (" %" if e["garment_weight_median"] is not None else ""),
                 "—" if is_none or e["delta_garment_weight_median"] is None else f"{100 * e['delta_garment_weight_median']:+.0f} pts",
                 "—" if is_none else f"{e['person_detected']}/{e['n']}", "—" if is_none else f"{e['with_mask']}/{e['n']}",
                 "—" if is_none else (", ".join(f"{s} {n}" for s, n in e["top_steps"]) or "persona completa"),
                 str(e["distinct_top1"])]
        if e["official"]:
            cells = [c if c.startswith("**") else f"**{c}**" for c in cells]
        lines.append("| " + " | ".join(cells) + " |")
    lines += ["", "## Prendas (paleta por prenda, `ce batch --garments`)", "",
              "Con pose, regiones de `ce garment-regions` (1 arriba, 2 abajo; 3 = prenda entera si arriba y abajo son la misma); "
              "sin pose, una sola región. ΔE00 prenda→su región: media por foto del ΔE00 de cada prenda anotada al swatch de "
              "prenda de su región (torso → arriba o entera, piernas → abajo o entera).", "",
              "| variante | fotos con prendas | con regiones | colores de paleta (mediana) | colores de prenda (mediana) | máx. colores en una región | ΔE00 prenda→su región mediana |",
              "|---|---|---|---|---|---|---|"]
    for v in variants:
        e = agg[v]
        lines.append(f"| {v} | {e.get('garments_n', 0)}/{e['n_photos']} | {e.get('garments_with_regions', 0)} | "
                     f"{_f(e.get('palette_swatches_median'), 0)} | {_f(e.get('garment_swatches_median'), 0)} | "
                     f"{e.get('garment_max_per_region_max') if e.get('garment_max_per_region_max') is not None else '—'} | "
                     f"{_f(e.get('de_garment_region_median'))} |")
    lines += ["", "## Por foto", "",
              "| foto | personas (Vision / anotadas) | variante | pasos | cobertura | dominante (peso) | ΔE00 dominante | ΔE00 prendas→paleta | peso ropa | top-3 | prendas (región: color peso) | ΔE00 prenda→región | top-3 prendas |",
              "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for p in doc["photos"]:
        garments = "; ".join(f"{g.get('part')} {g.get('color_hex')}" for g in p["garments"]) or "—"
        for j, v in enumerate(variants):
            c = p["variants"].get(v) or {}
            head = f"{p['file']}<br>prendas: {garments}" if j == 0 else ""
            ppl = f"{p['people'] if p['people'] is not None else '—'} / {p['expected_people'] if p['expected_people'] is not None else '—'}" if j == 0 else ""
            name = f"**{v}**" if v == l4v.OFFICIAL_VARIANT else v
            if c.get("status") != "ok" or "error" in c:
                lines.append(f"| {head} | {ppl} | {name} | {c.get('status', '—')}: {c.get('reason') or c.get('error') or '—'} | — | — | — | — | — | — | — | — | — |")
                continue
            steps = " → ".join(c.get("steps") or []) or ("—" if v == "none" else "persona completa")
            cov = "sin máscara" if not c.get("mask") else f"{100 * float(c.get('coverage') or 0):.1f} %"
            dom = f"`{c['dominant_hex']}` ({100 * c['dominant_weight']:.0f} %)"
            gw = "—" if c.get("garment_weight") is None else f"{100 * c['garment_weight']:.0f} %"
            region_names = {0: "única", 1: "arriba", 2: "abajo", 3: "entera"}
            gsw = "; ".join(f"{region_names.get(r, r)}: `{h}` {100 * w:.0f} %" for h, r, w, _n in c.get("garment_swatches") or []) \
                or (c.get("garments_error") or "—")
            lines.append(f"| {head} | {ppl} | {name} | {steps} | {cov} | {dom} | {_f(c.get('de_dominant'))} | {_f(c.get('de_garments'))} | {gw} | "
                         + ", ".join(str(t) for t in c.get("top", [])[:3])
                         + f" | {gsw} | {_f(c.get('de_garment_region'))} | " + ", ".join(str(t) for t in c.get("garment_top", [])[:3]) + " |")
    lines += ["", f"Detalle: `{doc['out_json']}`. Capas visuales de cada paso: `make layers-report`.", ""]
    return "\n".join(lines)


def run_smoke(cli: Path, people_dir: Path, out_dir: Path, *, variants: list[str] | None = None,
              visionmask: Path | str | None = "auto", build_visionmask: bool = False, log=print) -> tuple[int, dict[str, Any]]:
    variants = list(variants or l4v.VARIANTS)
    if "none" not in variants:
        variants.insert(0, "none")
    started = time.perf_counter()
    expected_path = people_dir / "expected.json"
    expected: dict[str, dict[str, Any]] = {}
    if expected_path.is_file():
        for e in json.loads(expected_path.read_text(encoding="utf-8")):
            if isinstance(e, dict) and isinstance(e.get("file"), str):
                expected[e["file"]] = e
    photos = sorted(p for p in people_dir.iterdir() if p.suffix.lower() in PHOTO_SUFFIXES)
    if not photos:
        raise FileNotFoundError(f"no hay fotos PNG/JPEG en {people_dir}")
    work = out_dir / "l4_people_smoke"
    masks_dir = work / "masks"
    vm_path: Path | None = None
    vm_reason = "visionmask desactivado"
    if visionmask is not None:
        vm_path, vm_reason = l4v.ensure_visionmask(None if visionmask == "auto" else visionmask, build_visionmask, log)
    if masks_dir.exists():
        for f in masks_dir.glob("*"):
            if f.is_file():
                f.unlink()
    masks_dir.mkdir(parents=True, exist_ok=True)
    exit_code = 0
    photo_rows: list[dict[str, Any]] = []
    lines: list[tuple[Path, Path | None]] = []
    where: list[tuple[int, str]] = []
    engine = dict_version = None
    for i, photo in enumerate(photos):
        exp = expected.get(photo.name, {})
        garments = list(((exp.get("largest_person") or {}).get("garments")) or [])
        row: dict[str, Any] = {"file": photo.name, "expected_people": exp.get("people"), "garments": garments,
                               "people": None, "raster": None, "variants": {}}
        doc = None
        if vm_path is not None:
            try:
                doc = l4v.run_visionmask(vm_path, photo, masks_dir, [v for v in variants if v != "none"] or ["none"],
                                         layers=True)
            except l4v.VariantError as exc:
                log(f"  [error] {exc}")
                exit_code = 1
                for v in variants:
                    row["variants"][v] = {"status": "error", "reason": str(exc)}
                photo_rows.append(row)
                continue
            raster = Path(doc["raster"])
            row["people"] = int(doc.get("people_count") or 0)
        else:
            from tools import to_ppm

            raster = masks_dir / f"{photo.stem}.ppm"
            to_ppm.convert(photo, raster, max_side=1024)
        row["raster"] = str(raster)
        for v in variants:
            if v == "none":
                row["variants"][v] = {"status": "ok", "mask": None, "steps": []}
                lines.append((raster, None))
                where.append((i, v))
                continue
            if doc is None:
                row["variants"][v] = {"status": "skipped", "reason": f"sin visionmask ({vm_reason})"}
                continue
            ve = l4v.variant_entry(doc, v)
            if ve is None or "error" in ve:
                row["variants"][v] = {"status": "error", "reason": (ve or {}).get("error", f"visionmask no devolvió {v}")}
                exit_code = 1
                continue
            mask = Path(ve["mask"]) if isinstance(ve.get("mask"), str) else None
            row["variants"][v] = {"status": "ok", "mask": str(mask) if mask else None, "steps": list(ve.get("steps") or []),
                                  "coverage": ve.get("mask_coverage"), "people": row["people"],
                                  "layers_dir": ve.get("layers") if isinstance(ve.get("layers"), str) else None}
            lines.append((raster, mask))
            where.append((i, v))
        photo_rows.append(row)
    results = l4v.run_batch_lines(cli, lines) if lines else []
    for (i, v), r in zip(where, results):
        cell = photo_rows[i]["variants"][v]
        if "error" in r:
            cell["error"] = str(r["error"])
            exit_code = 1
            continue
        engine, dict_version = r.get("engine", engine), r.get("dict_version", dict_version)
        cell.update(photo_metrics(r, photo_rows[i]["garments"]))
    # Paleta por prenda: regiones de la pose (si la hay) y ce batch --garments en una invocación.
    from oracle import garments as gm

    if gm.has_garments(cli) and lines:
        entries: list[tuple[Path, Path | None, Path | None]] = []
        for (i, v), (img, mask) in zip(where, lines):
            cell = photo_rows[i]["variants"][v]
            regions = None
            layers_dir = Path(cell["layers_dir"]) if cell.get("layers_dir") else None
            if mask is not None and layers_dir is not None and (layers_dir / "pose.txt").is_file():
                regions = work / "garment_regions" / f"{Path(img).stem}.{v}.regions.pgm"
                regions.parent.mkdir(parents=True, exist_ok=True)
                h, w = sc_read_ppm_shape(Path(img))
                import subprocess

                proc = subprocess.run([str(cli), "garment-regions", "--size", f"{w}x{h}", "--mask", str(mask), "--pose",
                                       str(layers_dir / "pose.txt"), "--out", str(regions), *gm.PEOPLE_REGION_ARGS],
                                      capture_output=True, text=True, check=False, timeout=120)
                if proc.returncode != 0:
                    cell["garment_regions_error"] = proc.stderr.strip()[:200]
                    regions = None
            entries.append((Path(img), mask, regions))
        try:
            g_results = gm.run_batch_garments(cli, entries)
        except gm.GarmentError as exc:
            log(f"  [error] {exc}")
            exit_code = 1
            g_results = []
        for (i, v), r in zip(where, g_results):
            photo_rows[i]["variants"][v].update(garment_metrics(r, photo_rows[i]["garments"]))
    doc_out: dict[str, Any] = {
        "schema": 1, "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"), "engine": engine, "dict_version": dict_version,
        "people_dir": str(people_dir), "visionmask": str(vm_path) if vm_path else None,
        "visionmask_reason": None if vm_path else vm_reason, "variants": variants, "garment_de": GARMENT_DE,
        "photos": photo_rows, "aggregate": aggregate(variants, photo_rows),
        "out_json": str(out_dir / "l4_people_smoke.json"), "seconds": None,
    }
    doc_out["seconds"] = round(time.perf_counter() - started, 1)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "l4_people_smoke.json").write_text(json.dumps(doc_out, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    (out_dir / "l4_people_smoke.md").write_text(render_markdown(doc_out), encoding="utf-8")
    return exit_code, doc_out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cli", type=str, default=None)
    ap.add_argument("--people-dir", type=Path, default=DEFAULT_PEOPLE)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--variants", type=str, default=None)
    ap.add_argument("--visionmask", type=str, default=None)
    ap.add_argument("--no-visionmask", action="store_true")
    ap.add_argument("--build-visionmask", action="store_true")
    args = ap.parse_args(argv)
    cli = find_cli_optional(args.cli)
    if cli is None or not l3.has_batch(cli):
        print(f"l4-people-smoke: {l3.not_implemented_reason(cli)}", file=sys.stderr)
        return 2
    variants = [v.strip() for v in args.variants.split(",") if v.strip()] if args.variants else None
    try:
        code, doc = run_smoke(cli, args.people_dir, args.out, variants=variants,
                              visionmask=None if args.no_visionmask else (args.visionmask or "auto"),
                              build_visionmask=args.build_visionmask)
    except (FileNotFoundError, l4v.VariantError) as exc:
        print(f"l4-people-smoke: {exc}", file=sys.stderr)
        return 2 if isinstance(exc, FileNotFoundError) else 1
    md = render_markdown(doc)
    print(md.split("## Por foto")[0].rstrip())
    if doc["visionmask"] is None:
        print(f"\nAVISO: variantes con máscara skipped: {doc['visionmask_reason']}")
    print(f"\nl4-people-smoke: {args.out / 'l4_people_smoke.md'} y .json ({doc['seconds']} s) -> exit {code}")
    return code


if __name__ == "__main__":
    sys.exit(main())
