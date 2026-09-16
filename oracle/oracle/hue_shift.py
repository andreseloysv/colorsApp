"""Métrica de giro de tono de la capa 3 (gate de «falsa adaptación», ADR-009).

    uv run --project oracle python -m oracle.hue_shift [--cli build/tools/ce] [--out harness/out]
                                                       [--n 2000] [--no-people]

Motivo (CONTEXT §11): con la hipótesis de iluminante activada, la paleta real rosa palo + negro
de una foto ya balanceada ganaba Nº 067 (azules): el match «compensaba» una luz de tungsteno
inexistente y el tono de la ropa giraba ~87°. Los sintéticos de ``wada_gen`` no lo detectan
porque solo contienen colores del diccionario; esta métrica usa **paletas realistas que no son
del diccionario** y mide si una configuración del match gira el tono respecto al match v0.

Paletas (deterministas, ``numpy.random.default_rng(20260915)``; se generan en Lab, se llevan a
sRGB8 con clamp y se vuelven a medir, como saldrían de una foto):

- ``apagados``: 2-4 colores con L* 25-75 y C*ab 6-22, tonos independientes.
- ``pasteles``: 2-4 colores con L* 75-92 y C*ab 8-28.
- ``tierras``: 2-4 colores con hab 20-90° (marrones, ocres, oliva), L* 20-65, C*ab 10-40.
- ``neutro_mas_color``: 1-2 negros/grises/blancos (C*ab < 3) que pesan 40-70 % + un color de
  cualquier familia (incluidos saturados).
- ``sombras_de_prenda``: un color + 1-3 sombras suyas (ΔL* ±6-20, croma ×0,7-1,1, tono ±8°) y un
  neutro del 25-50 % (el caso del pantalón rosa).
- ``people:<variante>`` (si hay datos): la paleta de ``ce palette`` de cada foto de
  ``harness/people`` sin máscara y con las máscaras de ``harness/out/people-masks``
  (``make visionmask-people``), cuando existen.
- ``people-garments:<variante>`` (si hay máscara y pose): la paleta por prenda de ``ce garments``
  con las regiones de ``ce garment-regions`` (silueta corporal de la pose): el camino de la app
  cuando hay regiones.

Pesos Dirichlet(1,5) con mínimo 0,05. **Fuera del diccionario**: se descartan las paletas cuyo
top-1 del match v0 puntúa < 3,0 (casi una combinación de Wada exacta); se generan candidatas
hasta tener ``--n`` sintéticas.

Métrica por configuración (``defaults`` = ``ce_match_opts_default``; ``iluminante`` = defaults +
``illuminant_search`` 1; referencia ``v0`` = sin hipótesis, exposición 0 e iluminante 0): swatch
cromático dominante ``s`` = el más pesado con C*ab >= 8 (paletas sin él no cuentan); ``n`` = color
de la combinación top-1 más cercano a ``s`` por ΔE00 (sin adaptar: lo que ve el usuario). Hay
**giro de tono** si ``C*ab(n) >= 8`` y ``|Δhab(s, n)| > 60°`` con la configuración y no con v0.
``hue_shift_rate`` = paletas con giro / paletas evaluadas. Gate de L3 (``oracle.l3``): la tasa
de ``defaults`` <= ``L3.hue_shift_max`` (0,01 propuesto en ``harness/out/thresholds.proposed.json``,
no promovido); ``iluminante`` es informativa.

Salida: ``<out>/hue_shift.json`` (parámetros, tasas por configuración y familia, ejemplos).
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import numpy as np

from oracle import reference as ref
from synth import compose as sc
from synth import wada_gen as wg

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "harness" / "out"
PEOPLE_DIR = REPO_ROOT / "harness" / "people"
PEOPLE_MASKS_DIR = REPO_ROOT / "harness" / "out" / "people-masks"

SEED = 20260915
N_PALETTES = 2000
HUE_SHIFT_DEG = 60.0
CHROMA_MIN = 8.0
OUT_OF_DICT_MIN_SCORE = 3.0
MIN_WEIGHT = 0.05
FAMILIES: tuple[str, ...] = ("apagados", "pasteles", "tierras", "neutro_mas_color", "sombras_de_prenda")
#: Opciones de match (flags de ``ce``) de la referencia y de cada configuración reportada.
REFERENCE = "v0"
CONFIGS: dict[str, dict[str, Any]] = {
    "v0": {"exposure_ev_max": 0.0, "illuminant_search": 0},
    "defaults": {},
    "iluminante": {"illuminant_search": 1},
}
REPORTED: tuple[str, ...] = ("defaults", "iluminante")
PEOPLE_MASK_VARIANTS: tuple[str, ...] = ("allPeople", "largest", "largest-clothing", "largest-clothing-skin")


class HueShiftError(RuntimeError):
    """``ce match-palette`` no existe o devolvió algo inesperado."""


# --------------------------------------------------------------------------------------
# Color
# --------------------------------------------------------------------------------------


def hue_deg(lab: np.ndarray) -> np.ndarray:
    lab = np.asarray(lab, dtype=float)
    return np.mod(np.degrees(np.arctan2(lab[..., 2], lab[..., 1])), 360.0)


def chroma(lab: np.ndarray) -> np.ndarray:
    lab = np.asarray(lab, dtype=float)
    return np.hypot(lab[..., 1], lab[..., 2])


def hue_diff_deg(h1: float, h2: float) -> float:
    d = abs(float(h1) - float(h2)) % 360.0
    return 360.0 - d if d > 180.0 else d


def _lab_from_lch(L: float, C: float, h_deg: float) -> list[float]:
    h = math.radians(h_deg)
    return [float(L), float(C) * math.cos(h), float(C) * math.sin(h)]


# --------------------------------------------------------------------------------------
# Paletas sintéticas realistas
# --------------------------------------------------------------------------------------


def _weights(rng: np.random.Generator, n: int) -> np.ndarray:
    w = rng.dirichlet(np.full(n, 1.5))
    w = np.maximum(w, MIN_WEIGHT)
    return np.sort(w / w.sum())[::-1]


def _color_of(rng: np.random.Generator, family: str) -> list[float]:
    if family == "apagados":
        return _lab_from_lch(rng.uniform(25, 75), rng.uniform(6, 22), rng.uniform(0, 360))
    if family == "pasteles":
        return _lab_from_lch(rng.uniform(75, 92), rng.uniform(8, 28), rng.uniform(0, 360))
    if family == "tierras":
        return _lab_from_lch(rng.uniform(20, 65), rng.uniform(10, 40), rng.uniform(20, 90))
    if family == "saturados":
        return _lab_from_lch(rng.uniform(30, 70), rng.uniform(25, 60), rng.uniform(0, 360))
    raise ValueError(family)


def _neutral(rng: np.random.Generator) -> list[float]:
    band = int(rng.integers(0, 4))
    L = (rng.uniform(5, 20), rng.uniform(25, 45), rng.uniform(50, 70), rng.uniform(80, 95))[band]
    return _lab_from_lch(L, rng.uniform(0, 3), rng.uniform(0, 360))


def sample_palette(rng: np.random.Generator, family: str) -> tuple[list[list[float]], list[float]]:
    """(Lab nominales, pesos) de una paleta de ``family``."""
    if family in ("apagados", "pasteles", "tierras"):
        n = int(rng.integers(2, 5))
        return [_color_of(rng, family) for _ in range(n)], _weights(rng, n).tolist()
    if family == "neutro_mas_color":
        n_neutral = int(rng.integers(1, 3))
        labs = [_neutral(rng) for _ in range(n_neutral)]
        labs.append(_color_of(rng, ("apagados", "pasteles", "tierras", "saturados")[int(rng.integers(0, 4))]))
        w_neutral = rng.uniform(0.40, 0.70)
        parts = rng.dirichlet(np.full(n_neutral, 2.0)) * w_neutral if n_neutral > 1 else np.array([w_neutral])
        w = np.concatenate([parts, [1.0 - w_neutral]])
        w = np.maximum(w, MIN_WEIGHT)
        return labs, (w / w.sum()).tolist()
    if family == "sombras_de_prenda":
        base_family = ("apagados", "pasteles", "tierras", "saturados")[int(rng.integers(0, 4))]
        L, a, b = _color_of(rng, base_family)
        C, h = math.hypot(a, b), math.degrees(math.atan2(b, a))
        labs = [[L, a, b]]
        for _ in range(int(rng.integers(1, 4))):
            dL = rng.uniform(6, 20) * (1 if rng.integers(0, 2) else -1)
            labs.append(_lab_from_lch(min(95.0, max(5.0, L + dL)), C * rng.uniform(0.7, 1.1), h + rng.uniform(-8, 8)))
        garment = _weights(rng, len(labs)) * (1.0 - (w_neutral := rng.uniform(0.25, 0.50)))
        labs.append(_neutral(rng))
        w = np.concatenate([garment, [w_neutral]])
        w = np.maximum(w, MIN_WEIGHT)
        return labs, (w / w.sum()).tolist()
    raise ValueError(f"familia desconocida {family!r}")


def _to_srgb8(labs: list[list[float]]) -> tuple[np.ndarray, np.ndarray]:
    rgb = sc.lab_to_srgb8(np.asarray(labs, dtype=float)).astype(np.int64)
    return rgb, np.asarray(ref.srgb8_to_lab_strict(rgb), dtype=float).reshape(-1, 3)


def synthetic_candidates(rng: np.random.Generator, start: int, count: int) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for i in range(start, start + count):
        family = FAMILIES[i % len(FAMILIES)]
        labs, weights = sample_palette(rng, family)
        rgb, lab = _to_srgb8(labs)
        tokens = " ".join(f"#{r:02x}{g:02x}{b:02x}:{w!r}" for (r, g, b), w in zip(rgb.tolist(), weights))
        out.append({"index": i, "family": family, "hex": [f"#{r:02x}{g:02x}{b:02x}" for r, g, b in rgb.tolist()],
                    "lab": lab, "weights": list(map(float, weights)), "tokens": tokens})
    return out


# --------------------------------------------------------------------------------------
# Paletas de harness/people
# --------------------------------------------------------------------------------------


def _palette_json(cli: Path, image: Path, mask: Path | None) -> dict[str, Any] | None:
    args = [str(cli), "palette", str(image), "--json"] + (["--mask", str(mask)] if mask is not None else [])
    proc = subprocess.run(args, capture_output=True, text=True, check=False, timeout=120)
    if proc.returncode != 0:
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def _garment_json(cli: Path, image: Path, mask: Path, pose: Path, regions: Path) -> dict[str, Any] | None:
    """``ce garment-regions`` (silueta de la pose, como oracle.garments) + ``ce garments --regions``."""
    from oracle import garments as gm

    h, w = sc.read_ppm(image).shape[:2]
    proc = subprocess.run([str(cli), "garment-regions", "--size", f"{w}x{h}", "--mask", str(mask), "--pose", str(pose),
                           "--out", str(regions), *gm.PEOPLE_REGION_ARGS], capture_output=True, text=True, check=False,
                          timeout=120)
    if proc.returncode != 0:
        return None
    try:
        return gm.run_garments(cli, image, mask=mask, regions=regions)
    except gm.GarmentError:
        return None


def people_palettes(cli: Path, people_dir: Path = PEOPLE_DIR, masks_dir: Path = PEOPLE_MASKS_DIR,
                    log=None) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Paletas de las fotos de ``harness/people`` (sin máscara y con las máscaras de visionmask si existen)."""
    import tempfile

    info: dict[str, Any] = {"people_dir": str(people_dir), "masks_dir": str(masks_dir), "photos": 0, "masks_used": 0}
    out: list[dict[str, Any]] = []
    photos = sorted(people_dir.glob("*.png")) if people_dir.is_dir() else []
    if not photos:
        info["status"] = "sin fotos"
        return out, info
    from PIL import Image

    with tempfile.TemporaryDirectory(prefix="colorsapp-hue-") as tmp:
        for photo in photos:
            stem = photo.stem
            raster = masks_dir / f"{stem}.ppm"
            if raster.is_file():
                image = raster
            else:
                image = Path(tmp) / f"{stem}.ppm"
                sc.write_ppm(np.asarray(Image.open(photo).convert("RGB"), dtype=np.uint8), image)
            sources: list[tuple[str, Path | None]] = [("none", None)]
            for variant in PEOPLE_MASK_VARIANTS:
                mask = masks_dir / f"{stem}.{variant}.pgm"
                if raster.is_file() and mask.is_file():
                    sources.append((variant, mask))
            info["photos"] += 1
            for variant, mask in sources:
                if mask is None:
                    continue
                pose = masks_dir / f"{stem}.{variant}.layers" / "pose.txt"
                if not pose.is_file():
                    continue
                g = _garment_json(cli, image, mask, pose, Path(tmp) / f"{stem}.{variant}.regions.pgm")
                if g is None or not g.get("garments"):
                    continue
                info["garment_palettes"] = info.get("garment_palettes", 0) + 1
                labs = np.asarray([s["lab"] for s in g["garments"]], dtype=float)
                weights = [float(s["weight"]) for s in g["garments"]]
                tokens = " ".join(f"{L!r},{a!r},{b!r}:{w!r}" for (L, a, b), w in zip(labs.tolist(), weights))
                out.append({"index": f"{stem}.{variant}.garments", "family": f"people-garments:{variant}",
                            "hex": [s["hex"] for s in g["garments"]], "lab": labs, "weights": weights, "tokens": tokens})
            for variant, mask in sources:
                r = _palette_json(cli, image, mask)
                if r is None or not r.get("swatches"):
                    continue
                info["masks_used"] += int(mask is not None)
                labs = np.asarray([s["lab"] for s in r["swatches"]], dtype=float)
                weights = [float(s["weight"]) for s in r["swatches"]]
                tokens = " ".join(f"{L!r},{a!r},{b!r}:{w!r}" for (L, a, b), w in zip(labs.tolist(), weights))
                out.append({"index": f"{stem}.{variant}", "family": f"people:{variant}",
                            "hex": [s["hex"] for s in r["swatches"]], "lab": labs, "weights": weights, "tokens": tokens})
    info["status"] = "ok"
    info["palettes"] = len(out)
    return out, info


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------


