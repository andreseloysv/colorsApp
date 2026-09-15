"""Fixtures deterministas de la paridad nativo/WASM (fase 5; ``make parity-fixtures``).

    uv run --project oracle python harness/wasm/make_fixtures.py --out harness/wasm/fixtures
    uv run --project oracle python harness/wasm/make_fixtures.py --check   # regenera aparte y compara sha256

Escribe 20 PPM (P6, lados <= 128) y ``manifest.json`` (una entrada por imagen con
``file``, ``width``, ``height``, ``note``, ``args`` extra para ``ce match`` y ``sha256``).
``harness/wasm/run_parity.js`` ejecuta ``ce match --json`` nativo y WASM sobre cada uno
y compara swatches (Lab, weight), top-3 (ids, scores) y ``ambiguous``.

Toda la aleatoriedad sale de ``numpy.random.default_rng`` con semillas fijas; los
colores de diccionario vienen de ``data/wada/dictionary.json`` (vía ``synth.wada_gen``),
la geometría y la E/S PNM de ``synth.compose`` / ``synth.wada_gen``. Misma máquina,
mismos bytes (el JPEG de Pillow y el ruido opensimplex quedan fijados por las versiones
que ``wada_gen.generator_hash`` incorpora al manifest).

Qué cubre cada fixture (los casos que más separan a las dos libm: cbrt/pow en Lab,
atan2/sin/cos/exp en ΔE00, y la fusión de colores casi iguales del diccionario):

  p01 gris uniforme (a = b ~ 0: h' indefinido, C' = 0)      p11 combo 282 (Maple) + ruido σ = 2
  p02 rampa de grises 128x40 (no cuadrada, varios swatches   p12 compose seed 7 (colores no diccionario)
      acromáticos que se fusionan)                           p13 compose seed 13 anidado + ruido σ = 3
  p03 un solo color del diccionario (Black, 23 combinaciones) p14 wada_gen v2 textura (combo 100)
      con --coverage-lambda 0: 23 empates a 0 -> orden por id p15 wada_gen v4 iluminante A (combo 200)
  p04 Isabella Color vs Maple (ΔE00 2,68 < merge_de 5)       p16 wada_gen v7 JPEG (combo 300)
  p05 Peacock Blue vs Green Blue (ΔE00 1,01)                 p17 wada_gen v9 distractor (combo 348)
  p06 Carmine Red vs Pompeian Red (ΔE00 1,80),               p18 primarios y secundarios sRGB puros
      --ambiguous-gap 30 fuerza ambiguous = 1                     (bordes del gamut)
  p07 combo 4 exacto, --center-sigma 0 (score 0 exacto)      p19 casi negro / casi blanco (umbral 0,04045
  p08 combo 12 anidado (2 colores)                                de la curva sRGB, cbrt cerca de 0)
  p09 combo 241 en L (4 colores)                              p20 3x2 píxeles, 6 colores del diccionario
  p10 combo 292 elipses (4 colores), --kL 2                        (k_init 6 > max_colors 5, recorte)
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import numpy as np

from synth import compose as sc
from synth import wada_gen as wg

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = Path(__file__).resolve().parent / "fixtures"
DEFAULT_CHECK_DIR = REPO_ROOT / "harness" / "out" / "wasm_fixtures_check"
SIZE = 128
TOP_K = 3
TOLERANCE = 1e-9
SCHEMA = 1


# --------------------------------------------------------------------------------------
# Utilidades de composición (imágenes HxWx3 uint8)
# --------------------------------------------------------------------------------------


def _paint(labels: np.ndarray, palette: np.ndarray) -> np.ndarray:
    """Etiquetas ``HxW`` (índice en ``palette``) -> imagen sRGB8."""
    return np.ascontiguousarray(palette[labels].astype(np.uint8))


def uniform(rgb: tuple[int, int, int], w: int, h: int) -> np.ndarray:
    return np.ascontiguousarray(np.full((h, w, 3), rgb, dtype=np.uint8))


def gray_ramp(w: int, h: int, lo: int, hi: int) -> np.ndarray:
    """Rampa horizontal de grises enteros ``lo..hi`` (columna a columna, redondeo)."""
    xs = np.rint(np.linspace(lo, hi, w)).astype(np.uint8)
    img = np.repeat(xs[None, :, None], h, axis=0)
    return np.ascontiguousarray(np.repeat(img, 3, axis=2))


def blocks(colors: list[tuple[int, int, int]], w: int, h: int, cols: int) -> np.ndarray:
    """Rejilla de bloques (``cols`` por fila) con un color cada uno, en orden."""
    rows = (len(colors) + cols - 1) // cols
    img = np.zeros((h, w, 3), dtype=np.uint8)
    for i, rgb in enumerate(colors):
        r, c = divmod(i, cols)
        y0, y1 = r * h // rows, (r + 1) * h // rows
        x0, x1 = c * w // cols, (c + 1) * w // cols
        img[y0:y1, x0:x1] = rgb
    return np.ascontiguousarray(img)


def stripes(colors: list[int], props: list[float], w: int, h: int, seed: int, d: dict[str, Any]) -> np.ndarray:
    rng = np.random.default_rng(seed)
    labels = wg.layout_stripes(rng, len(colors), np.asarray(props, dtype=float), w, h)
    return _paint(labels, d["rgbs"][colors])


def nested(colors: list[int], props: list[float], w: int, h: int, seed: int, d: dict[str, Any]) -> np.ndarray:
    rng = np.random.default_rng(seed)
    labels = wg.layout_nested(rng, len(colors), np.asarray(props, dtype=float), w, h)
    return _paint(labels, d["rgbs"][colors])


def l_shape(colors: list[int], props: list[float], w: int, h: int, seed: int, d: dict[str, Any]) -> np.ndarray:
    rng = np.random.default_rng(seed)
    labels = wg.layout_l_shape(rng, len(colors), np.asarray(props, dtype=float), w, h)
    return _paint(labels, d["rgbs"][colors])


def ellipses(colors: list[int], props: list[float], w: int, h: int, seed: int, d: dict[str, Any]) -> np.ndarray:
    rng = np.random.default_rng(seed)
    labels = wg.layout_ellipses(rng, len(colors), np.asarray(props, dtype=float), w, h)
    return _paint(labels, d["rgbs"][colors])


def _color(d: dict[str, Any], name: str) -> int:
    """Índice del color del diccionario por nombre exacto (error si no existe)."""
    for c in d["colors"]:
        if c["name"] == name:
            return int(c["index"])
    raise KeyError(f"color {name!r} no está en el diccionario")


# --------------------------------------------------------------------------------------
# Las 20 fixtures
# --------------------------------------------------------------------------------------


def build_fixtures(size: int = SIZE) -> list[dict[str, Any]]:
    """Lista ordenada de ``{"file", "note", "args", "img", ...}`` (la imagen aún en memoria)."""
    d = wg.load_dictionary()
    s = int(size)
    isabella, maple = _color(d, "Isabella Color"), _color(d, "Maple")
    peacock, green_blue = _color(d, "Peacock Blue"), _color(d, "Green Blue")
    carmine, pompeian = _color(d, "Carmine Red"), _color(d, "Pompeian Red")
    black = _color(d, "Black")

    def combo(cid: int) -> list[int]:
        return [int(i) for i in d["combos_by_id"][int(cid)]["colors"]]

    fx: list[dict[str, Any]] = []

    def add(file: str, img: np.ndarray, note: str, args: list[str] | None = None, **extra: Any) -> None:
        fx.append({"file": file, "note": note, "args": list(args or []), "img": np.ascontiguousarray(img, dtype=np.uint8), **extra})

    # p01/p02: acromáticos (h' indefinido, C' = 0 en ΔE00; cbrt en la rama lineal de Lab).
    add("p01_gray_uniform.ppm", uniform((128, 128, 128), s, s),
        "gris uniforme (128,128,128): un swatch, a = b ~ 0")
    add("p02_gray_ramp_128x40.ppm", gray_ramp(s, 40, 20, 235),
        "rampa de grises 20..235, 128x40 (no cuadrada): swatches acromáticos fusionados")

    # p03: un solo color del diccionario presente en 23 combinaciones; con lambda = 0 todas
    # empatan a score 0 y el orden debe ser por id en las dos plataformas.
    add("p03_black_lambda0.ppm", uniform(tuple(int(v) for v in d["rgbs"][black]), s, s),
        "Black (color 158, en 23 combinaciones) con --coverage-lambda 0: empate a 0, orden por id",
        ["--coverage-lambda", "0"], colors=[black])

    # p04-p06: pares casi indistinguibles del diccionario (ΔE00 < merge_de = 5): la paleta
    # los fusiona en un swatch intermedio y el match decide entre combinaciones distintas.
    add("p04_isabella_vs_maple.ppm", stripes([isabella, maple, combo(4)[1]], [0.45, 0.45, 0.10], s, s, 104, d),
        "Isabella Color (50) 45 % + Maple (51) 45 % (ΔE00 2,68, se fusionan) + color 150 10 %",
        colors=[isabella, maple, combo(4)[1]])
    add("p05_peacock_vs_greenblue.ppm", stripes([peacock, green_blue, combo(131)[0], combo(131)[1]], [0.35, 0.35, 0.15, 0.15], s, s, 105, d),
        "Peacock Blue (118) vs Green Blue (119), ΔE00 1,01, con los otros dos colores de la combinación 131",
        colors=[peacock, green_blue, combo(131)[0], combo(131)[1]])
    add("p06_carmine_vs_pompeian_gap30.ppm", nested([carmine, pompeian, combo(35)[0]], [0.5, 0.3, 0.2], s, s, 106, d),
        "Carmine Red (28) vs Pompeian Red (29), ΔE00 1,80, anidados; --ambiguous-gap 30 fuerza ambiguous = 1",
        ["--ambiguous-gap", "30"], colors=[carmine, pompeian, combo(35)[0]])

    # p07-p10: combinaciones exactas del diccionario con las cuatro geometrías.
    add("p07_c004_stripes_sigma0.ppm", stripes(combo(4), [0.5, 0.5], s, s, 107, d),
        "combinación 4 exacta en franjas, --center-sigma 0: sumas enteras, score 0 exacto",
        ["--center-sigma", "0"], combo_id=4, colors=combo(4))
    add("p08_c012_nested.ppm", nested(combo(12), [0.6, 0.4], s, s, 108, d),
        "combinación 12 (Isabella Color + Green Blue) anidada, peso al centro", combo_id=12, colors=combo(12))
    add("p09_c241_lshape.ppm", l_shape(combo(241), [0.4, 0.25, 0.2, 0.15], s, s, 109, d),
        "combinación 241 (4 colores) en L", combo_id=241, colors=combo(241))
    add("p10_c292_ellipses_kL2.ppm", ellipses(combo(292), [0.4, 0.25, 0.2, 0.15], s, s, 110, d),
        "combinación 292 (4 colores) en elipses, --kL 2", ["--kL", "2"], combo_id=292, colors=combo(292))

    # p11-p13: ruido gaussiano (compose.add_noise) y colores fuera del diccionario (compose).
    add("p11_c282_stripes_noise2.ppm", sc.add_noise(stripes(combo(282), [0.3, 0.3, 0.2, 0.2], s, s, 111, d), sigma=2.0, seed=111),
        "combinación 282 (con Maple) en franjas + ruido σ = 2", combo_id=282, colors=combo(282))
    img12, _truth12 = sc.compose(seed=7, size=(s, s), layout="50/30/20")
    add("p12_compose_seed7.ppm", img12, "synth.compose seed 7 (franjas, tres colores aleatorios fuera del diccionario)")
    img13, _truth13 = sc.compose(seed=13, size=(s, s), layout="40/35/25")
    add("p13_compose_seed13_noise3.ppm", sc.add_noise(img13, sigma=3.0, seed=13),
        "synth.compose seed 13 (anidado, 40/35/25) + ruido σ = 3")

    # p14-p17: degradaciones de wada_gen (textura opensimplex, iluminante A, JPEG, distractor).
    for file, cid, v, note in (
        ("p14_wada_c100_v2_texture.ppm", 100, 2, "wada_gen combo 100 v2: textura opensimplex ±6 L*"),
        ("p15_wada_c200_v4_illumA.ppm", 200, 4, "wada_gen combo 200 v4: Bradford D65 -> A"),
        ("p16_wada_c300_v7_jpeg.ppm", 300, 7, "wada_gen combo 300 v7: JPEG (q por semilla)"),
        ("p17_wada_c348_v9_distractor.ppm", 348, 9, "wada_gen combo 348 v9: distractor 40 %"),
    ):
        img, meta = wg.variant(cid, v, seed_base=0, size=s, dictionary=d)
        add(file, img, note, combo_id=cid, colors=meta["colors"], variant=meta["variant"])

    # p18-p20: bordes del gamut, umbral de la curva sRGB y una imagen minúscula.
    add("p18_primaries.ppm",
        blocks([(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0), (255, 0, 255), (0, 255, 255)], s, s, 3),
        "primarios y secundarios sRGB puros en 6 bloques (bordes del gamut, |a|, |b| ~ 100)")
    add("p19_near_black_white_64.ppm",
        blocks([(0, 0, 0), (1, 1, 1), (3, 3, 3), (11, 11, 11), (254, 254, 254), (255, 255, 255)], 64, 64, 3),
        "negro, casi negro (1, 3, 11: alrededor del umbral 0,04045 de sRGB) y casi blanco, 64x64")
    six = [combo(300)[0], combo(300)[1], combo(300)[2], combo(300)[3], combo(4)[0], combo(4)[1]]
    add("p20_tiny_3x2_six_colors.ppm", np.asarray(d["rgbs"][six], dtype=np.uint8).reshape(2, 3, 3),
        "3x2 píxeles con 6 colores del diccionario distintos (k_init 6 > max_colors 5: recorte y renormalización)",
        colors=six)

    assert len(fx) == 20, len(fx)
    for f in fx:
        h, w, _ = f["img"].shape
        assert 1 <= w <= SIZE and 1 <= h <= SIZE, (f["file"], w, h)
        f["width"], f["height"] = int(w), int(h)
    return fx


# --------------------------------------------------------------------------------------
# Escritura, manifest y comprobación
# --------------------------------------------------------------------------------------


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_set(out_dir: Path, size: int = SIZE) -> dict[str, Any]:
    """Escribe los 20 PPM y ``manifest.json`` en ``out_dir`` (borra PPM anteriores); devuelve el manifest."""
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("*.ppm"):
        old.unlink()
    entries: list[dict[str, Any]] = []
    for f in build_fixtures(size):
        path = sc.write_ppm(f["img"], out_dir / f["file"])
        entry = {k: v for k, v in f.items() if k != "img"}
        entry["sha256"] = sha256_file(path)
        entries.append(entry)
    manifest = {
        "schema": SCHEMA,
        "kind": "wasm_parity_fixtures",
        "generator": "harness/wasm/make_fixtures.py",
        "dict_version": wg.dict_version(),
        "wada_gen_hash": wg.generator_hash(),
        "max_side": int(size),
        "top_k": TOP_K,
        "tolerance": TOLERANCE,
        "n": len(entries),
        "entries": entries,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    return manifest


def check_set(out_dir: Path, tmp_dir: Path, size: int = SIZE) -> int:
    """Regenera en ``tmp_dir`` y compara sha256 y metadatos con ``out_dir/manifest.json``; 0 si idénticos."""
    manifest_path = out_dir / "manifest.json"
    if not manifest_path.is_file():
        print(f"make_fixtures --check: falta {manifest_path}", file=sys.stderr)
        return 1
    current = json.loads(manifest_path.read_text(encoding="utf-8"))
    fresh = write_set(tmp_dir, size)
    bad = 0
    cur_by_file = {e["file"]: e for e in current.get("entries", [])}
    for e in fresh["entries"]:
        c = cur_by_file.get(e["file"])
        if c is None:
            print(f"  FALTA en manifest: {e['file']}")
            bad += 1
            continue
        on_disk = out_dir / e["file"]
        disk_sha = sha256_file(on_disk) if on_disk.is_file() else None
        if c["sha256"] != e["sha256"] or disk_sha != e["sha256"] or c.get("args") != e["args"]:
            print(f"  DIFIERE: {e['file']} manifest={c['sha256'][:12]} disco={(disk_sha or '-')[:12]} regenerado={e['sha256'][:12]}")
            bad += 1
    extra = set(cur_by_file) - {e["file"] for e in fresh["entries"]}
    for name in sorted(extra):
        print(f"  SOBRA en manifest: {name}")
        bad += 1
    for key in ("dict_version", "wada_gen_hash", "n", "max_side"):
        if current.get(key) != fresh.get(key):
            print(f"  cabecera {key}: manifest={current.get(key)!r} regenerado={fresh.get(key)!r}")
            bad += 1
    if bad:
        print(f"make_fixtures --check: {bad} discrepancias (regenera con `make parity-fixtures`)")
        return 1
    print(f"make_fixtures --check: {fresh['n']} fixtures idénticas byte a byte (dict_version {fresh['dict_version']})")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="directorio de las fixtures (PPM + manifest.json)")
    ap.add_argument("--check", action="store_true", help="regenera aparte y compara sha256 con --out (exit 1 si difieren)")
    ap.add_argument("--tmp", type=Path, default=DEFAULT_CHECK_DIR, help="directorio de trabajo de --check (gitignored)")
    ap.add_argument("--size", type=int, default=SIZE, help="lado máximo de las fixtures (<= 128)")
    args = ap.parse_args(argv)
    if args.size < 8 or args.size > SIZE:
        print(f"--size debe estar en 8..{SIZE}", file=sys.stderr)
        return 2
    if args.check:
        return check_set(args.out, args.tmp, args.size)
    manifest = write_set(args.out, args.size)
    total = sum((args.out / e["file"]).stat().st_size for e in manifest["entries"])
    print(f"make_fixtures: {manifest['n']} PPM en {args.out} ({total} bytes, dict_version {manifest['dict_version']}, "
          f"wada_gen {manifest['wada_gen_hash']})")
    for e in manifest["entries"]:
        extra = " " + " ".join(e["args"]) if e["args"] else ""
        print(f"  {e['file']:36} {e['width']:3d}x{e['height']:<3d} {e['sha256'][:12]}{extra}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
