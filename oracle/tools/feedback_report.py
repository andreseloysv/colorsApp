#!/usr/bin/env python3
"""Informe de uso real (fase 8) a partir de los zips de "Exportar diagnóstico" de la app.

    uv run --project oracle python oracle/tools/feedback_report.py <zip|dir> [<zip|dir> ...]
        [--out harness/out] [--thresholds harness/thresholds.json] [--extract DIR]

Entrada: zips con el formato exacto de ``ios/ColorsApp/Support/Diagnostics.swift``:

- ``README.txt``: cabecera (``exportado: <ISO8601>``, ``app X (Y) · motor Z · diccionario W ...``).
- ``feedback.csv``: ``scan_id,verdict,top1,top2,top3,scores,created_at`` (``verdict`` = yes|no).
- ``scans.csv``: ``id,source,top1,top2,top3,scores,ambiguous,engine_version,dict_version,scanned_at,palette``
  (``source`` = camera|picker|library (escaneo día 0)|manual).
- ``times.txt``: una línea ``<ISO8601> <etiqueta> <ms> ms`` por medición (``analyze.<origen>``,
  ``scan.done``); se tolera también ``<ISO8601> scan.done <n> <ms> ms``.
- ``images/<scan_id>.png``: PNG sRGB de 256 px de las fotos con veredicto.

Columnas y ficheros opcionales (builds con extracción de sujeto; sin ellos todo funciona igual):
``feedback.csv`` (y/o ``scans.csv``) con ``subject_mode`` (off|allPeople|largestPerson|selectedPerson),
``region_mode`` (wholePerson|clothing), ``adaptive_skin`` (1/0, true/false), ``people_count`` y
``person_index``; junto a cada PNG, ``images/<scan_id>.<variante>.pgm`` (máscaras de 256 px:
``largest``, ``largest-clothing``, ``largest-clothing-skin``...) y ``images/<scan_id>.json`` (pasos,
personas, tiempos). Columnas desconocidas se avisan y se ignoran.

Un "teléfono" es cada zip (nombre = stem del zip: renombra los exports a ``andres.zip``,
``esposa.zip``) o cada subdirectorio de un directorio pasado como argumento (nombre = el
subdirectorio; agrupa varios exports del mismo teléfono). Si el README trae una línea
``device: <nombre>`` (o ``dispositivo:``) manda sobre el nombre del fichero. Las filas
repetidas entre zips (mismo ``scan_id`` en scans; misma ``(scan_id, verdict, created_at)``
en feedback; misma línea de ``times.txt``) se cuentan una sola vez, por teléfono y en el global.
Una valoración = el último veredicto de cada ``scan_id`` (si un scan tiene varios, los anteriores
se avisan y no cuentan).

Por teléfono y global: scans, valoraciones, % de "sí" (yes / (yes + no)), cuota de la
combinación top-1 más frecuente entre las valoraciones (y, informativa, entre todos los
scans), distribución por fuente, tiempos (``scan.done`` si está en ``times.txt``) y la lista
de fotos con veredicto "no" (nombres de PNG) para el set dorado; si hay columnas de recorte,
además por modo de recorte (``subject_mode/region_mode/skin``) y por número de personas (1 / grupo).
Escribe ``<out>/feedback-report.json`` y ``feedback-report.md``; ``--extract DIR`` copia los PNG de
las fotos valoradas a ``DIR/<teléfono>_<scan_id>.png`` (y sus máscaras como
``<teléfono>_<scan_id>.<variante>.pgm``, el nombre que descubre ``merge_labels.py``; el resto de
ficheros de ``images/<scan_id>.*`` —JSON de pasos, capas— van a ``DIR/capas/`` para que nunca se
confundan con fotos) con un ``feedback-index.csv``. DIR debe vivir fuera del repo (material del set
dorado; se admite ``harness/out/``, que no se versiona): dentro del repo se rechaza con exit 2.

Gate de F10 (sección 8 del plan) sobre el global, con ``harness/thresholds.json`` sección
``F10`` si existe y si no con los valores por defecto anotados: valoraciones >= 50
(``min_ratings``), "sí" >= 0,70 (``yes_rate_min``), cuota <= 0,30 (``max_class_share_max``).
``scan.done`` se compara con ``scan_done_max_ms`` (120000 provisional, PLAN §7.6): gatea
solo si el umbral viene de ``thresholds.json``; con el valor por defecto es informativo.

Códigos de salida: 0 gate superado; 1 gate no superado; 2 sin zips (o ninguno legible) o
``--extract`` dentro del repo. ``make feedback-report`` los muestra como "Error 1"/"Error 2" (GNU make
sale siempre con 2 cuando falla una receta).
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import shutil
import statistics
import sys
import zipfile
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "harness" / "out"
DEFAULT_THRESHOLDS = REPO_ROOT / "harness" / "thresholds.json"
REPORT_STEM = "feedback-report"
FEEDBACK_HEADER = ["scan_id", "verdict", "top1", "top2", "top3", "scores", "created_at"]
SCANS_HEADER = ["id", "source", "top1", "top2", "top3", "scores", "ambiguous", "engine_version", "dict_version", "scanned_at", "palette"]
#: Columnas opcionales (extracción de sujeto, sección 10 del contexto): se aceptan si están.
CROP_COLUMNS = ["subject_mode", "region_mode", "adaptive_skin", "people_count", "person_index"]
SCANS_OPTIONAL = [*CROP_COLUMNS, "mask_steps", "mask_coverage"]
SUBJECT_LABELS = {"off": "sin recorte", "allPeople": "todas las personas", "largestPerson": "persona principal",
                  "selectedPerson": "persona elegida"}
REGION_LABELS = {"wholePerson": "persona completa", "clothing": "solo ropa"}
NO_CROP_DATA = "sin-datos"
SOURCE_LABELS = {"camera": "cámara", "picker": "picker", "library": "día 0 (carrete)", "manual": "manual"}
#: Gate de F10 (PLAN §8, fila 10) cuando thresholds.json no trae la sección F10.
DEFAULTS: dict[str, Any] = {"min_ratings": 50, "yes_rate_min": 0.70, "max_class_share_max": 0.30, "scan_done_max_ms": 120000}
_TIME_RE = re.compile(r"^(?P<ts>\S+)\s+(?P<label>\S+)\s+(?:(?P<count>\d+)\s+)?(?P<ms>\d+)\s*ms\s*$")


class ZipFormatError(ValueError):
    """El zip no tiene los ficheros o cabeceras de Diagnostics.swift."""


@dataclass
class PhoneData:
    """Filas acumuladas de un teléfono (uno o varios zips)."""

    name: str
    zips: list[str] = field(default_factory=list)
    feedback: dict[tuple[str, str, str], dict[str, str]] = field(default_factory=dict)
    scans: dict[str, dict[str, str]] = field(default_factory=dict)
    times: list[dict[str, Any]] = field(default_factory=list)
    images: dict[str, tuple[Path, str]] = field(default_factory=dict)  # scan_id -> (zip, miembro)
    masks: dict[str, dict[str, tuple[Path, str]]] = field(default_factory=dict)  # scan_id -> {variante: (zip, miembro)}
    extras: dict[str, tuple[Path, str]] = field(default_factory=dict)  # "<scan_id>.<resto>" -> (zip, miembro): json, capas
    readme: dict[str, str] = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)


# --------------------------------------------------------------------------------------
# Lectura de zips
# --------------------------------------------------------------------------------------


def find_zips(paths: list[Path]) -> list[tuple[str, Path]]:
    """(teléfono, zip) para cada argumento: zip suelto (stem), directorio (zips de primer
    nivel por stem; subdirectorios como un teléfono cada uno)."""
    found: list[tuple[str, Path]] = []
    for p in paths:
        if p.is_file():
            found.append((p.stem, p))
        elif p.is_dir():
            for z in sorted(p.glob("*.zip")):
                found.append((z.stem, z))
            for sub in sorted(x for x in p.iterdir() if x.is_dir()):
                for z in sorted(sub.rglob("*.zip")):
                    found.append((sub.name, z))
    return found


def _read_csv(text: str, expected: list[str], optional: list[str], name: str) -> tuple[list[dict[str, str]], list[str]]:
    """Filas y columnas desconocidas. Exige las columnas de ``expected`` (en cualquier orden); las de
    ``optional`` se aceptan; el resto se avisa y se ignora."""
    header_rows = list(csv.reader(io.StringIO(text.splitlines()[0] if text else "")))
    header = header_rows[0] if header_rows else []
    missing = [c for c in expected if c not in header]
    if missing:
        raise ZipFormatError(f"{name}: faltan columnas {missing} (cabecera {header})")
    rows = [{k: (v if v is not None else "") for k, v in r.items() if k is not None}
            for r in csv.DictReader(io.StringIO(text))]
    unknown = [c for c in header if c not in expected and c not in optional]
    return rows, unknown


def split_member(member: str) -> tuple[str, str, str] | None:
    """``images/<base>[.<resto>].<ext>`` -> (base, resto, ext en minúsculas); None si no es de images/."""
    if not member.startswith("images/") or member.endswith("/"):
        return None
    name = member[len("images/"):]
    if "/" in name or "." not in name:
        return None
    stem, ext = name.rsplit(".", 1)
    base, _, rest = stem.partition(".")
    return base, rest, ext.lower()


def parse_readme(text: str) -> dict[str, str]:
    meta: dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("exportado:"):
            meta["exported_at"] = line.split(":", 1)[1].strip()
        elif line.startswith("app "):
            meta["versions"] = line
        elif line.lower().startswith(("device:", "dispositivo:")):
            meta["device"] = line.split(":", 1)[1].strip()
    return meta


def parse_times(text: str) -> tuple[list[dict[str, Any]], list[str]]:
    rows: list[dict[str, Any]] = []
    bad: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        m = _TIME_RE.match(line)
        if not m:
            bad.append(line[:80])
            continue
        rows.append({"ts": m["ts"], "label": m["label"], "ms": int(m["ms"]),
                     **({"count": int(m["count"])} if m["count"] else {})})
    return rows, bad


def read_zip(path: Path, phone: PhoneData) -> None:
    """Vuelca un zip en ``phone`` (dedupe por scan_id / (scan_id, verdict, created_at))."""
    with zipfile.ZipFile(path) as zf:
        names = set(zf.namelist())
        missing = [n for n in ("feedback.csv", "scans.csv", "times.txt") if n not in names]
        if missing:
            raise ZipFormatError(f"{path.name}: faltan {', '.join(missing)}")
        text = {n: zf.read(n).decode("utf-8") for n in ("feedback.csv", "scans.csv", "times.txt")}
        if "README.txt" in names:
            phone.readme.update(parse_readme(zf.read("README.txt").decode("utf-8", "replace")))
        for m in zf.namelist():
            parts = split_member(m)
            if parts is None:
                continue
            base, rest, ext = parts
            if ext == "png" and not rest:
                phone.images.setdefault(base, (path, m))
            elif ext == "pgm" and rest and re.fullmatch(r"[A-Za-z0-9_-]+", rest):
                phone.masks.setdefault(base, {}).setdefault(rest, (path, m))
            else:
                phone.extras.setdefault(f"{base}.{rest}.{ext}" if rest else f"{base}.{ext}", (path, m))
    feedback_rows, unknown_fb = _read_csv(text["feedback.csv"], FEEDBACK_HEADER, CROP_COLUMNS, "feedback.csv")
    scan_rows, unknown_sc = _read_csv(text["scans.csv"], SCANS_HEADER, SCANS_OPTIONAL, "scans.csv")
    for name, unknown in (("feedback.csv", unknown_fb), ("scans.csv", unknown_sc)):
        if unknown:
            phone.notes.append(f"{path.name}: {name}: columnas desconocidas ignoradas: {', '.join(unknown)}")
    for row in feedback_rows:
        if row["verdict"] not in ("yes", "no"):
            phone.notes.append(f"{path.name}: verdict {row['verdict']!r} desconocido (scan {row['scan_id']})")
            continue
        phone.feedback.setdefault((row["scan_id"], row["verdict"], row["created_at"]), row)
    for row in scan_rows:
        phone.scans.setdefault(row["id"], row)
    times, bad = parse_times(text["times.txt"])
    phone.times += times
    if bad:
        phone.notes.append(f"{path.name}: {len(bad)} línea(s) de times.txt ilegibles (p. ej. {bad[0]!r})")
    phone.zips.append(path.name)


def load_phones(zips: list[tuple[str, Path]], log=print) -> tuple[list[PhoneData], list[str]]:
    by_name: dict[str, PhoneData] = {}
    errors: list[str] = []
    for name, path in zips:
        tmp = PhoneData(name=name)
        try:
            read_zip(path, tmp)
        except (zipfile.BadZipFile, ZipFormatError, UnicodeDecodeError, KeyError) as exc:
            errors.append(f"{path}: {exc}")
            log(f"  [ignorado] {path}: {exc}")
            continue
        key = tmp.readme.get("device") or name
        phone = by_name.setdefault(key, PhoneData(name=key))
        phone.zips += tmp.zips
        phone.notes += tmp.notes
        phone.readme.update(tmp.readme)
        _add_times(phone.times, tmp.times)
        for k, v in tmp.feedback.items():
            phone.feedback.setdefault(k, v)
        for k, v in tmp.scans.items():
            phone.scans.setdefault(k, v)
        for k, v in tmp.images.items():
            phone.images.setdefault(k, v)
        for k, v in tmp.masks.items():
            for variant, member in v.items():
                phone.masks.setdefault(k, {}).setdefault(variant, member)
        for k, v in tmp.extras.items():
            phone.extras.setdefault(k, v)
    return list(by_name.values()), errors


def _add_times(target: list[dict[str, Any]], rows: list[dict[str, Any]]) -> None:
    """Añade mediciones sin repetir (exports sucesivos del mismo teléfono llevan el times.txt acumulado)."""
    seen = {tuple(sorted(t.items())) for t in target}
    for t in rows:
        key = tuple(sorted(t.items()))
        if key not in seen:
            seen.add(key)
            target.append(t)


def latest_feedback(phone: PhoneData) -> tuple[list[dict[str, str]], int]:
    """(último veredicto por scan_id, en orden de scan_id; nº de veredictos anteriores descartados)."""
    latest: dict[str, dict[str, str]] = {}
    for (sid, _verdict, created), row in sorted(phone.feedback.items(), key=lambda kv: (kv[0][0], kv[0][2], kv[0][1])):
        latest[sid] = row
    return [latest[sid] for sid in sorted(latest)], len(phone.feedback) - len(latest)


def merge_global(phones: list[PhoneData]) -> PhoneData:
    g = PhoneData(name="global")
    for p in phones:
        g.zips += p.zips
        _add_times(g.times, p.times)
        for k, v in p.feedback.items():
            g.feedback.setdefault(k, v)
        for k, v in p.scans.items():
            g.scans.setdefault(k, v)
        for k, v in p.images.items():
            g.images.setdefault(k, v)
        for k, v in p.masks.items():
            for variant, member in v.items():
                g.masks.setdefault(k, {}).setdefault(variant, member)
    return g


# --------------------------------------------------------------------------------------
# Métricas
# --------------------------------------------------------------------------------------


def _int_or_none(s: str) -> int | None:
    try:
        return int(s)
    except (TypeError, ValueError):
        return None


def _share(counter: Counter) -> tuple[float | None, int | None]:
    total = sum(counter.values())
    if not total:
        return None, None
    top, n = counter.most_common(1)[0]
    return n / total, top


def _parse_bool(s: str | None) -> bool | None:
    v = (s or "").strip().lower()
    if v in ("1", "true", "yes", "si", "sí", "on"):
        return True
    if v in ("0", "false", "no", "off"):
        return False
    return None


def crop_fields(row: dict[str, str], scan: dict[str, str] | None) -> dict[str, Any]:
    """Columnas de recorte de una valoración: las de feedback.csv y, si faltan, las del scan."""
    out: dict[str, Any] = {}
    for col in CROP_COLUMNS:
        value = (row.get(col) or "").strip()
        if not value and scan is not None:
            value = (scan.get(col) or "").strip()
        out[col] = value
    return out


def crop_mode_key(fields: dict[str, Any]) -> str:
    """``subject_mode/region_mode/skin|noskin`` (``off`` sin más; ``sin-datos`` en builds anteriores)."""
    subject = fields.get("subject_mode") or ""
    if not subject:
        return NO_CROP_DATA
    if subject == "off":
        return "off"
    skin = _parse_bool(fields.get("adaptive_skin"))
    return f"{subject}/{fields.get('region_mode') or '?'}/{'skin' if skin else ('noskin' if skin is False else '?')}"


def crop_mode_label(key: str) -> str:
    if key == NO_CROP_DATA:
        return "sin datos de recorte (build anterior)"
    if key == "off":
        return SUBJECT_LABELS["off"]
    subject, region, skin = (key.split("/") + ["?", "?"])[:3]
    return " · ".join([SUBJECT_LABELS.get(subject, subject), REGION_LABELS.get(region, region),
                       {"skin": "piel adaptativa", "noskin": "sin excluir piel"}.get(skin, "piel ?")])


def people_bucket(fields: dict[str, Any]) -> str:
    raw = fields.get("people_count") or ""
    n = _int_or_none(raw)
    if n is None:
        return NO_CROP_DATA
    return "0" if n <= 0 else ("1" if n == 1 else "2+")


PEOPLE_LABELS = {"0": "sin personas", "1": "1 persona", "2+": "grupo (2+ personas)", NO_CROP_DATA: "sin datos"}


def _group_stats(rows: list[dict[str, str]]) -> dict[str, Any]:
    yes = sum(1 for r in rows if r["verdict"] == "yes")
    top1 = Counter(t for t in (_int_or_none(r["top1"]) for r in rows) if t is not None)
    share, top = _share(top1)
    return {"n_ratings": len(rows), "yes": yes, "no": len(rows) - yes, "yes_rate": (yes / len(rows)) if rows else None,
            "top1_share": share, "top1_id": top}


def _time_stats(values: list[int]) -> dict[str, Any]:
    return {"n": len(values), "median_ms": statistics.median(values), "mean_ms": round(statistics.fmean(values), 1),
            "max_ms": max(values), "min_ms": min(values)}


def summarize(phone: PhoneData) -> dict[str, Any]:
    fb, superseded = latest_feedback(phone)
    yes = sum(1 for r in fb if r["verdict"] == "yes")
    no = len(fb) - yes
    rated_top1 = Counter(t for t in (_int_or_none(r["top1"]) for r in fb) if t is not None)
    rated_share, rated_top = _share(rated_top1)
    scan_top1 = Counter(t for t in (_int_or_none(s["top1"]) for s in phone.scans.values()) if t is not None)
    scan_share, scan_top = _share(scan_top1)
    by_source = Counter(s["source"] for s in phone.scans.values())
    by_label: dict[str, list[int]] = {}
    for t in phone.times:
        by_label.setdefault(t["label"], []).append(t["ms"])
    no_photos = sorted({r["scan_id"] for r in fb if r["verdict"] == "no"})
    by_mode: dict[str, list[dict[str, str]]] = {}
    by_people: dict[str, list[dict[str, str]]] = {}
    non_largest = 0
    for r in fb:
        fields = crop_fields(r, phone.scans.get(r["scan_id"]))
        by_mode.setdefault(crop_mode_key(fields), []).append(r)
        by_people.setdefault(people_bucket(fields), []).append(r)
        idx = _int_or_none(fields.get("person_index") or "")
        if idx is not None and idx > 0:
            non_largest += 1
    rated_ids = {r["scan_id"] for r in fb}
    mask_variants = Counter(v for sid in rated_ids for v in phone.masks.get(sid, {}))
    return {
        "name": phone.name,
        "zips": sorted(phone.zips),
        "versions": phone.readme.get("versions"),
        "exported_at": phone.readme.get("exported_at"),
        "n_scans": len(phone.scans),
        "n_ratings": len(fb),
        "yes": yes,
        "no": no,
        "yes_rate": (yes / (yes + no)) if fb else None,
        "rated_top1_share": rated_share,
        "rated_top1_id": rated_top,
        "rated_top1_distinct": len(rated_top1),
        "scans_top1_share": scan_share,
        "scans_top1_id": scan_top,
        "scans_top1_distinct": len(scan_top1),
        "ambiguous_rate": (sum(1 for s in phone.scans.values() if s["ambiguous"] == "1") / len(phone.scans)) if phone.scans else None,
        "by_source": dict(sorted(by_source.items())),
        "times": {label: _time_stats(v) for label, v in sorted(by_label.items())},
        "scan_done_ms": sorted(by_label.get("scan.done", [])),
        "no_photos": [{"scan_id": sid, "png": f"images/{sid}.png", "in_zip": sid in phone.images} for sid in no_photos],
        "rated_without_png": sorted({r["scan_id"] for r in fb} - set(phone.images)),
        "by_crop_mode": {k: {"label": crop_mode_label(k), **_group_stats(v)} for k, v in sorted(by_mode.items())},
        "by_people": {k: {"label": PEOPLE_LABELS[k], **_group_stats(v)} for k, v in sorted(by_people.items())},
        "person_index_not_largest": non_largest,
        "rated_with_masks": sum(1 for sid in rated_ids if phone.masks.get(sid)),
        "mask_variants": dict(sorted(mask_variants.items())),
        "superseded_verdicts": superseded,
        "notes": list(phone.notes) + ([f"{superseded} veredicto(s) anteriores de un mismo scan ignorados (cuenta el último)"] if superseded and phone.name != "global" else []),
    }


# --------------------------------------------------------------------------------------
# Gate F10
# --------------------------------------------------------------------------------------


def load_thresholds(path: Path) -> tuple[dict[str, Any], list[str]]:
    section: dict[str, Any] = {}
    if path.is_file():
        doc = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(doc.get("F10"), dict):
            section = doc["F10"]
    values: dict[str, Any] = {}
    defaulted: list[str] = []
    for key, default in DEFAULTS.items():
        if key in section:
            values[key] = section[key]
        else:
            values[key] = default
            defaulted.append(key)
    return values, defaulted


def gate_checks(total: dict[str, Any], th: dict[str, Any], defaulted: list[str]) -> list[dict[str, Any]]:
    """Checks del gate (status pass|fail|info); solo pass/fail cuentan para el exit."""
    checks: list[dict[str, Any]] = []
    n = total["n_ratings"]
    checks.append({"name": f"valoraciones >= {th['min_ratings']} (min_ratings)", "status": "pass" if n >= int(th["min_ratings"]) else "fail",
                   "value": n, "threshold": th["min_ratings"], "detail": f"{n} valoraciones ({total['yes']} sí, {total['no']} no)"})
    yr = total["yes_rate"]
    checks.append({"name": f"\"sí\" >= {th['yes_rate_min']:.2f} (yes_rate_min)", "status": "pass" if yr is not None and yr >= float(th["yes_rate_min"]) else "fail",
                   "value": yr, "threshold": th["yes_rate_min"], "detail": (f"{100 * yr:.1f} %" if yr is not None else "sin valoraciones")})
    sh = total["rated_top1_share"]
    checks.append({"name": f"cuota del top-1 más frecuente <= {th['max_class_share_max']:.2f} (max_class_share_max)",
                   "status": "pass" if sh is not None and sh <= float(th["max_class_share_max"]) else "fail",
                   "value": sh, "threshold": th["max_class_share_max"],
                   "detail": (f"{100 * sh:.1f} % (combo {total['rated_top1_id']}, {total['rated_top1_distinct']} distintas entre las valoradas)"
                              if sh is not None else "sin valoraciones con top-1")})
    sd = total["scan_done_ms"]
    gated = "scan_done_max_ms" not in defaulted
    if not sd:
        status, detail = "info", "sin líneas scan.done en times.txt (el escaneo día 0 no registró tiempo en TimingLog; si la build solo lo escribe en os.Logger, no llega al zip)"
    else:
        ok = max(sd) <= int(th["scan_done_max_ms"])
        status = ("pass" if ok else "fail") if gated else "info"
        detail = f"máx {max(sd)} ms, mediana {statistics.median(sd):.0f} ms sobre {len(sd)} escaneo(s)" + ("" if gated else "; umbral provisional (PLAN §7.6), no gatea hasta que el usuario lo fije en thresholds.json")
    checks.append({"name": f"scan.done <= {th['scan_done_max_ms']} ms (scan_done_max_ms)", "status": status,
                   "value": max(sd) if sd else None, "threshold": th["scan_done_max_ms"], "detail": detail})
    return checks


# --------------------------------------------------------------------------------------
# Salida
# --------------------------------------------------------------------------------------


def _pct(x: float | None) -> str:
    return "—" if x is None else f"{100 * x:.1f} %"


def _sources(d: dict[str, int]) -> str:
    return ", ".join(f"{SOURCE_LABELS.get(k, k)} {v}" for k, v in d.items()) or "—"


def _scan_done(s: dict[str, Any]) -> str:
    v = s["scan_done_ms"]
    return "—" if not v else (f"{v[0]} ms" if len(v) == 1 else f"máx {max(v)} ms ({len(v)})")


def render_table(rows: list[dict[str, Any]]) -> str:
    head = ["teléfono", "scans", "valoraciones", "sí", "no", "% sí", "cuota top-1", "fuentes", "scan.done"]
    body = [[s["name"], str(s["n_scans"]), str(s["n_ratings"]), str(s["yes"]), str(s["no"]), _pct(s["yes_rate"]),
             (f"{_pct(s['rated_top1_share'])} (Nº {s['rated_top1_id']:03d})" if s["rated_top1_id"] is not None else "—"),
             _sources(s["by_source"]), _scan_done(s)] for s in rows]
    widths = [max(len(h), *(len(r[i]) for r in body)) for i, h in enumerate(head)]
    line = lambda cells: "| " + " | ".join(c.ljust(w) for c, w in zip(cells, widths)) + " |"  # noqa: E731
    return "\n".join([line(head), "|" + "|".join("-" * (w + 2) for w in widths) + "|", *(line(r) for r in body)])


def render_groups(groups: dict[str, dict[str, Any]], title: str) -> str:
    head = [title, "valoraciones", "sí", "no", "% sí", "cuota top-1"]
    body = [[g["label"] + ("" if k in (NO_CROP_DATA, "0", "1", "2+") else f" ({k})"), str(g["n_ratings"]), str(g["yes"]), str(g["no"]),
             _pct(g["yes_rate"]), (f"{_pct(g['top1_share'])} (Nº {g['top1_id']:03d})" if g["top1_id"] is not None else "—")]
            for k, g in groups.items()]
    if not body:
        return f"| {title} |\n|---|\n| sin valoraciones |"
    widths = [max(len(h), *(len(r[i]) for r in body)) for i, h in enumerate(head)]
    line = lambda cells: "| " + " | ".join(c.ljust(w) for c, w in zip(cells, widths)) + " |"  # noqa: E731
    return "\n".join([line(head), "|" + "|".join("-" * (w + 2) for w in widths) + "|", *(line(r) for r in body)])


def render_markdown(report: dict[str, Any]) -> str:
    t = report["total"]
    out = ["# Informe de uso real (feedback-report)", "",
           f"Zips: {len(report['zips'])} · teléfonos: {len(report['phones'])} · generado por `oracle/tools/feedback_report.py`.", "",
           render_table([*report["phones"], t]), "",
           "## Gate F10 (global)", ""]
    for c in report["checks"]:
        out.append(f"- [{c['status']}] {c['name']}: {c['detail']}")
    if report["thresholds_defaulted"]:
        out.append(f"- [info] umbrales por defecto (sin sección F10 en thresholds.json): {', '.join(report['thresholds_defaulted'])}")
    out += ["", f"**Resultado: {'PASS' if report['gate_pass'] else 'FAIL'}**", "",
            "## Por modo de recorte (global, informativo)", "", render_groups(t["by_crop_mode"], "modo de recorte"), "",
            render_groups(t["by_people"], "personas en la foto"), "",
            f"- valoraciones con otra persona elegida (person_index > 0): {t['person_index_not_largest']}",
            f"- fotos valoradas con máscaras en el zip: {t['rated_with_masks']}"
            + (f" (variantes: {', '.join(f'{k} {v}' for k, v in t['mask_variants'].items())})" if t["mask_variants"] else ""),
            "", "## Tiempos (ms)", ""]
    for name, s in [(p["name"], p) for p in report["phones"]]:
        for label, st in s["times"].items():
            out.append(f"- {name} · `{label}`: n={st['n']}, mediana {st['median_ms']:.0f}, media {st['mean_ms']}, máx {st['max_ms']}")
    if not any(p["times"] for p in report["phones"]):
        out.append("- sin mediciones")
    out += ["", "## Fotos con veredicto \"no\" (candidatas al set dorado)", ""]
    for p in report["phones"]:
        for ph in p["no_photos"]:
            out.append(f"- {p['name']}: `{ph['png']}`" + ("" if ph["in_zip"] else " (PNG no incluido en el zip)"))
    if not any(p["no_photos"] for p in report["phones"]):
        out.append("- ninguna")
    notes = [f"- {p['name']}: {n}" for p in report["phones"] for n in p["notes"]] + [f"- {e}" for e in report["errors"]]
    if notes:
        out += ["", "## Avisos", "", *notes]
    return "\n".join(out) + "\n"


def extract_dest_problem(dest: Path) -> str | None:
    """Motivo para rechazar ``--extract`` (None si vale): las fotos personales nunca entran en el repo."""
    resolved = dest.expanduser().resolve()
    allowed = (REPO_ROOT / "harness" / "out").resolve()
    if resolved.is_relative_to(REPO_ROOT.resolve()) and not resolved.is_relative_to(allowed):
        return (f"--extract {dest}: está dentro del repo; las fotos viven fuera (p. ej. $COLORSAPP_GOLDEN_DIR), "
                "solo se admite harness/out/ para pruebas")
    return None


def extract_rated(phones: list[PhoneData], dest: Path, log=print) -> int:
    """Copia los PNG de las fotos valoradas a ``dest/<teléfono>_<scan_id>.png`` + feedback-index.csv."""
    dest.mkdir(parents=True, exist_ok=True)
    n = 0
    with (dest / "feedback-index.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["phone", "scan_id", "verdict", "top1", "top2", "top3", "file", *CROP_COLUMNS, "masks"])
        n_masks = 0
        for p in phones:
            for row in latest_feedback(p)[0]:
                sid, verdict = row["scan_id"], row["verdict"]
                if sid not in p.images:
                    continue
                name = f"{p.name}_{sid}.png"
                copies = [(p.images[sid], name)]
                copies += [(member, f"{p.name}_{sid}.{variant}.pgm") for variant, member in sorted(p.masks.get(sid, {}).items())]
                copies += [(member, f"capas/{p.name}_{key}") for key, member in sorted(p.extras.items()) if key.startswith(sid + ".")]
                for (zpath, member), target in copies:
                    (dest / target).parent.mkdir(parents=True, exist_ok=True)
                    with zipfile.ZipFile(zpath) as zf, zf.open(member) as src, (dest / target).open("wb") as dst:
                        shutil.copyfileobj(src, dst)
                fields = crop_fields(row, p.scans.get(sid))
                variants = sorted(p.masks.get(sid, {}))
                w.writerow([p.name, sid, verdict, row["top1"], row["top2"], row["top3"], name, *(fields[c] for c in CROP_COLUMNS),
                            ";".join(variants)])
                n += 1
                n_masks += len(variants)
    log(f"extraídos {n} PNG valorados y {n_masks} máscaras PGM a {dest} (feedback-index.csv)")
    return n


def build_report(paths: list[Path], thresholds_path: Path = DEFAULT_THRESHOLDS, log=print) -> dict[str, Any] | None:
    zips = find_zips(paths)
    if not zips:
        return None
    phones, errors = load_phones(zips, log=log)
    if not phones:
        return None
    phones.sort(key=lambda p: p.name)
    th, defaulted = load_thresholds(thresholds_path)
    summaries = [summarize(p) for p in phones]
    total = summarize(merge_global(phones))
    checks = gate_checks(total, th, defaulted)
    gate_pass = all(c["status"] != "fail" for c in checks)
    return {"schema": 1, "zips": [str(z) for _n, z in zips], "phones": summaries, "total": total, "thresholds": th,
            "thresholds_defaulted": defaulted, "checks": checks, "gate_pass": gate_pass, "errors": errors,
            "_phones": phones}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", type=Path, help="zips exportados por la app o directorios que los contienen")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="directorio de feedback-report.{json,md} (harness/out)")
    ap.add_argument("--thresholds", type=Path, default=DEFAULT_THRESHOLDS)
    ap.add_argument("--extract", type=Path, default=None, help="copia los PNG valorados (fuera del repo) con feedback-index.csv")
    args = ap.parse_args(argv)
    if args.extract is not None and (problem := extract_dest_problem(args.extract)):
        print(f"feedback-report: {problem}", file=sys.stderr)
        return 2
    report = build_report(args.paths, args.thresholds)
    if report is None:
        print(f"feedback-report: ningún zip legible en {', '.join(str(p) for p in args.paths)}", file=sys.stderr)
        return 2
    phones: list[PhoneData] = report.pop("_phones")
    print(render_table([*report["phones"], report["total"]]))
    print()
    for c in report["checks"]:
        print(f"  [{c['status']:>4}] {c['name']}: {c['detail']}")
    if report["thresholds_defaulted"]:
        print(f"  [info] umbrales por defecto (sin sección F10 en {args.thresholds.name}): {', '.join(report['thresholds_defaulted'])}")
    for p in report["phones"]:
        for n in p["notes"]:
            print(f"  [aviso] {p['name']}: {n}")
    for e in report["errors"]:
        print(f"  [aviso] {e}")
    total = report["total"]
    if set(total["by_crop_mode"]) != {NO_CROP_DATA}:
        print("\n" + render_groups(total["by_crop_mode"], "modo de recorte (global)"))
        print("\n" + render_groups(total["by_people"], "personas en la foto (global)"))
        print(f"  valoraciones con otra persona elegida (person_index > 0): {total['person_index_not_largest']}; "
              f"fotos valoradas con máscaras: {total['rated_with_masks']}")
    no_list = [(p["name"], ph) for p in report["phones"] for ph in p["no_photos"]]
    print(f"\nfotos con \"no\": {len(no_list)}" + ("".join(f"\n  {n}: {ph['png']}" + ("" if ph["in_zip"] else " (sin PNG)") for n, ph in no_list[:40])
                                                 + ("\n  …" if len(no_list) > 40 else "")))
    if args.extract is not None:
        extract_rated(phones, args.extract)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / f"{REPORT_STEM}.json").write_text(json.dumps(report, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    (args.out / f"{REPORT_STEM}.md").write_text(render_markdown(report), encoding="utf-8")
    print(f"\nfeedback-report: {'PASS' if report['gate_pass'] else 'FAIL'} (gate F10) · {args.out / (REPORT_STEM + '.json')}, .md")
    return 0 if report["gate_pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