def _flags(match_opts: dict[str, Any]) -> list[str]:
    args: list[str] = []
    for key, value in match_opts.items():
        flag = {"kL": "--kL", "kC": "--kC", "kH": "--kH"}.get(key, "--" + key.replace("_", "-"))
        args += [flag, str(int(value)) if isinstance(value, int) else repr(float(value))]
    return args


def run_match_palette(cli: Path, palettes: list[dict[str, Any]], match_opts: dict[str, Any], top: int = 3,
                      timeout: float = 600.0) -> list[dict[str, Any]]:
    """Una invocación de ``ce match-palette --json`` para todas las paletas (una línea cada una)."""
    text = "".join(p["tokens"] + "\n" for p in palettes)
    cmd = [str(cli), "match-palette", "--top", str(int(top)), *_flags(match_opts), "--json"]
    try:
        proc = subprocess.run(cmd, input=text, capture_output=True, text=True, check=False, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise HueShiftError(f"ce match-palette: {exc}") from exc
    rows = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
    if proc.returncode not in (0, 1) or len(rows) != len(palettes):
        raise HueShiftError(f"ce match-palette -> exit {proc.returncode}, {len(rows)} líneas para {len(palettes)} paletas: "
                            f"{proc.stderr.strip()[:300]}")
    bad = [r for r in rows if "error" in r]
    if bad:
        raise HueShiftError(f"ce match-palette: {len(bad)} paletas con error, p. ej. línea {bad[0]['line']}: {bad[0]['error']}")
    return rows


def has_match_palette(cli: Path | None) -> bool:
    if cli is None or not Path(cli).is_file():
        return False
    try:
        rows = run_match_palette(Path(cli), [{"tokens": "#808080:1"}], {}, top=1, timeout=30)
    except (HueShiftError, json.JSONDecodeError):
        return False
    return len(rows) == 1 and isinstance(rows[0].get("hits"), list)


# --------------------------------------------------------------------------------------
# Métrica
# --------------------------------------------------------------------------------------


def _nearest_color(dict_labs: np.ndarray, colors: list[int], lab: np.ndarray) -> tuple[int, np.ndarray]:
    cand = dict_labs[np.asarray(colors, dtype=np.int64)]
    d = np.asarray(ref.de2000(np.repeat(lab[None, :], len(cand), axis=0), cand), dtype=float)
    k = int(np.argmin(d))  # empates: primer color de la combinación
    return int(colors[k]), cand[k]


def palette_shift(p: dict[str, Any], hit: dict[str, Any], dict_labs: np.ndarray) -> dict[str, Any] | None:
    """Δhab entre el swatch cromático dominante y el color más cercano de la top-1 (None sin swatch cromático)."""
    labs = np.asarray(p["lab"], dtype=float)
    weights = np.asarray(p["weights"], dtype=float)
    chromatic = [i for i in np.argsort(-weights, kind="stable") if float(chroma(labs[i])) >= CHROMA_MIN]
    if not chromatic:
        return None
    s = labs[int(chromatic[0])]
    idx, near = _nearest_color(dict_labs, hit["colors"], s)
    dh = hue_diff_deg(float(hue_deg(s)), float(hue_deg(near)))
    shifted = bool(float(chroma(near)) >= CHROMA_MIN and dh > HUE_SHIFT_DEG)
    return {"swatch": int(chromatic[0]), "combo": int(hit["id"]), "color": idx, "dh": round(dh, 2),
            "near_chroma": round(float(chroma(near)), 2), "shifted": shifted}


def evaluate(cli: Path, n: int = N_PALETTES, seed: int = SEED, include_people: bool = True, log=print) -> dict[str, Any]:
    t0 = time.perf_counter()
    if not has_match_palette(cli):
        raise HueShiftError(f"{cli} no tiene el subcomando 'match-palette'")
    d = wg.load_dictionary()
    dict_labs = np.asarray(d["labs"], dtype=float)
    rng = np.random.default_rng(int(seed))

    kept: list[dict[str, Any]] = []
    v0_rows: list[dict[str, Any]] = []
    generated = 0
    candidates = 0  # candidatas examinadas (las sobrantes del último bloque no cuentan)
    rejected = 0
    while len(kept) < n:
        chunk = synthetic_candidates(rng, generated, max(64, int((n - len(kept)) * 1.1) + 16))
        generated += len(chunk)
        rows = run_match_palette(cli, chunk, CONFIGS[REFERENCE])
        for p, r in zip(chunk, rows):
            if len(kept) >= n:
                break
            candidates += 1
            if float(r["hits"][0]["score"]) < OUT_OF_DICT_MIN_SCORE:
                rejected += 1
                continue
            kept.append(p)
            v0_rows.append(r)
        if generated > 20 * n:
            raise HueShiftError(f"solo {len(kept)} paletas fuera del diccionario tras {candidates} candidatas")
    people_info: dict[str, Any] = {"status": "desactivado"}
    if include_people:
        people, people_info = people_palettes(cli)
        if people:
            p_rows = run_match_palette(cli, people, CONFIGS[REFERENCE])
            for p, r in zip(people, p_rows):
                if float(r["hits"][0]["score"]) < OUT_OF_DICT_MIN_SCORE:
                    rejected += 1
                    continue
                kept.append(p)
                v0_rows.append(r)
    log(f"  giro de tono: {len(kept)} paletas ({n} sintéticas de {candidates} candidatas, "
        f"{len(kept) - n} de harness/people, {rejected} descartadas por estar en el diccionario)")

    ref_shift = [palette_shift(p, r["hits"][0], dict_labs) for p, r in zip(kept, v0_rows)]
    n_eval = sum(1 for x in ref_shift if x is not None)
    families = list(FAMILIES) + sorted({p["family"] for p in kept if p["family"] not in FAMILIES})
    detail: dict[str, Any] = {
        "params": {"seed": seed, "n_synthetic": n, "hue_shift_deg": HUE_SHIFT_DEG, "chroma_min": CHROMA_MIN,
                   "out_of_dict_min_score": OUT_OF_DICT_MIN_SCORE, "min_weight": MIN_WEIGHT, "configs": CONFIGS,
                   "reference": REFERENCE},
        "cli": str(cli), "n_palettes": len(kept), "n_candidates": candidates, "n_rejected_in_dictionary": rejected,
        "n_evaluated": n_eval, "n_without_chromatic_swatch": len(kept) - n_eval, "people": people_info,
        "reference": {"shift_rate_vs_itself": 0.0,
                      "raw_shift_rate": sum(1 for x in ref_shift if x and x["shifted"]) / n_eval if n_eval else 0.0},
        "configs": {},
    }
    for name in REPORTED:
        rows = run_match_palette(cli, kept, CONFIGS[name])
        by_family: dict[str, dict[str, Any]] = {f: {"n": 0, "shifted": 0, "top1_changed": 0} for f in families}
        examples: list[dict[str, Any]] = []
        shifted = changed = 0
        for p, r, r0, x0 in zip(kept, rows, v0_rows, ref_shift):
            if x0 is None:
                continue
            fam = by_family[p["family"]]
            fam["n"] += 1
            top_changed = int(r["hits"][0]["id"]) != int(r0["hits"][0]["id"])
            changed += int(top_changed)
            fam["top1_changed"] += int(top_changed)
            x = palette_shift(p, r["hits"][0], dict_labs)
            if x is not None and x["shifted"] and not x0["shifted"]:
                shifted += 1
                fam["shifted"] += 1
                if len(examples) < 12:
                    examples.append({"palette": p["index"], "family": p["family"], "hex": p["hex"],
                                     "weights": [round(w, 3) for w in p["weights"]],
                                     "v0_top1": int(r0["hits"][0]["id"]), "v0_dh": x0["dh"],
                                     "top1": x["combo"], "score": r["hits"][0]["score"], "dh": x["dh"],
                                     "nearest_color": x["color"]})
        for fam in by_family.values():
            fam["rate"] = fam["shifted"] / fam["n"] if fam["n"] else 0.0
        detail["configs"][name] = {"opts": CONFIGS[name], "hue_shift_count": shifted,
                                   "hue_shift_rate": shifted / n_eval if n_eval else 0.0,
                                   "top1_changed_vs_v0": changed / n_eval if n_eval else 0.0,
                                   "by_family": {k: v for k, v in by_family.items() if v["n"]}, "examples": examples}
    detail["seconds"] = round(time.perf_counter() - t0, 1)
    return detail


def render_table(detail: dict[str, Any]) -> str:
    fams = list(detail["configs"][REPORTED[0]]["by_family"])
    lines = ["| Configuración | giro de tono | top-1 distinto de v0 | " + " | ".join(fams) + " |",
             "|---|---:|---:|" + "---:|" * len(fams)]
    for name in REPORTED:
        c = detail["configs"][name]
        cells = [f"{100 * c['by_family'][f]['rate']:.2f} % ({c['by_family'][f]['shifted']}/{c['by_family'][f]['n']})" for f in fams]
        lines.append(f"| {name} | **{100 * c['hue_shift_rate']:.2f} %** ({c['hue_shift_count']}/{detail['n_evaluated']}) | "
                     f"{100 * c['top1_changed_vs_v0']:.1f} % | " + " | ".join(cells) + " |")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    from oracle.l2 import find_cli_optional

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cli", type=str, default=None)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--n", type=int, default=N_PALETTES)
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--no-people", action="store_true")
    ap.add_argument("--max-rate", type=float, default=0.01, help="gate de la configuración defaults (propuesto)")
    args = ap.parse_args(argv)
    cli = find_cli_optional(args.cli)
    if cli is None:
        print("hue_shift: no hay CLI ce (make build)")
        return 2
    detail = evaluate(cli, n=args.n, seed=args.seed, include_people=not args.no_people)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "hue_shift.json").write_text(json.dumps(detail, indent=1, ensure_ascii=False, default=float) + "\n", encoding="utf-8")
    print(render_table(detail))
    rate = detail["configs"]["defaults"]["hue_shift_rate"]
    print(f"\nhue_shift: defaults {100 * rate:.2f} % (gate <= {100 * args.max_rate:.2f} %): {'OK' if rate <= args.max_rate else 'FAIL'}; "
          f"{detail['seconds']} s; detalle en {args.out / 'hue_shift.json'}")
    return 0 if rate <= args.max_rate else 1


if __name__ == "__main__":
    sys.exit(main())
