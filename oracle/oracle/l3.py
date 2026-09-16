"""Capa 3 del harness: match contra el diccionario sobre sintéticos de ``synth.wada_gen``.

    uv run --project oracle python -m oracle.l3 [--fast] [--cli PATH] [--out harness/out]
                                                [--no-golden]

Flujo (sección 6 del plan; la lógica vive aquí para ``oracle.eval`` y ``tests/test_l3_match.py``):

1. **Conjunto dev**: 348 combinaciones x 10 variantes (``wada_gen``, ``seed_base`` 0) en
   ``<out>/synth``; se regenera solo si falta o si cambia ``generator_hash`` (código del
   generador + ``dict_version`` + versiones de numpy/Pillow/opensimplex). ``--fast``: 35
   combinaciones fijas (``fast_combo_ids``, semilla 20260915), todas las variantes, en
   ``<out>/synth_fast`` (o el subconjunto del dev completo si ya está al día).
2. **Match**: una sola invocación de ``ce batch lista.txt ... --json`` por columna:
   ``kL1`` (oficial: opciones por defecto, sin hipótesis de iluminante desde ADR-009),
   ``kL2`` (``--kL 2``), ``skin1`` (``--skin-rule 1``), ``noadapt`` (match v0), ``illum1``
   (defaults + ``--illuminant-search 1``) y ``garments`` (``ce batch --garments``: paleta por
   prenda sin mapa de regiones, porque los sintéticos no tienen pose y la app usa ahí el camino
   clásico); sigma por defecto. Todas salvo kL1 informativas.
   Si el CLI no tiene ``batch`` se cae a un ``ce match`` por imagen. Sin ``match`` la capa es ``not implemented``.
3. **Métricas** (``oracle.metrics``) por grupo de degradación y agregadas: recall@1, recall@3,
   entropía normalizada del top-1 sobre 348 clases, cuota de la clase más frecuente y tasa
   de ``ambiguous``. Umbrales de ``harness/thresholds.json`` sección L3 (solo la columna
   oficial gatea; kL2 y skin1 son informativas): por degradación ``by_degradation`` y
   ``max_class_share_max`` sobre el agregado dev.
4. **Holdout** (variantes 10 y 11 con ``$COLORSAPP_HOLDOUT_SEED``): se regenera siempre en
   ``<out>/synth_holdout`` (nunca se cachea ni se escribe la semilla); cada imagen sigue la
   misma distribución que el dev (una variante 0..9 al azar con la semilla del usuario), así
   que el gate ``holdout >= dev + holdout_minus_dev_min`` (-0,03) en recall@1 y @3 agregados
   mide sobreajuste a las semillas del dev y no la dificultad de otra mezcla; el desglose del
   holdout por degradación subyacente (``holdout_degradation``) se reporta como informativo.
   Sin la variable: check ``skipped`` con motivo (aviso destacado en el scorecard).
5. **Determinismo**: los primeros 20 ficheros se vuelven a pasar por ``ce batch`` y las
   líneas JSON deben ser idénticas.
6. **golden-check** (``oracle.golden``): los goldens de ``harness/golden`` a 1e-9 y mismo
   top-3 (parte de ``make eval``).
7. **Giro de tono** (``oracle.hue_shift``): >= 2000 paletas realistas fuera del diccionario
   (apagados, pasteles, tierras, neutros con un color, sombras de una prenda y, si hay datos,
   ``harness/people``) por ``ce match-palette``; fracción cuyo swatch cromático dominante y el
   color más cercano de la top-1 difieren > 60° en tono cuando con el match v0 no. Gate:
   defaults <= ``L3.hue_shift_max`` (0,01 por defecto hasta que el usuario lo promueva; propuesto
   en ``harness/out/thresholds.proposed.json``); ``+iluminante`` informativo. Mismo conjunto en
   ``--fast`` (unos segundos).

Artefactos: ``<out>/l3_detail.json`` (métricas y resultados por imagen de la columna oficial)
y ``<out>/l3_batch_<columna>.jsonl`` (salida cruda del CLI).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
import time
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import numpy as np

from oracle import metrics as mt
from oracle.l2 import Check, find_cli_optional, load_thresholds
from synth import compose as sc
from synth import wada_gen as wg

REPO_ROOT = Path(__file__).resolve().parents[2]
THRESHOLDS_PATH = REPO_ROOT / "harness" / "thresholds.json"
DEFAULT_OUT = REPO_ROOT / "harness" / "out"
FAST_SEED = 20260915
OFFICIAL = "kL1"
#: Columnas del scorecard: opciones de paleta y de match de cada una.
COLUMNS: dict[str, dict[str, dict[str, Any]]] = {
    "kL1": {"palette": {}, "match": {}},
    "kL2": {"palette": {}, "match": {"kL": 2.0}},
    "skin1": {"palette": {"skin_rule": 1}, "match": {}},
    # Match v0 (fase 3): sin hipótesis de exposición ni de iluminante; informativa, para
    # que el scorecard muestre lo que aporta la búsqueda de hipótesis de la columna oficial.
    "noadapt": {"palette": {}, "match": {"exposure_ev_max": 0.0, "illuminant_search": 0}},
    # Hipótesis de iluminante (defaults hasta ADR-009, 2026-09-15; hoy opción): informativa.
    "illum1": {"palette": {}, "match": {"illuminant_search": 1}},
    # Paleta por prenda (``ce batch --garments``) sin mapa de regiones: los sintéticos de Wada no
    # tienen pose, así que la app usaría el camino clásico; informativa, mide cuánto perdería
    # el camino de prendas con una sola región (máx. 2 colores por región, segundo color >= 25 %).
    "garments": {"palette": {}, "match": {}, "extra": ["--garments"]},
}
TOP_K = 3
DETERMINISM_FILES = 20
BATCH_TIMEOUT = 900.0

#: Valores del contrato de F3 para las claves que falten en thresholds.json (sección L3).
DEFAULTS: dict[str, Any] = {
    "variants_per_combo": 10,
    "max_class_share_max": 0.05,
    "holdout_minus_dev_min": -0.03,
    "fast_combos": 35,
    "eval_fast_seconds_max": 120.0,
    # Giro de tono (oracle.hue_shift): propuesto en harness/out/thresholds.proposed.json, no promovido.
    "hue_shift_max": 0.01,
    "hue_shift_palettes": 2000,
}

#: Opciones por defecto del motor (``ce_match_opts_default``) para validar ``opts.match``.
ENGINE_DEFAULT_MATCH_OPTS: dict[str, float] = {
    "kL": 1.0, "kC": 1.0, "kH": 1.0, "coverage_lambda": 1.0, "ambiguous_gap": 1.0,
    "exposure_ev_max": 1.0, "exposure_penalty": 2.0, "illuminant_search": 0.0, "illuminant_penalty": 2.0,
}


class MatchError(RuntimeError):
    """``ce match``/``ce batch`` devolvió un código inesperado o una salida que no es JSON."""


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------


def _probe_image(tmp: Path) -> Path:
    return sc.write_ppm(np.full((2, 2, 3), 128, dtype=np.uint8), tmp / "probe.ppm")


def _fmt_opt(value: Any) -> str:
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    return repr(float(value))


def match_args(*, palette_opts: dict[str, Any] | None = None, match_opts: dict[str, Any] | None = None,
               top: int = TOP_K) -> list[str]:
    """Flags comunes a ``ce match`` y ``ce batch`` (siempre ``--json`` al final)."""
    args: list[str] = []
    for key, value in (palette_opts or {}).items():
        args += ["--" + key.replace("_", "-"), _fmt_opt(value)]
    for key, value in (match_opts or {}).items():
        flag = {"kL": "--kL", "kC": "--kC", "kH": "--kH"}.get(key, "--" + key.replace("_", "-"))
        args += [flag, _fmt_opt(value)]
    args += ["--top", str(int(top)), "--json"]
    return args


def has_match(cli: Path | None) -> bool:
    """True si ``ce match <2x2.ppm> --top 1 --json`` devuelve 0 y un JSON con ``hits``."""
    if cli is None:
        return False
    with tempfile.TemporaryDirectory(prefix="colorsapp-probe-") as tmp:
        try:
            r = run_match(cli, _probe_image(Path(tmp)), top=1, timeout=30)
        except MatchError:
            return False
    return isinstance(r.get("hits"), list)


def has_batch(cli: Path | None) -> bool:
    """True si ``ce batch lista.txt --json`` responde con una línea JSON con ``hits``."""
    if cli is None:
        return False
    with tempfile.TemporaryDirectory(prefix="colorsapp-probe-") as tmp:
        ppm = _probe_image(Path(tmp))
        try:
            rows = _run_batch_cli(cli, [ppm], [], timeout=30)
        except MatchError:
            return False
    return len(rows) == 1 and isinstance(rows[0].get("hits"), list)


def not_implemented_reason(cli: Path | None) -> str:
    if cli is None:
        return "no existe build/tools/ce (make build) ni $COLORSAPP_CE_CLI"
    return f"{cli} no tiene el subcomando 'match' (fase 3: ce_match.c + ce_cli.c match/analyze/batch)"


def run_match(cli: Path, image: Path, *, palette_opts: dict[str, Any] | None = None,
              match_opts: dict[str, Any] | None = None, top: int = TOP_K, timeout: float = 120.0,
              subcommand: str = "match") -> dict[str, Any]:
    """``ce match`` (o ``analyze``) sobre una imagen; JSON parseado con ``_stdout`` añadido."""
    args = [subcommand, str(image), *match_args(palette_opts=palette_opts, match_opts=match_opts, top=top)]
    try:
        proc = subprocess.run([str(cli), *args], capture_output=True, text=True, check=False, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise MatchError(f"ce {subcommand}: timeout de {timeout:.0f} s") from exc
    if proc.returncode != 0:
        raise MatchError(f"ce {' '.join(args)} -> exit {proc.returncode}: {proc.stderr.strip()[:300]}")
    try:
        result = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise MatchError(f"ce {subcommand}: stdout no es JSON ({exc}): {proc.stdout[:200]!r}") from exc
    if not isinstance(result, dict):
        raise MatchError(f"ce {subcommand}: el JSON no es un objeto")
    result["_stdout"] = proc.stdout
    return result


def _run_batch_cli(cli: Path, files: list[Path], args: list[str], timeout: float = BATCH_TIMEOUT) -> list[dict[str, Any]]:
    """Una invocación de ``ce batch``; devuelve una fila por línea JSON (``_line`` = texto crudo)."""
    with tempfile.TemporaryDirectory(prefix="colorsapp-batch-") as tmp:
        listing = Path(tmp) / "list.txt"
        listing.write_text("".join(f"{p}\n" for p in files), encoding="utf-8")
        cmd = [str(cli), "batch", str(listing), *args, "--json"]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            raise MatchError(f"ce batch: timeout de {timeout:.0f} s") from exc
    if proc.returncode not in (0, 1):
        raise MatchError(f"ce batch -> exit {proc.returncode}: {proc.stderr.strip()[:300]}")
    rows: list[dict[str, Any]] = []
    for line in proc.stdout.splitlines():
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            raise MatchError(f"ce batch: línea que no es JSON ({exc}): {line[:200]!r}") from exc
        if not isinstance(obj, dict):
            raise MatchError("ce batch: una línea no es un objeto JSON")
        obj["_line"] = line
        rows.append(obj)
    if len(rows) != len(files):
        raise MatchError(f"ce batch: {len(rows)} líneas para {len(files)} ficheros (exit {proc.returncode})")
    return rows


def run_batch(cli: Path, files: list[Path], *, palette_opts: dict[str, Any] | None = None,
              match_opts: dict[str, Any] | None = None, top: int = TOP_K, use_batch: bool | None = None,
              timeout: float = BATCH_TIMEOUT, extra_args: list[str] | None = None) -> list[dict[str, Any]]:
    """Resultados de match para ``files`` en orden: ``ce batch`` (una invocación) o, si no existe,
    ``ce match`` por fichero. Un fichero ilegible produce ``{"file", "error"}`` sin abortar.
    ``extra_args`` (p. ej. ``["--garments"]``) solo con ``ce batch``; sin él, cada fichero da error."""
    if use_batch is None:
        use_batch = has_batch(cli)
    common = match_args(palette_opts=palette_opts, match_opts=match_opts, top=top)[:-1]  # sin --json
    if extra_args:
        if not use_batch:
            return [{"file": str(p), "error": f"{' '.join(extra_args)} exige ce batch", "_line": ""} for p in files]
        try:
            return _run_batch_cli(cli, files, [*extra_args, *common], timeout=timeout)
        except MatchError as exc:
            return [{"file": str(p), "error": str(exc), "_line": ""} for p in files]
    if use_batch:
        return _run_batch_cli(cli, files, common, timeout=timeout)
    rows: list[dict[str, Any]] = []
    for p in files:
        try:
            r = run_match(cli, p, palette_opts=palette_opts, match_opts=match_opts, top=top)
            r["_line"] = r.pop("_stdout").strip()
            r.setdefault("file", str(p))
            rows.append(r)
        except MatchError as exc:
            rows.append({"file": str(p), "error": str(exc), "_line": ""})
    return rows


# --------------------------------------------------------------------------------------
# Contrato del JSON de match
# --------------------------------------------------------------------------------------

_HEX12 = re.compile(r"^[0-9a-f]{12}$")
_HEX16 = re.compile(r"^[0-9a-f]{16}$")


def validate_match_result(r: dict[str, Any], top: int = TOP_K, n_combos: int = wg.N_COMBOS) -> list[str]:
    """Problemas del JSON de ``ce match``/``batch`` respecto al contrato (lista vacía = conforme)."""
    problems: list[str] = []
    if "error" in r:
        return [f"error del CLI: {r['error']}"]
    for key in ("engine", "dict_version", "width", "height", "reduced_width", "reduced_height", "opts",
                "swatches", "hits", "ambiguous", "hash"):
        if key not in r:
            problems.append(f"falta la clave {key!r}")
    if problems:
        return problems
    if not (isinstance(r["dict_version"], str) and _HEX12.match(r["dict_version"])):
        problems.append(f"dict_version {r['dict_version']!r} no es 12 hex")
    if not (isinstance(r["hash"], str) and _HEX16.match(r["hash"])):
        problems.append(f"hash {r['hash']!r} no es 16 hex")
    opts = r["opts"]
    if not (isinstance(opts, dict) and isinstance(opts.get("palette"), dict) and isinstance(opts.get("match"), dict)):
        problems.append("opts debe tener 'palette' y 'match'")
    else:
        missing = [k for k in ENGINE_DEFAULT_MATCH_OPTS if k not in opts["match"]]
        if missing:
            problems.append(f"opts.match sin {missing}")
    sw = r["swatches"]
    if not (isinstance(sw, list) and 1 <= len(sw) <= 8):
        problems.append("swatches: se esperaban 1..8")
    else:
        total = sum(float(s.get("weight", 0.0)) for s in sw)
        if abs(total - 1.0) > 1e-12:
            problems.append(f"sum(weight) = {total!r}")
    if r["ambiguous"] not in (0, 1):
        problems.append(f"ambiguous {r['ambiguous']!r} no es 0|1")
    hits = r["hits"]
    if not (isinstance(hits, list) and 1 <= len(hits) <= top):
        problems.append(f"hits: {len(hits) if isinstance(hits, list) else type(hits).__name__} (esperaba 1..{top})")
        return problems
    prev: float | None = None
    prev_id = 0
    for i, h in enumerate(hits):
        for key in ("id", "score", "size", "colors"):
            if key not in h:
                problems.append(f"hit {i}: falta {key!r}")
        if any(k not in h for k in ("id", "score", "size", "colors")):
            continue
        if not (isinstance(h["id"], int) and 1 <= h["id"] <= n_combos):
            problems.append(f"hit {i}: id {h['id']!r} fuera de 1..{n_combos}")
        s = h["score"]
        if not (isinstance(s, (int, float)) and np.isfinite(s) and s >= 0.0):
            problems.append(f"hit {i}: score inválido {s!r}")
            continue
        if prev is not None and (s < prev or (s == prev and h["id"] <= prev_id)):
            problems.append(f"hit {i}: orden (score asc, id asc) roto: {s} / id {h['id']} tras {prev} / id {prev_id}")
        prev, prev_id = float(s), int(h["id"]) if isinstance(h["id"], int) else prev_id
        if not (isinstance(h["colors"], list) and len(h["colors"]) == h["size"] and 2 <= h["size"] <= 7):
            problems.append(f"hit {i}: size {h['size']!r} / colors {h['colors']!r} incoherentes")
    if len(hits) >= 2 and isinstance(hits[0].get("score"), (int, float)) and isinstance(hits[1].get("score"), (int, float)):
        gap = float(opts["match"].get("ambiguous_gap", 1.0)) if isinstance(opts, dict) and isinstance(opts.get("match"), dict) else 1.0
        expected = 1 if (hits[1]["score"] - hits[0]["score"]) < gap else 0
        if r["ambiguous"] != expected:
            problems.append(f"ambiguous {r['ambiguous']} != {expected} (gap {hits[1]['score'] - hits[0]['score']:.4g} vs {gap})")
    return problems


def ranked_ids(r: dict[str, Any]) -> list[int]:
    if "error" in r or not isinstance(r.get("hits"), list):
        return []
    return [int(h["id"]) for h in r["hits"] if isinstance(h, dict) and "id" in h]


# --------------------------------------------------------------------------------------
# Métricas
# --------------------------------------------------------------------------------------


def metrics_for(truth: list[int], results: list[dict[str, Any]]) -> dict[str, Any]:
    """recall@1/@3, entropía normalizada del top-1, cuota máxima, tasa de ambiguous y errores."""
    ranked = [ranked_ids(r) for r in results]
    top1 = [r[0] for r in ranked if r]
    n = len(truth)
    errors = sum(1 for r in results if "error" in r or not ranked_ids(r))
    ambiguous = sum(1 for r in results if r.get("ambiguous") == 1)
    shares = mt.class_shares(top1)
    top_class = next(iter(shares), None)
    return {
        "n": n,
        "errors": errors,
        "recall_at_1": mt.recall_at_k(truth, ranked, 1) if n else 0.0,
        "recall_at_3": mt.recall_at_k(truth, ranked, 3) if n else 0.0,
        "entropy_norm": mt.entropy(top1, n_classes=wg.N_COMBOS) if top1 else 0.0,
        "max_class_share": mt.max_class_share(top1) if top1 else 0.0,
        "max_class_id": top_class,
        "coverage": mt.coverage(top1, wg.N_COMBOS) if top1 else 0.0,
        "ambiguous_rate": ambiguous / n if n else 0.0,
    }


def evaluate(rows: list[dict[str, Any]], results: list[dict[str, Any]]) -> dict[str, Any]:
    """Métricas por grupo de degradación (``row["degradation"]``) y agregadas para una columna."""
    if len(rows) != len(results):
        raise ValueError(f"{len(rows)} filas del manifest y {len(results)} resultados")
    groups: dict[str, tuple[list[int], list[dict[str, Any]]]] = {}
    for row, res in zip(rows, results):
        g = groups.setdefault(str(row["degradation"]), ([], []))
        g[0].append(int(row["combo_id"]))
        g[1].append(res)
    order = [g for g in (*wg.DEGRADATION_GROUPS, "holdout") if g in groups] + sorted(g for g in groups if g not in wg.DEGRADATION_GROUPS and g != "holdout")
    by_group = {g: metrics_for(*groups[g]) for g in order}
    aggregate = metrics_for([int(r["combo_id"]) for r in rows], results)
    confusions = Counter(
        (int(row["combo_id"]), ranked_ids(res)[0]) for row, res in zip(rows, results)
        if ranked_ids(res) and ranked_ids(res)[0] != int(row["combo_id"])
    )
    return {
        "by_group": by_group,
        "aggregate": aggregate,
        "top_confusions": [{"truth": t, "pred": p, "n": n} for (t, p), n in confusions.most_common(15)],
    }


# --------------------------------------------------------------------------------------
# Umbrales y conjuntos
# --------------------------------------------------------------------------------------


def resolve_thresholds(thresholds: dict[str, Any] | None) -> tuple[dict[str, Any], list[str]]:
    """Valores de la sección L3 con los defaults del contrato para las claves ausentes."""
    section = (thresholds or {}).get("L3", {}) if thresholds else {}
    values: dict[str, Any] = {}
    defaulted: list[str] = []
    for key, default in DEFAULTS.items():
        if isinstance(section, dict) and key in section:
            values[key] = section[key]
        else:
            values[key] = default
            defaulted.append(key)
    values["by_degradation"] = dict((section or {}).get("by_degradation", {})) if isinstance(section, dict) else {}
    return values, defaulted


def fast_combo_ids(n: int = DEFAULTS["fast_combos"], seed: int = FAST_SEED) -> list[int]:
    """Las ``n`` combinaciones fijas del modo rápido (muestra sin reemplazo con semilla fija)."""
    ids = wg.combo_ids()
    rng = np.random.default_rng(int(seed))
    return sorted(int(i) for i in rng.choice(ids, size=min(int(n), len(ids)), replace=False))


def ensure_dev_set(out_root: Path, fast: bool, n_fast: int = DEFAULTS["fast_combos"], log=print) -> tuple[Path, dict[str, Any], list[dict[str, Any]], float]:
    """Directorio, meta y filas del conjunto dev (cacheado por ``generator_hash``); segundos de generación."""
    variants = list(wg.DEV_VARIANTS)
    full_dir = out_root / "synth"
    seconds = 0.0
    if fast:
        combos = fast_combo_ids(n_fast)
        if wg.set_is_current(full_dir, variants):
            meta, rows = wg.read_manifest(full_dir / "manifest.jsonl")
            wanted = set(combos)
            return full_dir, meta, [r for r in rows if int(r["combo_id"]) in wanted], seconds
        target = out_root / "synth_fast"
    else:
        combos = None
        target = full_dir
    if not wg.set_is_current(target, variants, combos):
        log(f"  wada_gen: generando {'35 combinaciones' if fast else '348 combinaciones'} x {len(variants)} variantes en {target} ...")
        t0 = time.perf_counter()
        wg.generate_set(target, variants, combos, seed_base=0, log=log)
        seconds = round(time.perf_counter() - t0, 1)
        log(f"  wada_gen: listo en {seconds} s")
    meta, rows = wg.read_manifest(target / "manifest.jsonl")
    return target, meta, rows, seconds


def ensure_holdout_set(out_root: Path, seed_base: int, combos: list[int] | None, log=print) -> tuple[Path, list[dict[str, Any]], float]:
    """Genera (siempre, sin caché) las variantes 10 y 11 con la semilla del usuario en ``<out>/synth_holdout``."""
    target = out_root / "synth_holdout"
    t0 = time.perf_counter()
    wg.generate_set(target, list(wg.HOLDOUT_VARIANTS), combos, seed_base=int(seed_base), log=log)
    _meta, rows = wg.read_manifest(target / "manifest.jsonl")
    return target, rows, round(time.perf_counter() - t0, 1)


# --------------------------------------------------------------------------------------
# Capa completa
# --------------------------------------------------------------------------------------


def _pct(x: float) -> str:
    return f"{100.0 * float(x):.1f} %"


def _run_column(cli: Path, files: list[Path], column: str, use_batch: bool, out_dir: Path | None) -> tuple[list[dict[str, Any]], float]:
    spec = COLUMNS[column]
    t0 = time.perf_counter()
    results = run_batch(cli, files, palette_opts=spec["palette"], match_opts=spec["match"], use_batch=use_batch,
                        extra_args=spec.get("extra"))
    seconds = round(time.perf_counter() - t0, 2)
    if out_dir is not None:
        (out_dir / f"l3_batch_{column}.jsonl").write_text("".join(r["_line"] + "\n" for r in results), encoding="utf-8")
    return results, seconds


def render_table(detail: dict[str, Any]) -> str:
    """Tabla Markdown por degradación y columna (kL=1 oficial; kL=2 y skin=1 informativas)."""
    cols = [c for c in COLUMNS if c in detail["columns"]]
    head = "| Degradación | n | " + " | ".join(f"{c} r@1 | {c} r@3" for c in cols) + " | kL1 ambiguous |"
    sep = "|---|---:|" + "---:|---:|" * len(cols) + "---:|"
    lines = [head, sep]

    def row(label: str, key: str, section: str) -> None:
        cells = []
        n = None
        amb = None
        for c in cols:
            block = detail["columns"][c][section]
            m = block["by_group"].get(key) if section != "aggregate_only" else None
            m = block["aggregate"] if key == "__aggregate__" else m
            if m is None:
                cells += ["—", "—"]
                continue
            n = m["n"]
            cells += [_pct(m["recall_at_1"]), _pct(m["recall_at_3"])]
            if c == OFFICIAL:
                amb = _pct(m["ambiguous_rate"])
        lines.append(f"| {label} | {n if n is not None else '—'} | " + " | ".join(cells) + f" | {amb or '—'} |")

    dev_groups = list(detail["columns"][OFFICIAL]["dev"]["by_group"])
    for g in dev_groups:
        row(f"dev {g}", g, "dev")
    row("**dev agregado**", "__aggregate__", "dev")
    if detail.get("holdout", {}).get("status") == "run":
        row("**holdout agregado (v10-11, misma distribución que el dev)**", "__aggregate__", "holdout")
        h_by_deg = detail["columns"][OFFICIAL].get("holdout_by_degradation") or {}
        for g, m in h_by_deg.items():
            cells = " | ".join([_pct(m["recall_at_1"]), _pct(m["recall_at_3"])] + ["—", "—"] * (len(cols) - 1))
            lines.append(f"| holdout {g} (kL1, informativo) | {m['n']} | {cells} | {_pct(m['ambiguous_rate'])} |")
    agg = detail["columns"][OFFICIAL]["dev"]["aggregate"]
    lines.append("")
    lines.append(
        f"kL1 dev: entropía normalizada del top-1 {agg['entropy_norm']:.3f}; cuota máxima {_pct(agg['max_class_share'])}"
        f" (combo {agg['max_class_id']}); cobertura {_pct(agg['coverage'])}; errores del CLI {agg['errors']}."
    )
    return "\n".join(lines)


def run_layer3(cli: Path, thresholds: dict[str, Any] | None, out_dir: Path | None, fast: bool,
               with_golden: bool = True, columns: tuple[str, ...] = tuple(COLUMNS), log=print) -> tuple[list[Check], dict[str, Any], str]:
    """Ejecuta la capa 3 y devuelve (checks, detalle, tabla Markdown). Escribe ``<out>/l3_detail.json``."""
    th, defaulted = resolve_thresholds(thresholds)
    started = time.perf_counter()
    out_root = out_dir if out_dir is not None else Path(tempfile.mkdtemp(prefix="colorsapp-l3-"))
    out_root.mkdir(parents=True, exist_ok=True)
    checks: list[Check] = []

    def add(check: Check) -> Check:
        checks.append(check)
        log(f"  [{check.status:>7}] {check.name}" + (f" ({check.seconds:.1f}s)" if check.seconds else "")
            + (f": {check.detail.splitlines()[0]}" if check.status in ("skipped", "info") and check.detail else ""))
        if check.status == "fail":
            log("           " + check.detail.replace("\n", "\n           "))
        return check

    # 1. Conjunto dev
    set_dir, meta, rows, gen_seconds = ensure_dev_set(out_root, fast, int(th["fast_combos"]), log=log)
    files = [set_dir / r["file"] for r in rows]
    n_combos = len({int(r["combo_id"]) for r in rows})
    detail: dict[str, Any] = {
        "cli": str(cli), "mode": "fast" if fast else "full", "set_dir": str(set_dir), "generator_hash": meta.get("generator_hash"),
        "dict_version": meta.get("dict_version"), "n_images": len(rows), "n_combos": n_combos,
        "variants": meta.get("variants"), "generation_seconds": gen_seconds, "thresholds": th, "thresholds_defaulted": defaulted,
        "columns": {},
    }
    engine_dict = subprocess.run([str(cli), "dict", "--version"], capture_output=True, text=True, check=False).stdout.strip()
    add(Check("dict_version: ce dict --version == generador (dictionary.json)",
              "pass" if engine_dict == meta.get("dict_version") else "fail",
              f"motor {engine_dict!r}, generador {meta.get('dict_version')!r}; generator_hash {meta.get('generator_hash')}; "
              f"{len(rows)} imágenes de {n_combos} combinaciones x {len(meta.get('variants') or [])} variantes en {set_dir}"
              + (f" (generadas en {gen_seconds} s)" if gen_seconds else " (caché)"), value=engine_dict))

    # 2. Match por columna
    use_batch = has_batch(cli)
    results: dict[str, list[dict[str, Any]]] = {}
    for column in columns:
        res, seconds = _run_column(cli, files, column, use_batch, out_root)
        results[column] = res
        detail["columns"][column] = {"opts": COLUMNS[column], "seconds": seconds, "dev": evaluate(rows, res)}
        log(f"  columna {column}: {len(res)} resultados en {seconds} s ({'ce batch' if use_batch else 'ce match por imagen'})")
    official = results[OFFICIAL]
    dev = detail["columns"][OFFICIAL]["dev"]

    # 3. Contrato
    problems: list[str] = []
    for r, row in zip(official, rows):
        for p in validate_match_result(r, TOP_K):
            problems.append(f"{row['file']}: {p}")
    answered = len(official)
    add(Check("contrato JSON de ce batch/match (claves, opts.palette/match, hits ordenados por score asc e id, ambiguous coherente, hash 16 hex)",
              "pass" if not problems else "fail",
              f"{answered} resultados validados; problemas: {len(problems)}" + ("\n" + "\n".join(problems[:10]) if problems else ""),
              value=len(problems), threshold=0))

    # 4. Umbrales por degradación (columna oficial)
    for group, gates in th["by_degradation"].items():
        m = dev["by_group"].get(group)
        for key, minimum in gates.items():
            k = 1 if key.endswith("_1_min") else 3
            if m is None:
                add(Check(f"{group}: recall@{k} >= {minimum} (kL=1)", "fail", f"sin imágenes del grupo {group!r} en el conjunto", threshold=minimum))
                continue
            value = float(m[f"recall_at_{k}"])
            add(Check(f"{group}: recall@{k} >= {minimum} (kL=1)", "pass" if value >= float(minimum) else "fail",
                      f"{_pct(value)} sobre {m['n']} imágenes (recall@1 {_pct(m['recall_at_1'])}, @3 {_pct(m['recall_at_3'])}, "
                      f"ambiguous {_pct(m['ambiguous_rate'])}, errores {m['errors']})", value=value, threshold=float(minimum)))
    agg = dev["aggregate"]
    add(Check(f"cuota de la clase más frecuente (top-1, dev agregado) <= {th['max_class_share_max']} (kL=1)",
              "pass" if float(agg["max_class_share"]) <= float(th["max_class_share_max"]) else "fail",
              f"{_pct(agg['max_class_share'])} (combo {agg['max_class_id']}); entropía normalizada {agg['entropy_norm']:.3f}; cobertura {_pct(agg['coverage'])}",
              value=float(agg["max_class_share"]), threshold=float(th["max_class_share_max"])))
    add(Check("dev agregado kL=1 (informativo)", "info",
              f"recall@1 {_pct(agg['recall_at_1'])}, recall@3 {_pct(agg['recall_at_3'])}, ambiguous {_pct(agg['ambiguous_rate'])}, "
              f"{agg['n']} imágenes; grupos sin umbral: "
              + ", ".join(f"{g} @1 {_pct(m['recall_at_1'])}/@3 {_pct(m['recall_at_3'])}" for g, m in dev["by_group"].items() if g not in th["by_degradation"]),
              value=float(agg["recall_at_1"])))
    for column in columns:
        if column == OFFICIAL:
            continue
        a = detail["columns"][column]["dev"]["aggregate"]
        add(Check(f"columna {column} (informativa: {COLUMNS[column]})", "info",
                  f"recall@1 {_pct(a['recall_at_1'])}, recall@3 {_pct(a['recall_at_3'])}, ambiguous {_pct(a['ambiguous_rate'])}, cuota máxima {_pct(a['max_class_share'])}",
                  value=float(a["recall_at_1"])))

    # 4b. Giro de tono (paletas realistas fuera del diccionario, sin imágenes)
    from oracle import hue_shift

    t_hs = time.perf_counter()
    try:
        hs = hue_shift.evaluate(cli, n=int(th["hue_shift_palettes"]), log=log)
    except hue_shift.HueShiftError as exc:
        detail["hue_shift"] = {"error": str(exc)}
        add(Check(f"giro de tono (defaults) <= {th['hue_shift_max']}", "fail", str(exc), threshold=float(th["hue_shift_max"])))
    else:
        detail["hue_shift"] = hs
        if out_dir is not None:
            (out_dir / "hue_shift.json").write_text(json.dumps(hs, indent=1, ensure_ascii=False, default=float) + "\n", encoding="utf-8")
        seconds_hs = round(time.perf_counter() - t_hs, 1)
        for name in hue_shift.REPORTED:
            c = hs["configs"][name]
            fams = ", ".join(f"{f} {_pct(m['rate'])}" for f, m in c["by_family"].items())
            text = (f"{_pct(c['hue_shift_rate'])} ({c['hue_shift_count']}/{hs['n_evaluated']} paletas con swatch cromático; "
                    f"{hs['n_palettes']} fuera del diccionario, {hs['people'].get('palettes', 0)} de harness/people); "
                    f"top-1 distinto de v0 {_pct(c['top1_changed_vs_v0'])}; por familia: {fams}")
            if name == "defaults":
                add(Check(f"giro de tono > {hue_shift.HUE_SHIFT_DEG:.0f}° (defaults, respecto a v0) <= {th['hue_shift_max']}",
                          "pass" if float(c["hue_shift_rate"]) <= float(th["hue_shift_max"]) else "fail", text,
                          value=float(c["hue_shift_rate"]), threshold=float(th["hue_shift_max"]), seconds=seconds_hs))
            else:
                add(Check(f"giro de tono con {name} (informativo: {hue_shift.CONFIGS[name]})", "info", text,
                          value=float(c["hue_shift_rate"])))

    # 5. Determinismo
    n_det = min(DETERMINISM_FILES, len(files))
    again = run_batch(cli, files[:n_det], palette_opts=COLUMNS[OFFICIAL]["palette"], match_opts=COLUMNS[OFFICIAL]["match"], use_batch=use_batch)
    differing = [rows[i]["file"] for i in range(n_det) if again[i]["_line"] != official[i]["_line"]]
    add(Check(f"determinismo ({n_det} imágenes): segunda pasada de ce batch -> líneas JSON idénticas (mismo hash)",
              "pass" if not differing else "fail", f"{n_det - len(differing)}/{n_det} idénticas" + (f"; distintas: {differing[:6]}" if differing else ""),
              value=len(differing), threshold=0))

    # 6. Holdout
    seed_base = wg.holdout_seed_base()
    if seed_base is None:
        detail["holdout"] = {"status": "skipped", "reason": f"sin {wg.HOLDOUT_SEED_ENV}"}
        add(Check("holdout (variantes 10-11 con COLORSAPP_HOLDOUT_SEED)", "skipped",
                  f"sin {wg.HOLDOUT_SEED_ENV}: solo el usuario la exporta al ejecutar make eval; el gate holdout >= dev {th['holdout_minus_dev_min']:+.2f} no se evalúa"))
    else:
        combos = sorted({int(r["combo_id"]) for r in rows}) if fast else None
        h_dir, h_rows, h_seconds = ensure_holdout_set(out_root, seed_base, combos, log=log)
        h_files = [h_dir / r["file"] for r in h_rows]
        h_res, h_batch_seconds = _run_column(cli, h_files, OFFICIAL, use_batch, None)
        h_eval = evaluate(h_rows, h_res)
        detail["columns"][OFFICIAL]["holdout"] = h_eval
        for column in columns:
            if column == OFFICIAL:
                continue
            c_res, _ = _run_column(cli, h_files, column, use_batch, None)
            detail["columns"][column]["holdout"] = evaluate(h_rows, c_res)
        # Desglose informativo por la degradación subyacente de cada imagen del holdout
        # (misma distribución que el dev: comparable grupo a grupo con la tabla dev).
        h_by_deg = evaluate([{**r, "degradation": r.get("holdout_degradation", "holdout")} for r in h_rows], h_res)["by_group"]
        detail["columns"][OFFICIAL]["holdout_by_degradation"] = h_by_deg
        detail["holdout"] = {"status": "run", "n_images": len(h_rows), "generation_seconds": h_seconds, "batch_seconds": h_batch_seconds}
        ha = h_eval["aggregate"]
        gap = float(th["holdout_minus_dev_min"])
        for k in (1, 3):
            hv, dv = float(ha[f"recall_at_{k}"]), float(agg[f"recall_at_{k}"])
            add(Check(f"holdout recall@{k} >= dev recall@{k} {gap:+.2f} (kL=1)", "pass" if hv >= dv + gap else "fail",
                      f"holdout {_pct(hv)} vs dev {_pct(dv)} ({len(h_rows)} imágenes de holdout, una variante 0..9 al azar por imagen "
                      "con la semilla del usuario: misma distribución que el dev)",
                      value=hv, threshold=dv + gap))
        add(Check("holdout kL=1 (informativo)", "info",
                  f"ambiguous {_pct(ha['ambiguous_rate'])}, cuota máxima {_pct(ha['max_class_share'])}, entropía {ha['entropy_norm']:.3f}, errores {ha['errors']}; "
                  "por degradación subyacente (r@1/r@3, n): "
                  + ", ".join(f"{g} {_pct(m['recall_at_1'])}/{_pct(m['recall_at_3'])} ({m['n']})" for g, m in h_by_deg.items()),
                  value=float(ha["recall_at_1"])))

    # 7. Goldens
    if with_golden:
        from oracle import golden

        t0 = time.perf_counter()
        ok, summary, g_detail = golden.check(cli)
        detail["golden"] = g_detail
        add(Check("golden-check (harness/golden: paletas y matches a 1e-9, mismo top-3)", "pass" if ok else "fail", summary,
                  value=g_detail.get("mismatches"), threshold=0, seconds=round(time.perf_counter() - t0, 3)))

    if defaulted:
        add(Check("umbrales L3 con valores por defecto (no promovidos en thresholds.json)", "info",
                  ", ".join(f"{k}={th[k]}" for k in defaulted), value=len(defaulted)))
    detail["seconds"] = round(time.perf_counter() - started, 1)
    detail["per_image"] = [
        {"file": row["file"], "combo_id": row["combo_id"], "v": row["v"], "degradation": row["degradation"],
         "top": ranked_ids(res), "scores": [h.get("score") for h in res.get("hits", [])] if "error" not in res else None,
         "ambiguous": res.get("ambiguous"), "error": res.get("error")}
        for row, res in zip(rows, official)
    ]
    table = render_table(detail)
    if out_dir is not None:
        (out_dir / "l3_detail.json").write_text(json.dumps(detail, indent=1, ensure_ascii=False, default=_json_default) + "\n", encoding="utf-8")
        (out_dir / "l3_table.md").write_text(table + "\n", encoding="utf-8")
    return checks, detail, table


def _json_default(obj: Any) -> Any:
    if isinstance(obj, (np.floating, np.integer)):
        return obj.item()
    if isinstance(obj, np.ndarray):
        return obj.tolist()
    if isinstance(obj, Path):
        return str(obj)
    if isinstance(obj, float) and not np.isfinite(obj):
        return None
    raise TypeError(f"no serializable: {type(obj).__name__}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fast", action="store_true", help="35 combinaciones fijas x 10 variantes")
    ap.add_argument("--cli", type=str, default=None, help="ruta a 'ce' (por defecto build/tools/ce o $COLORSAPP_CE_CLI)")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="directorio de artefactos (harness/out)")
    ap.add_argument("--no-golden", action="store_true", help="no ejecutar golden-check")
    args = ap.parse_args(argv)
    cli = find_cli_optional(args.cli)
    if not has_match(cli):
        print(f"L3: not implemented ({not_implemented_reason(cli)})")
        return 1
    print(f"L3 match contra el diccionario ({'fast' if args.fast else 'completo'}) con {cli}")
    checks, detail, table = run_layer3(cli, load_thresholds(), args.out, args.fast, with_golden=not args.no_golden)
    print("")
    print(table)
    failed = [c for c in checks if c.status == "fail"]
    skipped = [c for c in checks if c.status == "skipped"]
    print("")
    print(f"L3: {'FAIL' if failed else 'OK'} ({len(checks) - len(failed)}/{len(checks)} checks; {detail['seconds']} s)"
          + (f"; SKIPPED: {'; '.join(c.name + ' -> ' + c.detail.splitlines()[0] for c in skipped)}" if skipped else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
