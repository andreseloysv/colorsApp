"""Harness de evaluación del motor: ``make eval`` / ``make eval-fast``.

    uv run --project oracle python -m oracle.eval [--fast] [--out harness/out] [--cli PATH] [--no-make]

Ejecuta, en este orden, y escribe ``<out>/scorecard.json`` y ``<out>/scorecard.md``:

0. ``make check-protected`` si el target existe (si no, ``skipped``). Un fallo aquí
   se registra en el scorecard y hace fallar el eval.
1. Capa 1 (matemática de color): ``make test`` (ctest nativo: test_math + test_dict),
   ``make diff-oracle`` (100 000 colores; con ``--fast`` 10 000) y checks propios sobre
   el CLI ``ce``:
   - los 34 pares de Sharma/Wu/Dalal: gate sobre 33 a 1e-4; el par 14 cae en la
     discontinuidad |Δh'| = 180° y se reporta como informativo aceptando 4.8045 o 4.7461;
   - comparación laxa de 2000 colores contra ``skimage.color.rgb2lab`` (ΔE76 <= 0.05);
   - ΔE00 con kL = 2 del motor contra ``colour`` con ``textiles=True`` en 200 pares;
   - casos borde (C = 0, tonos opuestos) sin NaN;
   - cruce de ``dict_version``: ``ce dict --version`` == ``dictionary.json`` ==
     cabecera de ``golden_wada_lab.tsv``, y ``make dict-check``.
2. Capa 2 (extracción de paleta, ``oracle.l2``): composiciones sintéticas de
   ``synth.compose`` por ``ce palette`` (200 composiciones en modo uniforme, 30 de
   invariancias; con ``--fast`` 40 y 8). ``not implemented`` con motivo si el CLI no tiene
   el subcomando ``palette``.
3. Capa 3 (match contra el diccionario, ``oracle.l3``): 348 x 10 sintéticos de
   ``synth.wada_gen`` en ``harness/out/synth`` (cacheados por ``generator_hash``; con
   ``--fast`` 35 combinaciones fijas), ``ce batch`` en tres columnas (kL=1 oficial, kL=2 y
   skin=1 informativas), umbrales por degradación y cuota máxima de ``thresholds.json`` L3,
   determinismo, holdout (variantes 10-11 con ``COLORSAPP_HOLDOUT_SEED``; sin ella
   ``skipped``) y ``golden-check``. ``not implemented`` si el CLI no tiene ``match``.
4. Capa 4 (fotos reales, ``l4.run``): runner mínimo sobre ``$COLORSAPP_GOLDEN_DIR``
   (manifest, sha256/formato, consenso, recall por tag, cuota máxima, Fleiss κ); sin la
   variable, ``skipped``.

Semántica de salida por capa (sección 6 del plan):

| Situación                                                              | Estado            | Exit |
|------------------------------------------------------------------------|-------------------|------|
| capa no implementada                                                   | ``not implemented``| 1    |
| implementada y en umbral                                               | ``pass``          | 0    |
| implementada fuera de umbral o con error                               | ``fail``          | 1    |
| sin datos: L4 sin ``COLORSAPP_GOLDEN_DIR``; holdout sin ``COLORSAPP_HOLDOUT_SEED`` | ``skipped`` + motivo + aviso | 0 |

``skipped`` solo admite esos dos motivos. Los umbrales salen de ``harness/thresholds.json``
(ruta protegida); las claves que falten toman el valor del contrato de su fase y se anotan
como defaults no promovidos. ``--fast`` gatea además el tiempo total (< 2 min). Al final
imprime una línea resumen del tipo ``L1 OK; L2 OK; L3 OK (holdout skipped); L4 skipped``.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

import numpy as np

from l4 import run as l4run
from oracle import l2, l3
from oracle import reference as ref
from oracle.diff_oracle import find_cli, run_cli

REPO_ROOT = Path(__file__).resolve().parents[2]
ENGINE_DIR = REPO_ROOT / "engine"
HARNESS_DIR = REPO_ROOT / "harness"
THRESHOLDS_PATH = HARNESS_DIR / "thresholds.json"
DICTIONARY_PATH = REPO_ROOT / "data" / "wada" / "dictionary.json"
SHARMA_PATH = ENGINE_DIR / "tests" / "data" / "ciede2000testdata.txt"
GOLDEN_WADA_PATH = ENGINE_DIR / "tests" / "data" / "golden_wada_lab.tsv"
DEFAULT_OUT = HARNESS_DIR / "out"
SEED = 20260914
SHARMA_PAIR14_INDEX = 13  # 0-based

LAYERS: tuple[tuple[str, str], ...] = (
    ("L1", "Matemática de color"),
    ("L2", "Extracción de paleta"),
    ("L3", "Match contra el diccionario"),
    ("L4", "Fotos reales"),
)
#: Estados de capa que no hacen fallar el eval (sección 6 del plan).
GREEN_STATUSES = ("pass", "skipped")

# Programa C mínimo para ejecutar ce_de2000_k con factores paramétricos (el CLI ``ce``
# solo expone kL = kC = kH = 1). Se compila contra build/libcolorengine.a al vuelo.
DE2000K_SHIM_C = r"""
#include "ce/ce.h"
#include <stdio.h>
#pragma STDC FP_CONTRACT OFF
int main(void)
{
    double v[9];
    while (scanf("%lf %lf %lf %lf %lf %lf %lf %lf %lf",
                 &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7], &v[8]) == 9) {
        ce_lab a, b;
        a.L = v[0]; a.a = v[1]; a.b = v[2];
        b.L = v[3]; b.a = v[4]; b.b = v[5];
        printf("%.15e\n", ce_de2000_k(a, b, v[6], v[7], v[8]));
    }
    return 0;
}
"""


# --------------------------------------------------------------------------------------
# Modelo del scorecard
# --------------------------------------------------------------------------------------


@dataclass
class Check:
    """Un check individual: ``status`` es pass | fail | skipped | info."""

    name: str
    status: str
    detail: str = ""
    value: Any = None
    threshold: Any = None
    seconds: float | None = None

    @property
    def ok(self) -> bool:
        return self.status in ("pass", "skipped", "info")


@dataclass
class Layer:
    id: str
    title: str
    status: str = "not implemented"  # pass | fail | not implemented | skipped
    checks: list[Check] = field(default_factory=list)
    #: Avisos destacados (checks o capa ``skipped``): van al scorecard y a stdout.
    warnings: list[str] = field(default_factory=list)
    #: Markdown adicional (p. ej. la tabla de L3 por degradación y columna).
    markdown: str | None = None
    #: Datos estructurados adicionales para scorecard.json (p. ej. las variantes de recorte de L4).
    data: dict[str, Any] | None = None

    def finalize(self) -> None:
        if self.status in ("not implemented", "skipped"):
            return
        self.status = "fail" if any(c.status == "fail" for c in self.checks) else "pass"


def _tail(text: str, lines: int = 12) -> str:
    """Últimas ``lines`` líneas, sin las órdenes que make imprime al ejecutarlas."""
    noise = ("uv run ", "make -C ", "cmake ", "ctest ")
    rows = [
        r for r in text.strip().splitlines()
        if not r.startswith(noise) and "ColourUsageWarning" not in r and "warn(*args" not in r
        and "installation-guide" not in r
    ]
    return "\n".join(rows[-lines:])


def run_make(target: str, *extra: str, env: dict[str, str] | None = None) -> tuple[int, str]:
    """Ejecuta ``make -C REPO_ROOT <target> <extra>`` capturando stdout+stderr."""
    proc = subprocess.run(
        ["make", "-C", str(REPO_ROOT), target, *extra],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )
    return proc.returncode, proc.stdout + proc.stderr


def make_target_exists(target: str) -> bool:
    """``make -n`` no ejecuta nada: si el target no existe, make sale con 2."""
    proc = subprocess.run(
        ["make", "-C", str(REPO_ROOT), "-n", target],
        capture_output=True,
        text=True,
        check=False,
    )
    return not (proc.returncode == 2 and "No rule to make target" in proc.stderr)


def cli_output(cli: Path, *args: str, stdin: str | None = None) -> str:
    proc = subprocess.run([str(cli), *args], input=stdin, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"'{cli.name} {' '.join(args)}' devolvió {proc.returncode}: {proc.stderr.strip()}")
    return proc.stdout


def timed(fn):
    """Ejecuta ``fn()`` -> Check y le añade la duración."""
    t0 = time.perf_counter()
    check = fn()
    check.seconds = round(time.perf_counter() - t0, 3)
    return check


# --------------------------------------------------------------------------------------
# Paso 0: rutas protegidas
# --------------------------------------------------------------------------------------


def check_protected() -> Check:
    if not make_target_exists("check-protected"):
        return Check("check-protected", "skipped", "target no disponible aún (fase 0)")
    rc, out = run_make("check-protected")
    allowed = os.environ.get("COLORSAPP_ALLOW_PROTECTED") == "1"
    if rc == 0:
        detail = _tail(out, 6)
        if allowed and "permitido por" in out:
            return Check("check-protected", "info", "cambios en rutas protegidas permitidos por COLORSAPP_ALLOW_PROTECTED=1\n" + detail)
        return Check("check-protected", "pass", detail)
    return Check("check-protected", "fail", _tail(out, 20))


# --------------------------------------------------------------------------------------
# Capa 1
# --------------------------------------------------------------------------------------


def check_make_test() -> Check:
    rc, out = run_make("test")
    passed = "100% tests passed" in out
    status = "pass" if rc == 0 and passed else "fail"
    return Check("make test (ctest: test_math + test_dict)", status, _tail(out, 8 if status == "pass" else 40))


def check_diff_oracle(n: int, tol: float) -> Check:
    rc, out = run_make("diff-oracle", f"DIFF_N={n}")
    status = "pass" if rc == 0 and "\nOK" in "\n" + out else "fail"
    return Check(f"make diff-oracle ({n} colores)", status, _tail(out, 8 if status == "pass" else 30), value=n, threshold=tol)


def load_sharma() -> np.ndarray:
    rows = [
        [float(v) for v in line.split()]
        for line in SHARMA_PATH.read_text().splitlines()
        if line.strip() and not line.startswith("#")
    ]
    data = np.array(rows, dtype=float)
    if data.shape != (34, 7):
        raise RuntimeError(f"{SHARMA_PATH}: esperaba 34x7, tengo {data.shape}")
    return data


def check_sharma(cli: Path, tol: float, pair14_accepted: list[float]) -> list[Check]:
    data = load_sharma()
    payload = "\n".join(" ".join(f"{v:.4f}" for v in row[:6]) for row in data) + "\n"
    got = np.array([float(x) for x in cli_output(cli, "de2000", stdin=payload).split()])
    swapped = "\n".join(" ".join(f"{v:.4f}" for v in np.concatenate([row[3:6], row[0:3]])) for row in data) + "\n"
    got_sym = np.array([float(x) for x in cli_output(cli, "de2000", stdin=swapped).split()])
    expected = data[:, 6]
    gated = [i for i in range(34) if i != SHARMA_PAIR14_INDEX]
    err = np.abs(got[gated] - expected[gated])
    err_sym = np.abs(got_sym[gated] - expected[gated])
    worst = float(max(err.max(), err_sym.max()))
    n_bad = int(((err > tol) | (err_sym > tol)).sum())
    gate = Check(
        "Sharma 33 pares (ambos órdenes)",
        "pass" if n_bad == 0 else "fail",
        f"max |ΔE00 - esperado| = {worst:.2e}; pares fuera de tolerancia: {n_bad}",
        value=worst,
        threshold=tol,
    )
    p14 = float(got[SHARMA_PAIR14_INDEX])
    matched = [v for v in pair14_accepted if abs(p14 - v) <= tol]
    info = Check(
        "Sharma par 14 (informativo, discontinuidad |Δh'| = 180°)",
        "info" if matched else "fail",
        f"ce = {p14:.4f}; aceptados {pair14_accepted} (fichero: {expected[SHARMA_PAIR14_INDEX]:.4f}); "
        + ("coincide con " + ", ".join(f"{v:.4f}" for v in matched) if matched else "no coincide con ninguno"),
        value=p14,
        threshold=pair14_accepted,
    )
    return [gate, info]


def check_skimage_lax(cli: Path, n: int, tol: float) -> Check:
    from skimage import color as skcolor

    rng = np.random.default_rng(SEED + 1)
    rgb8 = rng.integers(0, 256, size=(n, 3), dtype=np.int64)
    got = run_cli(cli, rgb8)
    expected = np.asarray(skcolor.rgb2lab(rgb8.astype(float) / 255.0), dtype=float)
    de76 = np.sqrt(np.sum((got - expected) ** 2, axis=1))
    worst = float(de76.max())
    worst_i = int(de76.argmax())
    return Check(
        f"laxo vs skimage.color.rgb2lab ({n} colores, ΔE76)",
        "pass" if worst <= tol else "fail",
        f"max ΔE76 = {worst:.4f} en rgb={tuple(int(v) for v in rgb8[worst_i])}; media {float(de76.mean()):.4f}",
        value=worst,
        threshold=tol,
    )


def build_de2000k_shim(out_dir: Path) -> Path | None:
    """Compila el shim contra build/libcolorengine.a. None si no hay compilador o librería."""
    cc = shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
    lib = REPO_ROOT / "build" / "libcolorengine.a"
    if cc is None or not lib.is_file():
        return None
    src = out_dir / "de2000k_shim.c"
    exe = out_dir / "de2000k_shim"
    src.write_text(DE2000K_SHIM_C, encoding="ascii")
    cmd = [
        cc, "-std=c11", "-O2", "-ffp-contract=off", "-Wall", "-Wextra", "-Werror",
        "-I", str(ENGINE_DIR / "Sources" / "CColorEngine" / "include"),
        str(src), str(lib), "-o", str(exe),
    ]
    if sys.platform.startswith("linux"):
        cmd.append("-lm")
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"no se pudo compilar el shim de ce_de2000_k: {proc.stderr.strip()}")
    return exe


def check_textiles_kl2(out_dir: Path, n: int, tol: float) -> Check:
    from colour.difference import delta_E_CIE2000

    shim = build_de2000k_shim(out_dir)
    name = f"kL=2 vs colour textiles=True ({n} pares)"
    if shim is None:
        return Check(name, "skipped", "sin compilador C o sin build/libcolorengine.a")
    rng = np.random.default_rng(SEED + 2)
    L = rng.uniform(0.0, 100.0, size=(n, 2))
    a = rng.uniform(-128.0, 128.0, size=(n, 2))
    b = rng.uniform(-128.0, 128.0, size=(n, 2))
    lab1 = np.stack([L[:, 0], a[:, 0], b[:, 0]], axis=1)
    lab2 = np.stack([L[:, 1], a[:, 1], b[:, 1]], axis=1)
    # Como en los golden: se formatea con %.6f y se vuelve a parsear para que el C y
    # el oráculo trabajen exactamente sobre los mismos doubles.
    texts = [[f"{v:.6f}" for v in np.concatenate([p, q])] for p, q in zip(lab1, lab2)]
    parsed = np.array([[float(t) for t in row] for row in texts])
    payload = "\n".join(" ".join(row) + " 2 1 1" for row in texts) + "\n"
    got = np.array([float(x) for x in cli_output(shim, stdin=payload).split()])
    expected = np.asarray(delta_E_CIE2000(parsed[:, 0:3], parsed[:, 3:6], textiles=True), dtype=float)
    also_ref = ref.de2000(parsed[:, 0:3], parsed[:, 3:6], kL=2.0)
    err = np.abs(got - expected)
    worst = float(err.max())
    ref_gap = float(np.abs(expected - also_ref).max())
    return Check(
        name,
        "pass" if got.shape == expected.shape and worst <= tol else "fail",
        f"max |Δ| motor vs colour(textiles=True) = {worst:.2e}; colour vs reference.de2000(kL=2) = {ref_gap:.1e}",
        value=worst,
        threshold=tol,
    )


def check_edge_cases(cli: Path) -> Check:
    pairs = [
        (50.0, 0.0, 0.0, 50.0, 0.0, 0.0),  # idénticos acromáticos
        (50.0, 0.0, 0.0, 50.0, 30.0, -20.0),  # C1' = 0
        (50.0, 30.0, -20.0, 50.0, 0.0, 0.0),  # C2' = 0
        (50.0, -50.0, 0.0, 50.0, 50.0, 0.0),  # tonos opuestos (180°)
        (50.0, 50.0, 1e-9, 50.0, -50.0, -1e-9),  # justo en la discontinuidad
        (0.0, 0.0, 0.0, 100.0, 0.0, 0.0),  # negro vs blanco
    ]
    payload = "\n".join(" ".join(repr(v) for v in p) for p in pairs) + "\n"
    got = np.array([float(x) for x in cli_output(cli, "de2000", stdin=payload).split()])
    finite = bool(np.all(np.isfinite(got))) and got.shape == (len(pairs),)
    nonneg = bool(np.all(got >= 0.0)) and got[0] == 0.0
    return Check(
        "casos borde ΔE00 (C=0, hue 180°) finitos y >= 0",
        "pass" if finite and nonneg else "fail",
        "valores: " + ", ".join(f"{v:.4f}" for v in got),
    )


def golden_wada_version() -> str | None:
    if not GOLDEN_WADA_PATH.is_file():
        return None
    for line in GOLDEN_WADA_PATH.read_text(encoding="utf-8").splitlines():
        if line.startswith("# dict_version:"):
            return line.split(":", 1)[1].strip()
    return None


def check_dict_version(cli: Path, dictionary: dict[str, Any]) -> Check:
    engine = cli_output(cli, "dict", "--version").strip()
    json_v = dictionary.get("dict_version")
    golden_v = golden_wada_version()
    ok = engine == json_v == golden_v and isinstance(engine, str) and len(engine) == 12
    return Check(
        "dict_version: ce dict --version == dictionary.json == golden_wada_lab.tsv",
        "pass" if ok else "fail",
        f"motor {engine!r}, dictionary.json {json_v!r}, golden {golden_v!r}",
        value=engine,
    )


def check_dict_check(exists: bool) -> Check:
    if not exists:
        return Check("make dict-check", "skipped", "target no disponible")
    rc, out = run_make("dict-check")
    return Check("make dict-check", "pass" if rc == 0 else "fail", _tail(out, 6 if rc == 0 else 30))


def run_layer1(cli: Path, thresholds: dict[str, Any], dictionary: dict[str, Any], out_dir: Path, fast: bool, no_make: bool) -> Layer:
    t1 = thresholds["L1"]
    layer = Layer("L1", "Matemática de color", status="pending")
    checks = layer.checks

    def add(fn) -> None:
        check = timed(fn)
        checks.append(check)
        print(f"  [{check.status:>7}] {check.name}" + (f" ({check.seconds:.1f}s)" if check.seconds else ""))
        if check.status == "fail":
            print("           " + check.detail.replace("\n", "\n           "))

    if no_make:
        checks.append(Check("make test (ctest: test_math + test_dict)", "skipped", "--no-make"))
        checks.append(Check("make diff-oracle", "skipped", "--no-make"))
    else:
        add(check_make_test)
        n = int(t1["diff_oracle_colors_fast"] if fast else t1["diff_oracle_colors"])
        add(lambda: check_diff_oracle(n, float(t1["diff_oracle_abs_tol"])))
    for c in check_sharma(cli, float(t1["sharma_abs_tol"]), list(t1["sharma_pair14_accepted"])):
        checks.append(c)
        print(f"  [{c.status:>7}] {c.name}: {c.detail}")
    add(lambda: check_skimage_lax(cli, int(t1["skimage_lax_colors"]), float(t1["skimage_lax_de76_max"])))
    add(lambda: check_textiles_kl2(out_dir, int(t1["textiles_kl2_pairs"]), float(t1["textiles_kl2_abs_tol"])))
    add(lambda: check_edge_cases(cli))
    add(lambda: check_dict_version(cli, dictionary))
    if no_make:
        checks.append(Check("make dict-check", "skipped", "--no-make"))
    else:
        add(lambda: check_dict_check(make_target_exists("dict-check")))
    layer.finalize()
    return layer


# --------------------------------------------------------------------------------------
# Capa 2 (la lógica vive en oracle.l2; aquí solo se envuelve en el scorecard)
# --------------------------------------------------------------------------------------


def run_layer2(cli: Path, thresholds: dict[str, Any], out_dir: Path, fast: bool) -> Layer:
    layer = Layer("L2", "Extracción de paleta", status="pending")
    if not l2.has_palette(cli):
        layer.status = "not implemented"
        layer.checks.append(Check("ce palette", "skipped", l2.not_implemented_reason(cli)))
        print(f"L2 Extracción de paleta: not implemented ({l2.not_implemented_reason(cli)})")
        return layer
    print(f"L2 extracción de paleta ({'fast: 40 composiciones, 8 invariancias' if fast else '200 composiciones, 30 invariancias'})")
    try:
        checks, _detail = l2.run_layer2(cli, thresholds, out_dir, fast)
    except Exception as exc:  # noqa: BLE001 - el scorecard debe terminar siempre
        import traceback

        layer.checks.append(Check("oracle.l2.run_layer2", "fail", f"excepción {type(exc).__name__}: {exc}\n{traceback.format_exc()[-1500:]}"))
        print(f"  [   fail] oracle.l2.run_layer2: {type(exc).__name__}: {exc}")
        layer.finalize()
        return layer
    layer.checks = [Check(**asdict(c)) for c in checks]
    layer.finalize()
    return layer


# --------------------------------------------------------------------------------------
# Capa 3 (oracle.l3) y capa 4 (l4.run): envoltorios con la semántica skipped
# --------------------------------------------------------------------------------------


def _print_checks(checks: list[Check]) -> None:
    for c in checks:
        first = c.detail.splitlines()[0] if c.detail else ""
        print(f"  [{c.status:>7}] {c.name}" + (f" ({c.seconds:.1f}s)" if c.seconds else "") + (f": {first}" if c.status in ("skipped", "info") and first else ""))
        if c.status == "fail":
            print("           " + c.detail.replace("\n", "\n           "))


def run_layer3(cli: Path, thresholds: dict[str, Any], out_dir: Path, fast: bool) -> Layer:
    layer = Layer("L3", "Match contra el diccionario", status="pending")
    if not l3.has_match(cli):
        layer.status = "not implemented"
        reason = l3.not_implemented_reason(cli)
        layer.checks.append(Check("ce match", "skipped", reason))
        print(f"L3 Match contra el diccionario: not implemented ({reason})")
        return layer
    print(f"L3 match contra el diccionario ({'fast: 35 combinaciones' if fast else '348 combinaciones'} x 10 variantes; "
          "columnas kL1 (oficial), kL2, skin1, noadapt, illum1 y garments; giro de tono (también por el camino de prendas en harness/people); "
          "holdout si hay COLORSAPP_HOLDOUT_SEED; golden-check)")
    try:
        checks, _detail, table = l3.run_layer3(cli, thresholds, out_dir, fast, with_golden=True, log=lambda *_: None)
    except Exception as exc:  # noqa: BLE001 - el scorecard debe terminar siempre
        import traceback

        layer.checks.append(Check("oracle.l3.run_layer3", "fail", f"excepción {type(exc).__name__}: {exc}\n{traceback.format_exc()[-1500:]}"))
        print(f"  [   fail] oracle.l3.run_layer3: {type(exc).__name__}: {exc}")
        layer.finalize()
        return layer
    layer.checks = [Check(**asdict(c)) for c in checks]
    layer.markdown = table
    for c in layer.checks:
        if c.status == "skipped":
            layer.warnings.append(f"L3 {c.name}: {c.detail.splitlines()[0]}")
    _print_checks(layer.checks)
    layer.finalize()
    return layer


def run_layer4(cli: Path, thresholds: dict[str, Any], out_dir: Path) -> Layer:
    layer = Layer("L4", "Fotos reales", status="pending")
    golden_dir = l4run.golden_dir_from_env()
    if golden_dir is None:
        status, checks, detail = l4run.run_layer4(cli, thresholds, out_dir, log=lambda *_: None)
        layer.status = "skipped"
        layer.checks = [Check(**asdict(c)) for c in checks]
        layer.warnings.append(f"L4 skipped: {detail['reason']}")
        print(f"L4 Fotos reales: skipped ({detail['reason']})")
        return layer
    if not l3.has_match(cli):
        layer.status = "not implemented"
        reason = l3.not_implemented_reason(cli)
        layer.checks.append(Check("ce batch", "skipped", reason))
        print(f"L4 Fotos reales: not implemented ({reason})")
        return layer
    print(f"L4 fotos reales del set dorado ({golden_dir})")
    try:
        status, checks, detail = l4run.run_layer4(cli, thresholds, out_dir, golden_dir=golden_dir, log=lambda *_: None)
    except Exception as exc:  # noqa: BLE001
        import traceback

        layer.checks.append(Check("l4.run.run_layer4", "fail", f"excepción {type(exc).__name__}: {exc}\n{traceback.format_exc()[-1500:]}"))
        print(f"  [   fail] l4.run.run_layer4: {type(exc).__name__}: {exc}")
        layer.finalize()
        return layer
    layer.checks = [Check(**asdict(c)) for c in checks]
    layer.markdown = detail.get("variants_markdown")
    layer.data = {"variants": detail["variants"]} if detail.get("variants") else None
    _print_checks(layer.checks)
    layer.finalize()
    return layer


def add_eval_fast_budget(layers: list[Layer], thresholds: dict[str, Any], elapsed: float) -> None:
    """Presupuesto de tiempo total de ``make eval-fast`` (PLAN §6: < 2 min). Límite:
    ``thresholds.json`` L3.eval_fast_seconds_max si existe, si no L2.eval_fast_seconds_max
    (propuesta en thresholds.proposed.json). Se anota en la última capa implementada de L2/L3."""
    limit = (thresholds.get("L3") or {}).get("eval_fast_seconds_max") or (thresholds.get("L2") or {}).get("eval_fast_seconds_max")
    targets = [layer for layer in layers if layer.id in ("L2", "L3") and layer.status in ("pass", "fail")]
    if limit is None or not targets:
        return
    target = targets[-1]
    elapsed = round(elapsed, 1)
    scope = "L0 + L1 fast + L2 fast" + (" + L3 fast (35 combinaciones)" if target.id == "L3" else "")
    check = Check(
        f"make eval-fast completo < {float(limit):.0f} s (eval_fast_seconds_max)",
        "pass" if elapsed < float(limit) else "fail",
        f"{elapsed} s ({scope}, incluido make build/test)",
        value=elapsed, threshold=float(limit), seconds=elapsed,
    )
    target.checks.append(check)
    target.finalize()
    print(f"  [{check.status:>7}] {check.name}: {check.detail}")


# --------------------------------------------------------------------------------------
# Scorecard
# --------------------------------------------------------------------------------------


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_describe() -> dict[str, Any]:
    try:
        head = subprocess.run(["git", "-C", str(REPO_ROOT), "rev-parse", "--short", "HEAD"], capture_output=True, text=True, check=False)
        dirty = subprocess.run(["git", "-C", str(REPO_ROOT), "status", "--porcelain"], capture_output=True, text=True, check=False)
        return {"commit": head.stdout.strip() or None, "dirty": bool(dirty.stdout.strip())}
    except OSError:
        return {"commit": None, "dirty": None}


def versions() -> dict[str, str]:
    import colour
    import skimage

    return {
        "python": platform.python_version(),
        "numpy": np.__version__,
        "colour-science": colour.__version__,
        "scikit-image": skimage.__version__,
        "platform": platform.platform(),
    }


#: Título de la sección de markdown adicional de cada capa en scorecard.md.
MARKDOWN_TITLES = {
    "L3": "recall por degradación y columna (kL1 oficial; kL2, skin1, noadapt e illum1 informativas) y giro de tono de paletas fuera del diccionario",
    "L4": "variantes de recorte (largest-clothing-skin oficial, delta frente a none)",
}


def render_markdown(card: dict[str, Any]) -> str:
    lines: list[str] = []
    add = lines.append
    add(f"# Scorecard colorsApp — {card['generated_at']}")
    add("")
    add(f"- Motor `ce_version` {card['ce_version']} · diccionario `dict_version` {card['dict_version']} "
        f"(status {card['dict_status']}, book-verified: {'sí' if card['book_verified'] else 'no'})")
    v = card["versions"]
    add(f"- python {v['python']} · numpy {v['numpy']} · colour-science {v['colour-science']} · scikit-image {v['scikit-image']}")
    th = card["thresholds"]
    add(f"- Umbrales `{th['path']}` sha256 {th['sha256'][:12]}… (proposed_by {th['proposed_by']}, promoted_by {th['promoted_by'] or '—'})")
    g = card["git"]
    add(f"- Git {g['commit'] or '?'}{' (árbol sucio)' if g['dirty'] else ''} · modo {card['mode']} · exit {card['exit_code']}")
    add("")
    add(f"**{card['summary']}**")
    add("")
    if card.get("warnings"):
        add("> **AVISO — `skipped` (implementado pero sin datos; no cuenta como fallo, y el gate de F10 exige un scorecard sin ningún `skipped`):**")
        for w in card["warnings"]:
            add(f"> - {w}")
        add("")
    add("| Capa | Estado | Checks |")
    add("|---|---|---|")
    p = card["protected"]
    add(f"| L0 rutas protegidas | {p['status']} | {p['name']} |")
    for layer in card["layers"]:
        n_pass = sum(1 for c in layer["checks"] if c["status"] == "pass")
        n_fail = sum(1 for c in layer["checks"] if c["status"] == "fail")
        summary = f"{n_pass} pass, {n_fail} fail, {len(layer['checks']) - n_pass - n_fail} otros" if layer["checks"] else "—"
        add(f"| {layer['id']} {layer['title']} | {layer['status']} | {summary} |")
    add("")
    add("## Detalle")
    add("")
    add("| Capa | Check | Estado | Valor | Umbral | Detalle |")
    add("|---|---|---|---|---|---|")

    def cell(text: Any) -> str:
        return str(text).replace("|", "\\|").replace("\n", "<br>")

    add(f"| L0 | {cell(p['name'])} | {p['status']} | | | {cell(p['detail'])} |")
    for layer in card["layers"]:
        for c in layer["checks"]:
            value = "" if c["value"] is None else (f"{c['value']:.3e}" if isinstance(c["value"], float) else cell(c["value"]))
            thr = "" if c["threshold"] is None else cell(c["threshold"])
            add(f"| {layer['id']} | {cell(c['name'])} | {c['status']} | {value} | {thr} | {cell(c['detail'])} |")
        if not layer["checks"]:
            add(f"| {layer['id']} | — | {layer['status']} | | | |")
    for layer in card["layers"]:
        if layer.get("markdown"):
            add("")
            add(f"## {layer['id']} {layer['title']}: " + MARKDOWN_TITLES.get(layer["id"], "detalle"))
            add("")
            add(layer["markdown"])
    add("")
    return "\n".join(lines)


def build_summary(layers: list[Layer], protected: Check) -> str:
    parts: list[str] = []
    for layer in layers:
        inner_skipped = sorted({c.name.split(" (")[0] for c in layer.checks if c.status == "skipped" and layer.status != "skipped"})
        suffix = f" ({', '.join(inner_skipped)} skipped)" if inner_skipped and layer.status != "not implemented" else ""
        if layer.status == "pass":
            parts.append(f"{layer.id} OK{suffix}")
        elif layer.status == "fail":
            parts.append(f"{layer.id} FAIL{suffix}")
        elif layer.status == "skipped":
            parts.append(f"{layer.id} skipped")
    missing = [layer.id for layer in layers if layer.status == "not implemented"]
    if missing:
        rng = f"{missing[0]}-{missing[-1]}" if len(missing) > 1 else missing[0]
        parts.append(f"{rng} not implemented")
    if protected.status == "fail":
        parts.append("check-protected FAIL")
    return "; ".join(parts)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fast", action="store_true", help="L1 con diff-oracle de 10k colores y L2 con 40 composiciones y 8 invariancias")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="directorio del scorecard (harness/out)")
    ap.add_argument("--cli", type=str, default=None, help="ruta al ejecutable 'ce' (por defecto build/tools/ce)")
    ap.add_argument("--no-make", action="store_true", help="no ejecutar make test/diff-oracle/dict-check (depuración)")
    args = ap.parse_args(argv)

    out_dir: Path = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    thresholds = json.loads(THRESHOLDS_PATH.read_text(encoding="utf-8"))
    dictionary = json.loads(DICTIONARY_PATH.read_text(encoding="utf-8"))
    mode = "fast" if args.fast else "full"
    started = time.perf_counter()

    print(f"colorsApp eval ({mode}) — umbrales {THRESHOLDS_PATH.relative_to(REPO_ROOT)}")
    print("L0 rutas protegidas")
    protected = timed(check_protected)
    print(f"  [{protected.status:>7}] {protected.name}: {protected.detail.splitlines()[0] if protected.detail else ''}")

    # make test compila el CLI si hace falta; en --no-make debe existir ya.
    layers: list[Layer] = []
    print("L1 matemática de color")
    if not args.no_make:
        rc, out = run_make("build")
        if rc != 0:
            print(_tail(out, 30))
            print("eval: make build falló", file=sys.stderr)
            return 1
    cli = find_cli(args.cli)
    layers.append(run_layer1(cli, thresholds, dictionary, out_dir, args.fast, args.no_make))
    layers.append(run_layer2(cli, thresholds, out_dir, args.fast))
    layers.append(run_layer3(cli, thresholds, out_dir, args.fast))
    layers.append(run_layer4(cli, thresholds, out_dir))
    if args.fast:
        add_eval_fast_budget(layers, thresholds, time.perf_counter() - started)

    warnings = [w for layer in layers for w in layer.warnings]
    all_green = protected.ok and all(layer.status in GREEN_STATUSES for layer in layers)
    exit_code = 0 if all_green else 1
    summary = build_summary(layers, protected)
    card = {
        "schema": 1,
        "generated_at": dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds"),
        "mode": mode,
        "ce_version": cli_output(cli, "version").strip(),
        "dict_version": dictionary.get("dict_version"),
        "dict_status": dictionary.get("status"),
        "book_verified": dictionary.get("status") == "book-verified",
        "versions": versions(),
        "git": git_describe(),
        "thresholds": {
            "path": str(THRESHOLDS_PATH.relative_to(REPO_ROOT)),
            "sha256": sha256_file(THRESHOLDS_PATH),
            "proposed_by": thresholds.get("proposed_by"),
            "promoted_by": thresholds.get("promoted_by"),
        },
        "protected": asdict(protected),
        "layers": [
            {"id": layer.id, "title": layer.title, "status": layer.status, "checks": [asdict(c) for c in layer.checks],
             "warnings": layer.warnings, "markdown": layer.markdown, "data": layer.data}
            for layer in layers
        ],
        "warnings": warnings,
        "summary": summary,
        "exit_code": exit_code,
        "seconds": round(time.perf_counter() - started, 1),
    }
    (out_dir / "scorecard.json").write_text(json.dumps(card, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (out_dir / "scorecard.md").write_text(render_markdown(card), encoding="utf-8")
    print("")
    if warnings:
        print("AVISO: capas o checks `skipped` (sin datos; no cuentan como fallo, pero el gate de F10 exige ninguno):")
        for w in warnings:
            print(f"  - {w}")
    print(summary)
    print(f"scorecard: {out_dir / 'scorecard.json'} y scorecard.md ({card['seconds']} s) -> exit {exit_code}")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
