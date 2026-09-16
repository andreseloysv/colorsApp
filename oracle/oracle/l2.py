"""Capa 2 del harness: extracción de paleta (``ce palette``) sobre composiciones sintéticas.

    uv run --project oracle python -m oracle.l2 [--fast] [--cli PATH] [--out harness/out]
                                                [--compositions N] [--invariances M]

La lógica de esta capa vive aquí para que la usen ``oracle.eval`` (scorecard) y
``tests/test_l2_palette.py`` (pytest) sin duplicarla. Dos bloques (sección 6 del plan):

(a) **Composiciones**: ``N`` composiciones de ``synth.compose`` (mitad por layout,
    semillas 1..N) -> ``ce palette img.ppm --center-sigma 0 --json`` (peso uniforme, así
    el peso de cada swatch debe ser su área) -> emparejamiento óptimo verdad <-> swatch
    (``scipy.optimize.linear_sum_assignment`` sobre ΔE00) -> cada color de la verdad
    tiene un swatch con ΔE00 < ``color_de00_max`` y |weight - area| <=
    ``weight_abs_error_max``. Además se ejecuta con el sigma por defecto solo a título
    informativo (ahí el peso al centro no coincide con el área por diseño).

(b) **Invariancias** sobre ``M`` composiciones (semillas 1001..1000+M), en modo uniforme:
    barajado de píxeles -> lab y weight bit-idénticos, mismo hash y JSON byte a byte (y con
    el sigma por defecto, mismo conjunto con ΔE00 < 1); escala 0,5x y 2x -> ΔE00 < 1 por color
    emparejado; espejo y rotación 180° -> ΔE00 < 0,5; ruido gaussiano sigma = 2 ->
    ΔE00 < 1,5; dos ejecuciones -> mismo hash y mismo JSON.

(c) **Prendas** (``oracle.garments``, paleta por prenda de ``ce batch --garments``): 170
    composiciones de una figura sombreada (liso, rayas, vestido, sombras duras, dos prendas de
    tono cercano, sombra proyectada contigua, sombra abierta de exterior que AZULEA, estampado
    oscuro + motivo claro con esa sombra, degradado de color, y las informativas bicolor tonal y
    banda de fusión) con mapa de regiones arriba/abajo: colores exactos por prenda, ΔE00 al tono
    iluminado verdadero, fusiones erróneas, vestidos sin fusionar, prendas lisas partidas en dos
    por una sombra (proyectada o azul), estampados que pierden el motivo y degradados colapsados.
    Umbrales en
    ``L2.garments`` (propuestos en ``harness/out/thresholds.proposed.json``, sección
    ``L2_garments``). Si el CLI no tiene ``garments`` el bloque queda ``skipped``.

Los umbrales salen de ``harness/thresholds.json`` (sección ``L2``); si falta una clave se
usa el valor del contrato de la fase 2 (``DEFAULTS``) y el scorecard lo anota como default
no promovido. ``--fast``: 40 composiciones y 8 invariancias (debe tardar < 60 s).

Si el CLI no tiene el subcomando ``palette`` (``has_palette``), la capa queda
``not implemented`` con el motivo. El ejecutable se busca en ``build/tools/ce`` o en la
variable de entorno ``COLORSAPP_CE_CLI``.

Artefactos: ``<out>/l2_detail.json`` (métricas por composición) y, para las composiciones
que fallan, ``<out>/l2/fail/`` con el PPM y el JSON devuelto (máx. 25).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import numpy as np
from scipy.optimize import linear_sum_assignment

from oracle import reference as ref
from synth import compose as sc

REPO_ROOT = Path(__file__).resolve().parents[2]
THRESHOLDS_PATH = REPO_ROOT / "harness" / "thresholds.json"
DEFAULT_OUT = REPO_ROOT / "harness" / "out"
CLI_ENV = "COLORSAPP_CE_CLI"
MAX_FAIL_ARTIFACTS = 25
INVARIANCE_SEED_BASE = 1000

#: Valores del contrato de F2 para las claves que falten en thresholds.json (sección L2).
DEFAULTS: dict[str, Any] = {
    "compositions": 200,
    "compositions_fast": 40,
    "invariance_compositions": 30,
    "invariance_compositions_fast": 8,
    "color_de00_max": 2.0,
    "weight_abs_error_max": 0.03,
    "invariance.shuffle_uniform": "bit-identical",
    "invariance.shuffle_center_weighted_de00_max": 1.0,
    "invariance.scale_de00_max": 1.0,
    "invariance.mirror_rotate_de00_max": 0.5,
    "invariance.noise_sigma2_de00_max": 1.5,
    "invariance.rerun": "same-hash",
    "l2_fast_seconds_max": 60.0,
}

#: Opciones por defecto del motor (``ce_palette_opts_default``), para validar ``opts``.
ENGINE_DEFAULT_OPTS: dict[str, Any] = {
    "k_init": 6, "max_iters": 20, "max_colors": 5, "max_side": 256,
    "center_sigma": 0.35, "merge_de": 5.0, "min_weight": 0.05, "skin_rule": 0,
}


@dataclass
class Check:
    """Mismo esquema que ``oracle.eval.Check``: status pass | fail | skipped | info."""

    name: str
    status: str
    detail: str = ""
    value: Any = None
    threshold: Any = None
    seconds: float | None = None


class PaletteError(RuntimeError):
    """``ce palette`` devolvió un código distinto de 0 o una salida que no es JSON."""


def _fmt(x: float) -> str:
    """ΔE / error de peso legible: notación científica por debajo de 1e-3 (p. ej. 8.2e-14), si no 3 decimales."""
    x = float(x)
    if not np.isfinite(x):
        return str(x)
    return f"{x:.3e}" if 0.0 < abs(x) < 1e-3 else f"{x:.3f}"


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------


def find_cli_optional(explicit: str | None = None) -> Path | None:
    """Ruta a ``ce`` (explícita, ``$COLORSAPP_CE_CLI`` o ``build/tools/ce``) o None si no existe."""
    candidates = [Path(explicit)] if explicit else []
    env = os.environ.get(CLI_ENV)
    if env:
        candidates.append(Path(env))
    candidates += [REPO_ROOT / "build" / "tools" / "ce", REPO_ROOT / "build" / "ce"]
    for c in candidates:
        if c.is_file() and os.access(c, os.X_OK):
            return c
    return None


def has_palette(cli: Path | None) -> bool:
    """True si ``ce palette`` existe: su uso (sin argumentos) menciona el subcomando o, en su
    defecto, ``ce palette <2x2.ppm> --json`` devuelve 0 con un JSON con ``swatches``."""
    if cli is None:
        return False
    try:
        proc = subprocess.run([str(cli), "palette"], capture_output=True, text=True, check=False, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return False
    if "palette" in (proc.stdout + proc.stderr).lower():
        return True
    with tempfile.TemporaryDirectory(prefix="colorsapp-probe-") as tmp:
        ppm = sc.write_ppm(np.full((2, 2, 3), 128, dtype=np.uint8), Path(tmp) / "probe.ppm")
        try:
            result = run_palette(cli, ppm, center_sigma=0.0, timeout=30)
        except PaletteError:
            return False
    return isinstance(result.get("swatches"), list)


def _fmt_opt(value: Any) -> str:
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    return repr(float(value))


def palette_args(image: Path, *, center_sigma: float | None = None, mask: Path | None = None,
                 options: dict[str, Any] | None = None) -> list[str]:
    """Argumentos de ``ce palette`` según el contrato (``--json`` siempre)."""
    args = ["palette", str(image)]
    if mask is not None:
        args += ["--mask", str(mask)]
    if center_sigma is not None:
        args += ["--center-sigma", _fmt_opt(float(center_sigma))]
    for key, value in (options or {}).items():
        args += ["--" + key.replace("_", "-"), _fmt_opt(value)]
    args.append("--json")
    return args


def run_palette(cli: Path, image: Path, *, center_sigma: float | None = None, mask: Path | None = None,
                options: dict[str, Any] | None = None, timeout: float = 120.0) -> dict[str, Any]:
    """Ejecuta ``ce palette`` y devuelve el JSON parseado (con ``_stdout`` crudo añadido)."""
    args = palette_args(image, center_sigma=center_sigma, mask=mask, options=options)
    try:
        proc = subprocess.run([str(cli), *args], capture_output=True, text=True, check=False, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise PaletteError(f"ce {' '.join(args[:2])}: timeout de {timeout:.0f} s") from exc
    if proc.returncode != 0:
        raise PaletteError(f"ce {' '.join(args)} -> exit {proc.returncode}: {proc.stderr.strip()[:300]}")
    try:
        result = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise PaletteError(f"ce palette: stdout no es JSON ({exc}): {proc.stdout[:200]!r}") from exc
    if not isinstance(result, dict):
        raise PaletteError("ce palette: el JSON no es un objeto")
    result["_stdout"] = proc.stdout
    return result


# --------------------------------------------------------------------------------------
# Contrato del JSON
# --------------------------------------------------------------------------------------

_HEX_RE = re.compile(r"^#[0-9a-f]{6}$")


def validate_result(result: dict[str, Any], width: int, height: int,
                    max_colors: int = ENGINE_DEFAULT_OPTS["max_colors"],
                    max_side: int = ENGINE_DEFAULT_OPTS["max_side"]) -> list[str]:
    """Problemas del JSON respecto al contrato del CLI (lista vacía = conforme)."""
    problems: list[str] = []
    for key in ("engine", "dict_version", "width", "height", "reduced_width", "reduced_height", "opts", "swatches", "hash"):
        if key not in result:
            problems.append(f"falta la clave {key!r}")
    if problems:
        return problems
    if result["width"] != width or result["height"] != height:
        problems.append(f"width/height {result['width']}x{result['height']} != imagen {width}x{height}")
    rw, rh = result["reduced_width"], result["reduced_height"]
    if not (1 <= rw <= max_side and 1 <= rh <= max_side):
        problems.append(f"reduced {rw}x{rh} fuera de 1..{max_side}")
    if not (isinstance(result["dict_version"], str) and re.fullmatch(r"[0-9a-f]{12}", result["dict_version"])):
        problems.append(f"dict_version {result['dict_version']!r} no es 12 hex")
    if not (isinstance(result["hash"], str) and re.fullmatch(r"[0-9a-f]{16}", result["hash"])):
        problems.append(f"hash {result['hash']!r} no es 16 hex")
    if not isinstance(result["opts"], dict):
        problems.append("opts no es un objeto")
    else:
        missing = [k for k in ENGINE_DEFAULT_OPTS if k not in result["opts"]]
        if missing:
            problems.append(f"opts sin {missing}")
    sw = result["swatches"]
    if not isinstance(sw, list) or not (1 <= len(sw) <= max_colors):
        problems.append(f"swatches: {len(sw) if isinstance(sw, list) else type(sw).__name__} (esperaba 1..{max_colors})")
        return problems
    total = 0.0
    prev = None
    for i, s in enumerate(sw):
        for key in ("rgb", "hex", "lab", "weight"):
            if key not in s:
                problems.append(f"swatch {i}: falta {key!r}")
        if any(k not in s for k in ("rgb", "hex", "lab", "weight")):
            continue
        rgb, lab, w = s["rgb"], s["lab"], s["weight"]
        if not (isinstance(rgb, list) and len(rgb) == 3 and all(isinstance(v, int) and 0 <= v <= 255 for v in rgb)):
            problems.append(f"swatch {i}: rgb inválido {rgb!r}")
        elif not (isinstance(s["hex"], str) and _HEX_RE.match(s["hex"]) and s["hex"] == "#%02x%02x%02x" % tuple(rgb)):
            problems.append(f"swatch {i}: hex {s['hex']!r} no corresponde a rgb {rgb}")
        if not (isinstance(lab, list) and len(lab) == 3 and all(isinstance(v, (int, float)) and np.isfinite(v) for v in lab)):
            problems.append(f"swatch {i}: lab inválido {lab!r}")
        elif isinstance(rgb, list) and len(rgb) == 3 and all(isinstance(v, int) for v in rgb):
            back = sc.lab_to_srgb8(lab)
            if int(np.abs(back - np.asarray(rgb)).max()) > 1:
                problems.append(f"swatch {i}: rgb {rgb} no es Lab->sRGB8 de lab (oráculo: {back.tolist()})")
        if not (isinstance(w, (int, float)) and np.isfinite(w) and 0.0 < w <= 1.0 + 1e-12):
            problems.append(f"swatch {i}: weight inválido {w!r}")
            continue
        total += float(w)
        if prev is not None and float(w) > prev + 1e-15:
            problems.append(f"swatch {i}: no ordenado por weight desc ({w} > {prev})")
        prev = float(w)
    if abs(total - 1.0) > 1e-12:
        problems.append(f"sum(weight) = {total!r} (|Δ| = {abs(total - 1.0):.1e} > 1e-12)")
    return problems


# --------------------------------------------------------------------------------------
# Emparejamiento y comparación
# --------------------------------------------------------------------------------------


def swatch_labs(result: dict[str, Any]) -> np.ndarray:
    return np.array([s["lab"] for s in result["swatches"]], dtype=float).reshape(-1, 3)


def swatch_weights(result: dict[str, Any]) -> np.ndarray:
    return np.array([float(s["weight"]) for s in result["swatches"]], dtype=float)


def de00_matrix(labs_a: np.ndarray, labs_b: np.ndarray) -> np.ndarray:
    """Matriz (n, m) de ΔE00 (oráculo colour) entre dos listas de Lab."""
    a = np.asarray(labs_a, dtype=float).reshape(-1, 3)
    b = np.asarray(labs_b, dtype=float).reshape(-1, 3)
    if len(a) == 0 or len(b) == 0:
        return np.zeros((len(a), len(b)))
    aa = np.repeat(a[:, None, :], len(b), axis=1)
    bb = np.repeat(b[None, :, :], len(a), axis=0)
    return np.asarray(ref.de2000(aa, bb), dtype=float).reshape(len(a), len(b))


def assign(labs_a: np.ndarray, labs_b: np.ndarray) -> list[tuple[int, int, float]]:
    """Asignación óptima (Hungarian) por ΔE00: lista de (i, j, ΔE) ordenada por i."""
    cost = de00_matrix(labs_a, labs_b)
    if cost.size == 0:
        return []
    rows, cols = linear_sum_assignment(cost)
    return sorted((int(i), int(j), float(cost[i, j])) for i, j in zip(rows, cols))


def compare_to_truth(result: dict[str, Any], truth: list[dict[str, Any]]) -> dict[str, Any]:
    """ΔE00 y error de peso de cada color de la verdad frente a su swatch emparejado."""
    t_labs = np.array([t["lab"] for t in truth], dtype=float)
    pairs = assign(t_labs, swatch_labs(result))
    weights = swatch_weights(result)
    de = [float("inf")] * len(truth)
    w_err = [float("inf")] * len(truth)
    for i, j, d in pairs:
        de[i] = d
        w_err[i] = abs(float(weights[j]) - float(truth[i]["area"]))
    return {
        "n_swatches": len(result["swatches"]),
        "matched": len(pairs) == len(truth),
        "de": de,
        "de_max": max(de),
        "w_err": w_err,
        "w_err_max": max(w_err),
    }


def compare_palettes(a: dict[str, Any], b: dict[str, Any]) -> dict[str, Any]:
    """Compara dos resultados: igualdad exacta (lab, weight), bytes del JSON, mismo n, ΔE00 y Δpeso por par."""
    la, lb = swatch_labs(a), swatch_labs(b)
    wa, wb = swatch_weights(a), swatch_weights(b)
    pairs = assign(la, lb)
    de_max = max((d for _, _, d in pairs), default=0.0)
    w_diff = max((abs(float(wa[i]) - float(wb[j])) for i, j, _ in pairs), default=0.0)
    same_n = len(la) == len(lb)
    exact = same_n and [s["lab"] for s in a["swatches"]] == [s["lab"] for s in b["swatches"]] \
        and [s["weight"] for s in a["swatches"]] == [s["weight"] for s in b["swatches"]]
    return {
        "same_n": same_n,
        "exact": bool(exact),
        "hash_equal": a.get("hash") == b.get("hash"),
        # Bytes del JSON completo (stdout) idénticos: el contrato no incluye rutas ni
        # tiempos, así que dos entradas equivalentes deben producir el mismo texto.
        "stdout_equal": a.get("_stdout") == b.get("_stdout"),
        "de_max": float(de_max if same_n else float("inf")),
        "w_diff_max": float(w_diff),
        "n": (len(la), len(lb)),
    }


# --------------------------------------------------------------------------------------
# Umbrales
# --------------------------------------------------------------------------------------


def resolve_thresholds(thresholds: dict[str, Any] | None) -> tuple[dict[str, Any], list[str]]:
    """Aplana ``thresholds["L2"]`` (``invariance.x`` para las anidadas); devuelve (valores, claves por defecto)."""
    section = (thresholds or {}).get("L2", {}) if thresholds else {}
    inv = section.get("invariance", {}) if isinstance(section, dict) else {}
    values: dict[str, Any] = {}
    defaulted: list[str] = []
    for key, default in DEFAULTS.items():
        if key.startswith("invariance."):
            source, sub = inv, key.split(".", 1)[1]
        else:
            source, sub = section, key
        if isinstance(source, dict) and sub in source:
            values[key] = source[sub]
        else:
            values[key] = default
            defaulted.append(key)
    return values, defaulted


def load_thresholds(path: Path = THRESHOLDS_PATH) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}


def layout_for_seed(seed: int) -> str:
    return list(sc.LAYOUTS)[(seed - 1) % 2]


# --------------------------------------------------------------------------------------
# Bloque (a): composiciones
# --------------------------------------------------------------------------------------


class _Artifacts:
    """Guarda PPM + JSON de los casos que fallan (acotado)."""

    def __init__(self, fail_dir: Path | None):
        self.dir = fail_dir
        self.count = 0
        if fail_dir is not None:
            shutil.rmtree(fail_dir, ignore_errors=True)
            fail_dir.mkdir(parents=True, exist_ok=True)

    def save(self, tag: str, ppm: Path, result: dict[str, Any] | None) -> None:
        if self.dir is None or self.count >= MAX_FAIL_ARTIFACTS:
            return
        self.count += 1
        shutil.copyfile(ppm, self.dir / f"{tag}.ppm")
        if result is not None:
            (self.dir / f"{tag}.json").write_text(result.get("_stdout", json.dumps(result)), encoding="utf-8")


def run_compositions(cli: Path, n: int, th: dict[str, Any], work: Path, artifacts: _Artifacts,
                     size: tuple[int, int] = sc.DEFAULT_SIZE) -> tuple[list[Check], list[dict[str, Any]]]:
    de_max_th = float(th["color_de00_max"])
    w_max_th = float(th["weight_abs_error_max"])
    rows: list[dict[str, Any]] = []
    contract_problems: list[str] = []
    errors: list[str] = []
    for seed in range(1, n + 1):
        layout = layout_for_seed(seed)
        img, truth = sc.compose(seed, size=size, layout=layout)
        _labels, variant = sc.compose_labels(seed, size=size, layout=layout)
        ppm = sc.write_ppm(img, work / f"comp_{seed}.ppm")
        row: dict[str, Any] = {"seed": seed, "layout": layout, "variant": variant, "ok": False}
        try:
            uni = run_palette(cli, ppm, center_sigma=0.0)
            problems = validate_result(uni, img.shape[1], img.shape[0])
            contract_problems += [f"seed {seed} uniforme: {p}" for p in problems]
            cmp_u = compare_to_truth(uni, truth)
            row["uniform"] = {k: cmp_u[k] for k in ("n_swatches", "matched", "de", "de_max", "w_err", "w_err_max")}
            row["ok"] = cmp_u["matched"] and cmp_u["de_max"] < de_max_th and cmp_u["w_err_max"] <= w_max_th
            if not row["ok"]:
                artifacts.save(f"comp_{seed}_uniform", ppm, uni)
        except PaletteError as exc:
            errors.append(f"seed {seed} uniforme: {exc}")
            row["uniform"] = {"error": str(exc)}
            artifacts.save(f"comp_{seed}_uniform", ppm, None)
        try:
            dflt = run_palette(cli, ppm)
            problems = validate_result(dflt, img.shape[1], img.shape[0])
            contract_problems += [f"seed {seed} sigma por defecto: {p}" for p in problems]
            cmp_d = compare_to_truth(dflt, truth)
            row["default"] = {k: cmp_d[k] for k in ("n_swatches", "matched", "de", "de_max", "w_err", "w_err_max")}
            row["default"]["opts"] = dflt.get("opts")
        except PaletteError as exc:
            errors.append(f"seed {seed} sigma por defecto: {exc}")
            row["default"] = {"error": str(exc)}
        rows.append(row)

    ok_rows = [r for r in rows if r["ok"]]
    uni_rows = [r for r in rows if "de_max" in r.get("uniform", {})]
    de_max = max((r["uniform"]["de_max"] for r in uni_rows), default=float("inf") if errors else 0.0)
    w_max = max((r["uniform"]["w_err_max"] for r in uni_rows), default=float("inf") if errors else 0.0)
    rate = len(ok_rows) / n if n else 0.0
    failures = [r for r in rows if not r["ok"]]
    fail_lines = []
    for r in failures[:8]:
        u = r["uniform"]
        if "error" in u:
            fail_lines.append(f"seed {r['seed']} ({r['variant']}, {r['layout']}): {u['error'][:120]}")
        else:
            fail_lines.append(
                f"seed {r['seed']} ({r['variant']}, {r['layout']}): n={u['n_swatches']}, "
                f"ΔE={[round(d, 2) for d in u['de']]}, |Δpeso|={[round(e, 3) for e in u['w_err']]}"
            )
    detail = (
        f"pasan {len(ok_rows)}/{n}; max ΔE00 = {_fmt(de_max)} (umbral {de_max_th}); "
        f"max |peso - área| = {_fmt(w_max)} (umbral {w_max_th}); errores del CLI: {len(errors)}"
    )
    if fail_lines:
        detail += "\nfallos: " + "\n        ".join(fail_lines)
    checks = [
        Check(
            f"composiciones uniformes ({n}, --center-sigma 0): cada color ΔE00 < {de_max_th} y |peso - área| <= {w_max_th}",
            "pass" if rate == 1.0 and not errors else "fail",
            detail, value=rate, threshold=1.0,
        ),
    ]
    n_results = sum(1 for r in rows for k in ("uniform", "default") if k in r and "error" not in r[k])
    checks.append(Check(
        "contrato JSON de ce palette (claves, sum(weight) = 1 ± 1e-12, orden desc, hex = rgb, rgb = Lab->sRGB8, hash 16 hex)",
        "pass" if not contract_problems and n_results else "fail",
        f"{n_results} resultados validados; problemas: {len(contract_problems)}"
        + ("\n" + "\n".join(contract_problems[:10]) if contract_problems else ""),
        value=len(contract_problems), threshold=0,
    ))
    d_rows = [r for r in rows if "de_max" in r.get("default", {})]
    d_found = sum(1 for r in d_rows if r["default"]["matched"] and r["default"]["de_max"] < de_max_th)
    d_de = max((r["default"]["de_max"] for r in d_rows if r["default"]["matched"]), default=0.0)
    d_w = max((r["default"]["w_err_max"] for r in d_rows if r["default"]["matched"]), default=0.0)
    checks.append(Check(
        "composiciones con sigma por defecto (informativo: el peso al centro no es el área)",
        "info",
        f"los 3 colores con ΔE00 < {de_max_th} en {d_found}/{len(d_rows)}; max ΔE00 = {_fmt(d_de)}; "
        f"max |peso - área| = {_fmt(d_w)} (esperado > 0 en nested/corners/l_shape)",
        value=d_found,
    ))
    return checks, rows


# --------------------------------------------------------------------------------------
# Bloque (b): invariancias
# --------------------------------------------------------------------------------------


def run_invariances(cli: Path, m: int, th: dict[str, Any], work: Path, artifacts: _Artifacts,
                    size: tuple[int, int] = sc.DEFAULT_SIZE) -> tuple[list[Check], list[dict[str, Any]]]:
    th_shuffle_d = float(th["invariance.shuffle_center_weighted_de00_max"])
    th_scale = float(th["invariance.scale_de00_max"])
    th_mr = float(th["invariance.mirror_rotate_de00_max"])
    th_noise = float(th["invariance.noise_sigma2_de00_max"])
    rows: list[dict[str, Any]] = []
    errors: list[str] = []

    for k in range(1, m + 1):
        seed = INVARIANCE_SEED_BASE + k
        layout = layout_for_seed(seed)
        img, _truth = sc.compose(seed, size=size, layout=layout)
        _labels, variant = sc.compose_labels(seed, size=size, layout=layout)
        row: dict[str, Any] = {"seed": seed, "layout": layout, "variant": variant}
        paths = {
            "base": sc.write_ppm(img, work / f"inv_{seed}_base.ppm"),
            "shuffle": sc.write_ppm(sc.shuffle_pixels(img, seed), work / f"inv_{seed}_shuffle.ppm"),
            "scale_0.5": sc.write_ppm(sc.scale(img, 0.5), work / f"inv_{seed}_half.ppm"),
            "scale_2": sc.write_ppm(sc.scale(img, 2.0), work / f"inv_{seed}_double.ppm"),
            "mirror": sc.write_ppm(sc.mirror(img), work / f"inv_{seed}_mirror.ppm"),
            "rotate180": sc.write_ppm(sc.rotate180(img), work / f"inv_{seed}_rot.ppm"),
            "noise": sc.write_ppm(sc.add_noise(img, 2.0, seed), work / f"inv_{seed}_noise.ppm"),
        }
        try:
            base_u = run_palette(cli, paths["base"], center_sigma=0.0)
            base_u2 = run_palette(cli, paths["base"], center_sigma=0.0)
            base_d = run_palette(cli, paths["base"])
            res_u = {name: run_palette(cli, p, center_sigma=0.0) for name, p in paths.items() if name != "base"}
            shuffle_d = run_palette(cli, paths["shuffle"])
            mirror_d = run_palette(cli, paths["mirror"])
            rot_d = run_palette(cli, paths["rotate180"])
        except PaletteError as exc:
            errors.append(f"seed {seed}: {exc}")
            row["error"] = str(exc)
            rows.append(row)
            artifacts.save(f"inv_{seed}_base", paths["base"], None)
            continue
        rerun = compare_palettes(base_u, base_u2)
        row["rerun"] = {"same_hash": rerun["hash_equal"], "same_json": base_u["_stdout"] == base_u2["_stdout"]}
        row["shuffle_uniform"] = compare_palettes(base_u, res_u["shuffle"])
        row["shuffle_default"] = compare_palettes(base_d, shuffle_d)
        for name in ("scale_0.5", "scale_2", "mirror", "rotate180", "noise"):
            row[name] = compare_palettes(base_u, res_u[name])
        row["mirror_default"] = compare_palettes(base_d, mirror_d)
        row["rotate180_default"] = compare_palettes(base_d, rot_d)
        row["n_base"] = len(base_u["swatches"])
        rows.append(row)
        failing = (
            not (row["rerun"]["same_hash"] and row["rerun"]["same_json"])
            or not (row["shuffle_uniform"]["exact"] and row["shuffle_uniform"]["hash_equal"]
                    and row["shuffle_uniform"]["stdout_equal"])
            or not (row["shuffle_default"]["same_n"] and row["shuffle_default"]["de_max"] < th_shuffle_d)
            or not (row["scale_0.5"]["same_n"] and row["scale_0.5"]["de_max"] < th_scale)
            or not (row["scale_2"]["same_n"] and row["scale_2"]["de_max"] < th_scale)
            or not (row["mirror"]["same_n"] and row["mirror"]["de_max"] < th_mr)
            or not (row["rotate180"]["same_n"] and row["rotate180"]["de_max"] < th_mr)
            or not (row["noise"]["same_n"] and row["noise"]["de_max"] < th_noise)
        )
        if failing:
            artifacts.save(f"inv_{seed}_base_uniform", paths["base"], base_u)

    good = [r for r in rows if "error" not in r]

    def agg(key: str, threshold: float | None, exact: bool = False) -> tuple[str, str, float]:
        bad = []
        worst = 0.0
        for r in good:
            c = r[key]
            worst = max(worst, c["de_max"] if np.isfinite(c["de_max"]) else 1e9)
            if exact:
                ok = c["exact"] and c["hash_equal"] and c["stdout_equal"]
            else:
                ok = c["same_n"] and threshold is not None and c["de_max"] < threshold
            if not ok:
                bad.append(f"seed {r['seed']} ({r['variant']}): n={c['n']}, ΔE={c['de_max']:.3f}, |Δpeso|={c['w_diff_max']:.4f}"
                           + (", hash distinto" if not c["hash_equal"] else "")
                           + (", JSON distinto" if exact and not c["stdout_equal"] else ""))
        w_max = max((r[key]["w_diff_max"] for r in good), default=0.0)
        status = "pass" if not bad and not errors and good else "fail"
        detail = f"{len(good) - len(bad)}/{m} ok; max ΔE00 = {_fmt(worst)}; max |Δpeso| = {_fmt(w_max)}"
        if errors:
            detail += f"; errores del CLI: {len(errors)} ({errors[0][:120]})"
        if bad:
            detail += "\nfallos: " + "\n        ".join(bad[:6])
        return status, detail, worst

    checks: list[Check] = []
    st, dt, _ = agg("shuffle_uniform", None, exact=True)
    checks.append(Check(f"invariancia barajado, modo uniforme ({m}): lab y weight bit-idénticos, mismo hash y mismo JSON (bytes)", st, dt,
                        value=sum(1 for r in good if r["shuffle_uniform"]["exact"] and r["shuffle_uniform"]["stdout_equal"]),
                        threshold=th["invariance.shuffle_uniform"]))
    st, dt, worst = agg("shuffle_default", th_shuffle_d)
    checks.append(Check(f"invariancia barajado, sigma por defecto ({m}): mismo n y ΔE00 < {th_shuffle_d}", st, dt, value=worst, threshold=th_shuffle_d))
    worst_scale = 0.0
    parts = []
    st_all = "pass"
    for key in ("scale_0.5", "scale_2"):
        st, dt, worst = agg(key, th_scale)
        worst_scale = max(worst_scale, worst)
        parts.append(f"{key}: {dt}")
        if st != "pass":
            st_all = "fail"
    checks.append(Check(f"invariancia escala 0,5x y 2x, modo uniforme ({m}): ΔE00 < {th_scale}", st_all, "\n".join(parts), value=worst_scale, threshold=th_scale))
    worst_mr = 0.0
    parts = []
    st_all = "pass"
    for key in ("mirror", "rotate180"):
        st, dt, worst = agg(key, th_mr)
        worst_mr = max(worst_mr, worst)
        parts.append(f"{key}: {dt}")
        if st != "pass":
            st_all = "fail"
    checks.append(Check(f"invariancia espejo y rotación 180°, modo uniforme ({m}): ΔE00 < {th_mr}", st_all, "\n".join(parts), value=worst_mr, threshold=th_mr))
    st, dt, worst = agg("noise", th_noise)
    checks.append(Check(f"invariancia ruido gaussiano sigma = 2, modo uniforme ({m}): ΔE00 < {th_noise}", st, dt, value=worst, threshold=th_noise))
    rerun_bad = [r["seed"] for r in good if not (r["rerun"]["same_hash"] and r["rerun"]["same_json"])]
    checks.append(Check(
        f"determinismo ({m}): dos ejecuciones -> mismo hash y mismo JSON",
        "pass" if not rerun_bad and not errors and good else "fail",
        f"{len(good) - len(rerun_bad)}/{m} ok" + (f"; distintos: {rerun_bad[:8]}" if rerun_bad else "")
        + (f"; errores del CLI: {len(errors)}" if errors else ""),
        value=len(rerun_bad), threshold=th["invariance.rerun"],
    ))
    # Informativo: con el sigma por defecto, espejo y rotación deberían ser igual de invariantes.
    d_worst = max((max(r["mirror_default"]["de_max"], r["rotate180_default"]["de_max"]) for r in good
                   if r["mirror_default"]["same_n"] and r["rotate180_default"]["same_n"]), default=0.0)
    d_bad = sum(1 for r in good if not (r["mirror_default"]["same_n"] and r["rotate180_default"]["same_n"]))
    checks.append(Check(
        "invariancia espejo/rotación con sigma por defecto (informativo)",
        "info",
        f"max ΔE00 = {_fmt(d_worst)}; composiciones con n distinto: {d_bad}/{len(good)}",
        value=d_worst,
    ))
    return checks, rows


# --------------------------------------------------------------------------------------
# Capa completa
# --------------------------------------------------------------------------------------


def not_implemented_reason(cli: Path | None) -> str:
    if cli is None:
        return "no existe build/tools/ce (make build) ni $COLORSAPP_CE_CLI"
    return f"{cli} no tiene el subcomando 'palette' (fase 2: ce_palette.c + ce_pnm.c + ce_cli.c)"


def run_layer2(cli: Path, thresholds: dict[str, Any] | None, out_dir: Path | None, fast: bool,
               n_compositions: int | None = None, n_invariances: int | None = None,
               log=print) -> tuple[list[Check], dict[str, Any]]:
    """Ejecuta los dos bloques y devuelve (checks, detalle). Escribe ``<out>/l2_detail.json``."""
    th, defaulted = resolve_thresholds(thresholds)
    n = int(n_compositions if n_compositions is not None else th["compositions_fast" if fast else "compositions"])
    m = int(n_invariances if n_invariances is not None else th["invariance_compositions_fast" if fast else "invariance_compositions"])
    started = time.perf_counter()
    checks: list[Check] = []
    detail: dict[str, Any] = {"cli": str(cli), "mode": "fast" if fast else "full", "compositions_n": n,
                              "invariances_n": m, "thresholds": th, "thresholds_defaulted": defaulted}
    artifacts = _Artifacts(out_dir / "l2" / "fail" if out_dir else None)
    with tempfile.TemporaryDirectory(prefix="colorsapp-l2-") as tmp:
        work = Path(tmp)
        t0 = time.perf_counter()
        comp_checks, comp_rows = run_compositions(cli, n, th, work, artifacts)
        comp_checks[0].seconds = round(time.perf_counter() - t0, 3)
        for c in comp_checks:
            log(f"  [{c.status:>7}] {c.name}" + (f" ({c.seconds:.1f}s)" if c.seconds else ""))
            if c.status == "fail":
                log("           " + c.detail.replace("\n", "\n           "))
        checks += comp_checks
        detail["compositions"] = comp_rows
        t0 = time.perf_counter()
        inv_checks, inv_rows = run_invariances(cli, m, th, work, artifacts)
        inv_checks[0].seconds = round(time.perf_counter() - t0, 3)
        for c in inv_checks:
            log(f"  [{c.status:>7}] {c.name}" + (f" ({c.seconds:.1f}s)" if c.seconds else ""))
            if c.status == "fail":
                log("           " + c.detail.replace("\n", "\n           "))
        checks += inv_checks
        detail["invariances"] = inv_rows
        from oracle import garments

        if garments.has_garments(cli):
            t0 = time.perf_counter()
            g_checks, g_detail = garments.run_block(cli, thresholds, work, log=log)
            if g_checks:
                g_checks[0].seconds = round(time.perf_counter() - t0, 3)
            checks += g_checks
            detail["garments"] = g_detail
        else:
            c = Check("prendas (ce batch --garments)", "skipped", f"{cli} no tiene el subcomando 'garments'")
            checks.append(c)
            log(f"  [{c.status:>7}] {c.name}: {c.detail}")
    seconds = round(time.perf_counter() - started, 1)
    detail["seconds"] = seconds
    if fast:
        limit = float(th["l2_fast_seconds_max"])
        c = Check(f"L2 --fast < {limit:.0f} s", "pass" if seconds < limit else "fail",
                  f"{seconds} s para {n} composiciones y {m} invariancias", value=seconds, threshold=limit)
        checks.append(c)
        log(f"  [{c.status:>7}] {c.name}: {c.detail}")
    if defaulted:
        c = Check("umbrales L2 con valores por defecto (no promovidos en thresholds.json)", "info",
                  ", ".join(f"{k}={th[k]}" for k in defaulted), value=len(defaulted))
        checks.append(c)
        log(f"  [{c.status:>7}] {c.name}: {c.detail}")
    if out_dir is not None:
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "l2_detail.json").write_text(json.dumps(detail, indent=1, ensure_ascii=False, default=_json_default) + "\n", encoding="utf-8")
    return checks, detail


def _json_default(obj: Any) -> Any:
    if isinstance(obj, (np.floating, np.integer)):
        return obj.item()
    if isinstance(obj, np.ndarray):
        return obj.tolist()
    if isinstance(obj, float) and not np.isfinite(obj):
        return None
    raise TypeError(f"no serializable: {type(obj).__name__}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fast", action="store_true", help="40 composiciones y 8 invariancias")
    ap.add_argument("--cli", type=str, default=None, help="ruta a 'ce' (por defecto build/tools/ce o $COLORSAPP_CE_CLI)")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="directorio de artefactos (harness/out)")
    ap.add_argument("--compositions", type=int, default=None, help="número de composiciones (bloque a)")
    ap.add_argument("--invariances", type=int, default=None, help="número de composiciones del bloque b")
    args = ap.parse_args(argv)
    cli = find_cli_optional(args.cli)
    if not has_palette(cli):
        print(f"L2: not implemented — {not_implemented_reason(cli)}")
        return 1
    print(f"L2 extracción de paleta ({'fast' if args.fast else 'full'}) con {cli}")
    checks, detail = run_layer2(cli, load_thresholds(), args.out, args.fast, args.compositions, args.invariances)
    failed = [c for c in checks if c.status == "fail"]
    print(f"L2 {'FAIL' if failed else 'OK'}: {len(checks) - len(failed)}/{len(checks)} checks en {detail['seconds']} s; detalle en {args.out / 'l2_detail.json'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
