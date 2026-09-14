"""Differential testing masivo: motor C (``ce convert``) contra el oráculo estricto.

    uv run --project oracle python -m oracle.diff_oracle [--n 100000] [--cli PATH] [--seed S]

Genera N colores sRGB8 aleatorios, los pasa por ``ce convert`` (stdin/stdout)
y por ``reference.srgb8_to_lab_strict``, e imprime el máximo |ΔL|, |Δa|, |Δb| y
cuántos triples superan la tolerancia (1e-9). Código de salida 1 si alguno la
supera.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np

from oracle import reference as ref

REPO_ROOT = Path(__file__).resolve().parents[2]
TOLERANCE = 1e-9


def find_cli(explicit: str | None) -> Path:
    candidates = [Path(explicit)] if explicit else []
    candidates += [
        REPO_ROOT / "build" / "tools" / "ce",
        REPO_ROOT / "build" / "ce",
        REPO_ROOT / "engine" / "build" / "tools" / "ce",
    ]
    for c in candidates:
        if c.is_file():
            return c
    raise SystemExit(
        "no encuentro el CLI 'ce'; compila con 'make test' o pasa --cli PATH (probé: "
        + ", ".join(str(c) for c in candidates)
        + ")"
    )


def run_cli(cli: Path, rgb8: np.ndarray) -> np.ndarray:
    payload = "\n".join(f"{r} {g} {b}" for r, g, b in rgb8) + "\n"
    proc = subprocess.run(
        [str(cli), "convert"],
        input=payload,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SystemExit(f"'{cli} convert' devolvió {proc.returncode}: {proc.stderr}")
    out = np.array([[float(v) for v in line.split()] for line in proc.stdout.splitlines() if line.strip()])
    if out.shape != (len(rgb8), 3):
        raise SystemExit(f"salida inesperada del CLI: forma {out.shape}, esperaba {(len(rgb8), 3)}")
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--n", type=int, default=100_000, help="número de colores aleatorios")
    ap.add_argument("--cli", type=str, default=None, help="ruta al ejecutable 'ce'")
    ap.add_argument("--seed", type=int, default=20260914, help="semilla del generador")
    ap.add_argument("--tol", type=float, default=TOLERANCE, help="tolerancia absoluta por componente")
    args = ap.parse_args(argv)

    cli = find_cli(args.cli)
    rng = np.random.default_rng(args.seed)
    rgb8 = rng.integers(0, 256, size=(args.n, 3), dtype=np.int64)

    got = run_cli(cli, rgb8)
    expected = ref.srgb8_to_lab_strict(rgb8)

    diff = np.abs(got - expected)
    max_per_component = diff.max(axis=0)
    bad = np.any(diff > args.tol, axis=1)
    n_bad = int(bad.sum())

    print(f"cli: {cli}")
    print(f"colores: {args.n}  semilla: {args.seed}  tolerancia: {args.tol:g}")
    print(f"max |dL| = {max_per_component[0]:.3e}")
    print(f"max |da| = {max_per_component[1]:.3e}")
    print(f"max |db| = {max_per_component[2]:.3e}")
    print(f"triples que superan la tolerancia: {n_bad}")
    if n_bad:
        idx = np.flatnonzero(bad)[:10]
        for i in idx:
            print(f"  rgb={tuple(int(v) for v in rgb8[i])} ce={got[i]} oracle={expected[i]} diff={diff[i]}")
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
