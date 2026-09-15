"""Golden files del harness (``harness/golden/``, ruta protegida): paletas y matches de referencia.

    make golden-update GOLDEN_REASON="..."   # python -m oracle.golden update --reason "..."
    make golden-check                        # python -m oracle.golden check

Fixtures: 50 PPM deterministas de ``synth.wada_gen`` (``fixture_specs``: 50 combinaciones
distintas elegidas con la semilla 20260915, variante 0..9 al azar, 128x128 para que el
repo no engorde) en ``harness/golden/fixtures/``. ``palettes_20.json`` guarda ``ce palette``
(opciones por defecto) de las 20 primeras; ``match_50.json`` guarda ``ce match --top 3`` de
las 50 (swatches, hits con id y score, ambiguous, hash).

``check`` compara la salida actual con los goldens: sha256 de cada fixture, mismo número de
swatches y hits, ``lab``/``weight``/``score`` a ``tolerance`` (1e-9 absoluto, la misma
tolerancia de paridad nativo/WASM), mismo ``rgb``, mismo top-3 (ids en orden) y mismo
``ambiguous``. Un golden distinto es una **regresión hasta que el usuario decida lo
contrario**: el check solo falla; ``update`` regenera y anota el motivo (obligatorio) en
``harness/CHANGELOG.md``. Tras un ``update`` el usuario revisa y promueve con
``COLORSAPP_ALLOW_PROTECTED=1 make protected-hash``.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import numpy as np

from oracle import l2, l3
from oracle.l2 import find_cli_optional
from synth import wada_gen as wg

REPO_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_DIR = REPO_ROOT / "harness" / "golden"
CHANGELOG_PATH = REPO_ROOT / "harness" / "CHANGELOG.md"
PALETTES_NAME = "palettes_20.json"
MATCHES_NAME = "match_50.json"
FIXTURES_NAME = "fixtures"
FIXTURE_SIZE = 128
N_PALETTES = 20
N_MATCHES = 50
FIXTURE_SEED = 20260915
TOLERANCE = 1e-9
TOP_K = 3


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fixture_specs(n: int = N_MATCHES, seed: int = FIXTURE_SEED) -> list[tuple[int, int]]:
    """``n`` pares (combo_id, v) deterministas: combinaciones distintas, variante dev al azar."""
    ids = wg.combo_ids()
    rng = np.random.default_rng(int(seed))
    combos = sorted(int(c) for c in rng.choice(ids, size=min(int(n), len(ids)), replace=False))
    vs = rng.integers(0, len(wg.DEV_VARIANTS), size=len(combos))
    return [(c, int(v)) for c, v in zip(combos, vs)]


def fixture_name(i: int, combo_id: int, v: int) -> str:
    return f"f{i:02d}_c{combo_id:03d}_v{v:02d}.ppm"


def write_fixtures(fixtures_dir: Path, specs: list[tuple[int, int]] | None = None, size: int = FIXTURE_SIZE) -> list[dict[str, Any]]:
    """Regenera los PPM de las fixtures (borra los anteriores) y devuelve su lista con sha256."""
    from synth import compose as sc

    specs = specs or fixture_specs()
    if fixtures_dir.is_dir():
        for old in fixtures_dir.glob("*.ppm"):
            old.unlink()
    fixtures_dir.mkdir(parents=True, exist_ok=True)
    out: list[dict[str, Any]] = []
    for i, (combo_id, v) in enumerate(specs, start=1):
        img, meta = wg.variant(combo_id, v, seed_base=0, size=size)
        name = fixture_name(i, combo_id, v)
        path = sc.write_ppm(img, fixtures_dir / name)
        out.append({"file": name, "combo_id": combo_id, "v": v, "variant": meta["variant"], "sha256": sha256_file(path)})
    return out


def _swatches(r: dict[str, Any]) -> list[dict[str, Any]]:
    return [{"lab": s["lab"], "weight": s["weight"], "rgb": s["rgb"], "hex": s["hex"]} for s in r["swatches"]]


def _header(kind: str, cli: Path, reason: str, n: int) -> dict[str, Any]:
    ce_version = subprocess.run([str(cli), "version"], capture_output=True, text=True, check=False).stdout.strip()
    return {
        "schema": 1,
        "kind": kind,
        "generated_at": dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds"),
        "reason": reason,
        "ce_version": ce_version,
        "dict_version": wg.dict_version(),
        "generator_hash": wg.generator_hash(),
        "fixture_size": FIXTURE_SIZE,
        "fixture_seed": FIXTURE_SEED,
        "tolerance": TOLERANCE,
        "top_k_required": TOP_K,
        "n": n,
    }


def update(cli: Path, reason: str, golden_dir: Path = GOLDEN_DIR, changelog: Path | None = CHANGELOG_PATH,
           log=print) -> dict[str, Any]:
    """Regenera fixtures, ``palettes_20.json`` y ``match_50.json``; anota ``reason`` en el CHANGELOG."""
    reason = (reason or "").strip()
    if not reason:
        raise ValueError("golden-update exige un motivo (GOLDEN_REASON=\"...\"); se anota en harness/CHANGELOG.md")
    if not l2.has_palette(cli):
        raise l2.PaletteError(l2.not_implemented_reason(cli))
    if not l3.has_match(cli):
        raise l3.MatchError(l3.not_implemented_reason(cli))
    fixtures_dir = golden_dir / FIXTURES_NAME
    fixtures = write_fixtures(fixtures_dir)
    palettes: list[dict[str, Any]] = []
    for f in fixtures[:N_PALETTES]:
        r = l2.run_palette(cli, fixtures_dir / f["file"])
        palettes.append({**f, "opts": r["opts"], "reduced": [r["reduced_width"], r["reduced_height"]],
                         "swatches": _swatches(r), "hash": r["hash"]})
    matches: list[dict[str, Any]] = []
    for f in fixtures:
        r = l3.run_match(cli, fixtures_dir / f["file"], top=TOP_K)
        matches.append({**f, "opts": r["opts"], "swatches": _swatches(r), "hits": r["hits"], "ambiguous": r["ambiguous"], "hash": r["hash"]})
    p_doc = {**_header("palettes", cli, reason, len(palettes)), "entries": palettes}
    m_doc = {**_header("matches", cli, reason, len(matches)), "entries": matches}
    (golden_dir / PALETTES_NAME).write_text(json.dumps(p_doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    (golden_dir / MATCHES_NAME).write_text(json.dumps(m_doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    top1_ok = sum(1 for m in matches if m["hits"] and m["hits"][0]["id"] == m["combo_id"])
    top3_ok = sum(1 for m in matches if m["combo_id"] in [h["id"] for h in m["hits"][:3]])
    summary = {
        "fixtures": len(fixtures), "palettes": len(palettes), "matches": len(matches),
        "ce_version": p_doc["ce_version"], "dict_version": p_doc["dict_version"], "generator_hash": p_doc["generator_hash"],
        "match_top1": top1_ok, "match_top3": top3_ok,
        "palettes_sha256": sha256_file(golden_dir / PALETTES_NAME), "matches_sha256": sha256_file(golden_dir / MATCHES_NAME),
    }
    if changelog is not None:
        entry = (
            f"\n## {dt.date.today().isoformat()} — golden-update: {reason}\n\n"
            f"- `harness/golden/{PALETTES_NAME}` ({len(palettes)} paletas, sha256 {summary['palettes_sha256'][:12]}…), "
            f"`{MATCHES_NAME}` ({len(matches)} matches, sha256 {summary['matches_sha256'][:12]}…) y `fixtures/` "
            f"({len(fixtures)} PPM {FIXTURE_SIZE}x{FIXTURE_SIZE} de `wada_gen`, semilla {FIXTURE_SEED}) regenerados con "
            f"`ce` {summary['ce_version']}, `dict_version` {summary['dict_version']}, `generator_hash` {summary['generator_hash']}.\n"
            f"- Recall sobre las 50 fixtures en el momento del update: top-1 {top1_ok}/50, top-3 {top3_ok}/50 "
            f"(un golden nuevo sin subida de recall es una regresión: lo decide el usuario).\n"
            f"- Ruta protegida: revisar y promover con `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash`.\n"
        )
        changelog.parent.mkdir(parents=True, exist_ok=True)
        with changelog.open("a", encoding="utf-8") as f:
            f.write(entry)
    log(f"golden-update: {len(fixtures)} fixtures, {len(palettes)} paletas, {len(matches)} matches en {golden_dir} "
        f"(top-1 {top1_ok}/50, top-3 {top3_ok}/50); motivo anotado en {changelog}")
    return summary


# --------------------------------------------------------------------------------------
# check
# --------------------------------------------------------------------------------------


def compare_swatches(expected: list[dict[str, Any]], actual: list[dict[str, Any]], tol: float) -> list[str]:
    problems: list[str] = []
    if len(expected) != len(actual):
        return [f"n swatches {len(actual)} != {len(expected)}"]
    for i, (e, a) in enumerate(zip(expected, actual)):
        d_lab = max(abs(float(x) - float(y)) for x, y in zip(e["lab"], a["lab"]))
        d_w = abs(float(e["weight"]) - float(a["weight"]))
        if d_lab > tol:
            problems.append(f"swatch {i}: |Δlab| = {d_lab:.3e} > {tol:g}")
        if d_w > tol:
            problems.append(f"swatch {i}: |Δweight| = {d_w:.3e} > {tol:g}")
        if list(e["rgb"]) != list(a["rgb"]):
            problems.append(f"swatch {i}: rgb {a['rgb']} != {e['rgb']}")
    return problems


def compare_hits(expected: list[dict[str, Any]], actual: list[dict[str, Any]], tol: float, top: int = TOP_K) -> list[str]:
    problems: list[str] = []
    if len(expected) != len(actual):
        problems.append(f"n hits {len(actual)} != {len(expected)}")
    e_ids = [int(h["id"]) for h in expected[:top]]
    a_ids = [int(h["id"]) for h in actual[:top]]
    if e_ids != a_ids:
        problems.append(f"top-{top} {a_ids} != {e_ids}")
    for i, (e, a) in enumerate(zip(expected, actual)):
        d = abs(float(e["score"]) - float(a["score"]))
        if d > tol:
            problems.append(f"hit {i} (id {e['id']}): |Δscore| = {d:.3e} > {tol:g}")
    return problems


def _load(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def check(cli: Path | None, golden_dir: Path = GOLDEN_DIR, log=None) -> tuple[bool, str, dict[str, Any]]:
    """(ok, resumen, detalle). ``ok`` solo si todos los goldens existen y coinciden."""
    detail: dict[str, Any] = {"golden_dir": str(golden_dir), "mismatches": 0, "problems": []}
    fixtures_dir = golden_dir / FIXTURES_NAME
    p_doc = _load(golden_dir / PALETTES_NAME)
    m_doc = _load(golden_dir / MATCHES_NAME)
    if p_doc is None or m_doc is None:
        missing = [n for n, d in ((PALETTES_NAME, p_doc), (MATCHES_NAME, m_doc)) if d is None]
        detail["problems"] = [f"falta harness/golden/{n}" for n in missing]
        detail["mismatches"] = len(missing)
        return False, f"sin goldens ({', '.join(missing)}): make golden-update GOLDEN_REASON=\"...\"", detail
    if cli is None or not l2.has_palette(cli):
        detail["problems"] = [l2.not_implemented_reason(cli)]
        detail["mismatches"] = 1
        return False, f"no se puede comprobar: {l2.not_implemented_reason(cli)}", detail
    engine_dict = subprocess.run([str(cli), "dict", "--version"], capture_output=True, text=True, check=False).stdout.strip()
    problems: list[str] = []
    for doc, name in ((p_doc, PALETTES_NAME), (m_doc, MATCHES_NAME)):
        if doc.get("dict_version") != engine_dict:
            problems.append(f"{name}: dict_version {doc.get('dict_version')} != motor {engine_dict}")
    tol = float(p_doc.get("tolerance", TOLERANCE))

    # Paletas
    p_bad = 0
    for e in p_doc["entries"]:
        path = fixtures_dir / e["file"]
        errs: list[str] = []
        if not path.is_file():
            errs.append("fixture ausente")
        elif sha256_file(path) != e["sha256"]:
            errs.append("sha256 de la fixture distinto")
        else:
            try:
                r = l2.run_palette(cli, path, options=None)
                errs += compare_swatches(e["swatches"], r["swatches"], tol)
                if r["hash"] != e["hash"] and not errs:
                    errs.append(f"hash {r['hash']} != {e['hash']} (bits distintos por debajo de {tol:g}: informativo)")
            except l2.PaletteError as exc:
                errs.append(str(exc))
        if errs and not all("informativo" in x for x in errs):
            p_bad += 1
            problems += [f"paleta {e['file']}: {x}" for x in errs]
    # Matches
    m_bad = 0
    if not l3.has_match(cli):
        problems.append(f"{MATCHES_NAME}: {l3.not_implemented_reason(cli)}")
        m_bad = len(m_doc["entries"])
    else:
        top = int(m_doc.get("top_k_required", TOP_K))
        for e in m_doc["entries"]:
            path = fixtures_dir / e["file"]
            errs = []
            if not path.is_file():
                errs.append("fixture ausente")
            elif sha256_file(path) != e["sha256"]:
                errs.append("sha256 de la fixture distinto")
            else:
                try:
                    r = l3.run_match(cli, path, top=top)
                    errs += compare_swatches(e["swatches"], r["swatches"], tol)
                    errs += compare_hits(e["hits"], r["hits"], tol, top)
                    if r["ambiguous"] != e["ambiguous"]:
                        errs.append(f"ambiguous {r['ambiguous']} != {e['ambiguous']}")
                except l3.MatchError as exc:
                    errs.append(str(exc))
            if errs:
                m_bad += 1
                problems += [f"match {e['file']}: {x}" for x in errs]
    detail.update({
        "palettes": {"n": len(p_doc["entries"]), "mismatches": p_bad, "generated_at": p_doc.get("generated_at"), "ce_version": p_doc.get("ce_version")},
        "matches": {"n": len(m_doc["entries"]), "mismatches": m_bad, "generated_at": m_doc.get("generated_at"), "ce_version": m_doc.get("ce_version")},
        "mismatches": p_bad + m_bad + (1 if any(x.startswith((PALETTES_NAME, MATCHES_NAME)) for x in problems) else 0),
        "problems": problems,
        "tolerance": tol,
    })
    ok = not problems
    summary = (f"{len(p_doc['entries']) - p_bad}/{len(p_doc['entries'])} paletas y {len(m_doc['entries']) - m_bad}/{len(m_doc['entries'])} "
               f"matches iguales a {tol:g} (goldens de {m_doc.get('generated_at', '?')[:10]}, ce {m_doc.get('ce_version')}, "
               f"motivo: {m_doc.get('reason', '?')[:60]})")
    if problems:
        summary += "\n" + "\n".join(problems[:12])
    if log is not None:
        log(summary)
    return ok, summary, detail


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=("update", "check"))
    ap.add_argument("--cli", type=str, default=None, help="ruta a 'ce' (por defecto build/tools/ce o $COLORSAPP_CE_CLI)")
    ap.add_argument("--reason", type=str, default="", help="motivo del update (obligatorio; va a harness/CHANGELOG.md)")
    ap.add_argument("--golden-dir", type=Path, default=GOLDEN_DIR)
    args = ap.parse_args(argv)
    cli = find_cli_optional(args.cli)
    if args.action == "update":
        if cli is None:
            print(f"golden-update: {l2.not_implemented_reason(cli)}", file=sys.stderr)
            return 2
        try:
            update(cli, args.reason, golden_dir=args.golden_dir)
        except (ValueError, l2.PaletteError, l3.MatchError) as exc:
            print(f"golden-update: {exc}", file=sys.stderr)
            return 2
        return 0
    ok, summary, _detail = check(cli, golden_dir=args.golden_dir)
    print(f"golden-check: {'OK' if ok else 'FALLO'} — {summary}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
