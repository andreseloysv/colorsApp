"""Genera los golden files de la capa 1 en engine/tests/data/.

    uv run --project oracle python -m oracle.gen_golden [--out DIR] [--dictionary JSON]

Semilla fija (20260914, ``numpy.random.default_rng``) para que la salida sea
reproducible. Ficheros:

* ``golden_lab.tsv``       R G B L a b        (sRGB8 -> CIELAB D65)
* ``golden_de2000.tsv``    L1 a1 b1 L2 a2 b2 dE00
* ``golden_bradford.tsv``  from to X Y Z Xa Ya Za
* ``golden_wada_lab.tsv``  index R G B L a b  (los 159 colores de
  ``data/wada/dictionary.json``; no usa la semilla). Su cabecera lleva
  ``# dict_version: <12hex>``, que ``engine/tests/test_dict.c`` cruza con
  ``ce_dict_version()``: si cambia el diccionario hay que regenerar este golden.

Formato: líneas de cabecera con ``#`` (versiones de numpy y colour), luego
filas separadas por tabuladores. Los resultados van con ``%.15e``. Las entradas
reales (Lab y XYZ) se escriben con ``%.6f`` y se vuelven a parsear ANTES de
calcular el resultado, de modo que el double sobre el que trabajó el oráculo es
exactamente el que lee el test en C con ``strtod``.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import colour

from oracle import reference as ref

SEED = 20260914
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "engine" / "tests" / "data"
DEFAULT_DICTIONARY = REPO_ROOT / "data" / "wada" / "dictionary.json"


def header(name: str, columns: str, extra: list[str] | None = None, seeded: bool = True) -> list[str]:
    origin = f"(semilla {SEED}, numpy default_rng)" if seeded else "(sin aleatoriedad)"
    lines = [
        f"# {name} — generado por oracle/oracle/gen_golden.py {origin}",
        f"# numpy {np.__version__}, colour-science {colour.__version__}, python {sys.version.split()[0]}",
        f"# columnas: {columns}",
    ]
    if extra:
        lines.extend(f"# {e}" for e in extra)
    return lines


def _reparse(values: np.ndarray, fmt: str = "%.6f") -> tuple[np.ndarray, list[list[str]]]:
    """Formatea con ``fmt`` y vuelve a parsear: devuelve (doubles, textos)."""
    texts = [[fmt % v for v in row] for row in np.atleast_2d(values)]
    parsed = np.array([[float(t) for t in row] for row in texts], dtype=float)
    return parsed, texts


def gen_lab(rng: np.random.Generator) -> list[str]:
    edge = [
        (0, 0, 0),
        (255, 255, 255),
        (255, 0, 0),
        (0, 255, 0),
        (0, 0, 255),
        (255, 255, 0),
        (0, 255, 255),
        (255, 0, 255),
        (1, 1, 1),
        (254, 254, 254),
        (1, 0, 0),
        (0, 1, 0),
        (0, 0, 1),
        (10, 10, 10),
        (11, 11, 11),
    ]
    grays = [(k, k, k) for k in range(256)]
    rand = rng.integers(0, 256, size=(2000, 3), dtype=np.int64)
    rgb8 = np.array(edge + grays + [tuple(int(v) for v in row) for row in rand], dtype=np.int64)
    lab = ref.srgb8_to_lab_strict(rgb8)
    lines = header(
        "golden_lab.tsv",
        "R G B L a b  (sRGB8 enteros -> CIELAB D65, matriz derivada, blanco xy(0.3127,0.3290))",
        [f"filas: {len(edge)} casos borde + 256 grises + 2000 aleatorios = {len(rgb8)}"],
    )
    for (r, g, b), (L, a, bb) in zip(rgb8, lab):
        lines.append(f"{r}\t{g}\t{b}\t{L:.15e}\t{a:.15e}\t{bb:.15e}")
    return lines


def gen_de2000(rng: np.random.Generator) -> list[str]:
    n = 2000
    L = rng.uniform(0.0, 100.0, size=(n, 2))
    a = rng.uniform(-128.0, 128.0, size=(n, 2))
    b = rng.uniform(-128.0, 128.0, size=(n, 2))
    pairs = np.stack([L[:, 0], a[:, 0], b[:, 0], L[:, 1], a[:, 1], b[:, 1]], axis=1)
    edge = np.array(
        [
            [50.0, 0.0, 0.0, 50.0, 0.0, 0.0],  # idénticos, acromáticos
            [50.0, 2.5, 0.0, 50.0, 2.5, 0.0],  # idénticos, cromáticos
            [50.0, 0.0, 0.0, 60.0, 0.0, 0.0],  # gris vs gris
            [50.0, 0.0, 0.0, 50.0, 30.0, -20.0],  # C1' = 0
            [50.0, 30.0, -20.0, 50.0, 0.0, 0.0],  # C2' = 0
            [0.0, 0.0, 0.0, 100.0, 0.0, 0.0],  # negro vs blanco
            [50.0, -50.0, 0.0, 50.0, 50.0, 0.0],  # tonos opuestos (180°)
            [50.0, 50.0, 1.0, 50.0, -50.0, -1.0],  # cerca de la discontinuidad
            [50.0, 50.0, -1.0, 50.0, -50.0, 1.0],
            [50.0, 0.0, -80.0, 50.0, 0.0, 80.0],
        ]
    )
    pairs = np.vstack([edge, pairs])
    parsed, texts = _reparse(pairs)
    de = ref.de2000(parsed[:, 0:3], parsed[:, 3:6])
    lines = header(
        "golden_de2000.tsv",
        "L1 a1 b1 L2 a2 b2 dE00  (Sharma/Wu/Dalal 2005, kL=kC=kH=1)",
        [f"filas: {len(edge)} casos borde + {n} pares aleatorios (L en [0,100], a,b en [-128,128])"],
    )
    for row, d in zip(texts, de):
        lines.append("\t".join(row) + f"\t{d:.15e}")
    return lines


def gen_bradford(rng: np.random.Generator) -> list[str]:
    n = 20
    xyz = np.stack(
        [
            rng.uniform(0.0, 1.1, size=n),
            rng.uniform(0.0, 1.0, size=n),
            rng.uniform(0.0, 1.1, size=n),
        ],
        axis=1,
    )
    parsed, texts = _reparse(xyz)
    lines = header(
        "golden_bradford.tsv",
        "from to X Y Z Xa Ya Za  (adaptación Bradford, iluminantes CIE 015:2004 obs. 2°)",
        [f"filas: {n} XYZ aleatorios x 4 destinos (D65->A, D65->D50, D65->F2, D65->D75)"],
    )
    for dst in ("A", "D50", "F2", "D75"):
        adapted = ref.xyz_adapt(parsed, "D65", dst)
        for row, out in zip(texts, adapted):
            lines.append(f"D65\t{dst}\t" + "\t".join(row) + "\t" + "\t".join(f"{v:.15e}" for v in out))
    return lines


def gen_wada_lab(dictionary_path: Path) -> list[str]:
    """Lab D65 (oráculo estricto) de los colores de ``dictionary.json``, con su dict_version."""
    doc = json.loads(dictionary_path.read_text(encoding="utf-8"))
    colors = doc["colors"]
    version = doc["dict_version"]
    rgb8 = np.array([c["rgb"] for c in colors], dtype=np.int64)
    lab = ref.srgb8_to_lab_strict(rgb8)
    lines = header(
        "golden_wada_lab.tsv",
        "index R G B L a b  (colores del diccionario de Wada, sRGB8 -> CIELAB D65 con el oráculo estricto)",
        [
            f"dict_version: {version}",
            f"filas: {len(colors)} colores de {dictionary_path.name} (status {doc.get('status')}); "
            "el test C exige dict_version == ce_dict_version()",
        ],
        seeded=False,
    )
    for color, (L, a, b) in zip(colors, lab):
        r, g, bb = color["rgb"]
        lines.append(f"{color['index']}\t{r}\t{g}\t{bb}\t{L:.15e}\t{a:.15e}\t{b:.15e}")
    return lines


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="directorio de salida")
    ap.add_argument("--dictionary", type=Path, default=DEFAULT_DICTIONARY, help="dictionary.json de Wada")
    args = ap.parse_args(argv)
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)

    rng = np.random.default_rng(SEED)
    files = {
        "golden_lab.tsv": gen_lab(rng),
        "golden_de2000.tsv": gen_de2000(rng),
        "golden_bradford.tsv": gen_bradford(rng),
        "golden_wada_lab.tsv": gen_wada_lab(args.dictionary),
    }
    for name, lines in files.items():
        path = out / name
        path.write_text("\n".join(lines) + "\n")
        rows = sum(1 for l in lines if not l.startswith("#"))
        print(f"{path}: {rows} filas, {path.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
