"""Runner mínimo de la capa 4 (fotos reales del set dorado), fase 3 del plan.

    uv run --project oracle python -m l4.run [--cli PATH] [--out harness/out] [--golden-dir DIR]

Lee ``$COLORSAPP_GOLDEN_DIR/manifest.json`` (lista de ``{file, sha256, tags[], labels:
{juez: combo_id|null}}``; también se admite ``{"photos": [...]}``), verifica cada foto
(sha256; solo PNG o JPEG sRGB con lado <= 256 px; HEIC rechazado por extensión y por
cabecera ``ftyp``), calcula el consenso por mayoría de los jueces (``null`` = "ninguna";
sin mayoría estricta la foto queda sin consenso y no puntúa), convierte a PPM con
``tools.to_ppm`` (el único decodificador), ejecuta ``ce batch`` (opciones por defecto) y
mide recall@1/@3 por tag y agregado, cuota de la clase más frecuente y Fleiss κ (si todas
las fotos tienen el mismo número de jueces, >= 2). Umbrales: ``harness/thresholds.json``
sección L4 (``golden_min_photos``, ``by_tag``, ``aggregate``).

Sin ``COLORSAPP_GOLDEN_DIR`` la capa es ``skipped`` (motivo en el scorecard, exit 0); es
el único motivo admitido de ``skipped`` para L4 (sección 6 del plan). Las fotos nunca
entran en el repo: solo se copian PPM temporales a ``<out>/l4/``.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Any

from oracle import l3
from oracle import metrics as mt
from oracle.l2 import Check, find_cli_optional, load_thresholds

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "harness" / "out"
GOLDEN_DIR_ENV = "COLORSAPP_GOLDEN_DIR"
MANIFEST_NAME = "manifest.json"
MAX_SIDE = 256
ALLOWED_FORMATS = ("PNG", "JPEG")
DEFAULTS: dict[str, Any] = {"golden_min_photos": 50, "judges": 3, "tags": [], "by_tag": {},
                            "aggregate": {"recall_at_3_min": 0.70, "max_class_share_max": 0.30}}


class ManifestError(ValueError):
    """El manifest no tiene el formato esperado."""


def golden_dir_from_env() -> Path | None:
    raw = os.environ.get(GOLDEN_DIR_ENV)
    if raw is None or not raw.strip():
        return None
    return Path(raw).expanduser()


# --------------------------------------------------------------------------------------
# Manifest y verificación de fotos
# --------------------------------------------------------------------------------------


def load_manifest(golden_dir: Path) -> list[dict[str, Any]]:
    path = golden_dir / MANIFEST_NAME
    if not path.is_file():
        raise ManifestError(f"falta {path}")
    doc = json.loads(path.read_text(encoding="utf-8"))
    entries = doc.get("photos", doc.get("entries")) if isinstance(doc, dict) else doc
    if not isinstance(entries, list):
        raise ManifestError(f"{path}: se esperaba una lista (o un objeto con 'photos')")
    problems: list[str] = []
    for i, e in enumerate(entries):
        if not isinstance(e, dict):
            problems.append(f"entrada {i}: no es un objeto")
            continue
        if not isinstance(e.get("file"), str) or not e["file"]:
            problems.append(f"entrada {i}: 'file' inválido")
        if not (isinstance(e.get("sha256"), str) and len(e["sha256"]) == 64):
            problems.append(f"entrada {i}: 'sha256' debe ser 64 hex")
        if not (isinstance(e.get("tags"), list) and all(isinstance(t, str) for t in e["tags"])):
            problems.append(f"entrada {i}: 'tags' debe ser una lista de cadenas")
        labels = e.get("labels")
        if not isinstance(labels, dict) or not labels:
            problems.append(f"entrada {i}: 'labels' debe ser {{juez: combo_id|null}} no vacío")
        elif any(not (v is None or (isinstance(v, int) and not isinstance(v, bool) and 1 <= v <= 348)) for v in labels.values()):
            problems.append(f"entrada {i}: etiquetas fuera de 1..348 o no enteras")
    if problems:
        raise ManifestError("; ".join(problems[:8]))
    return entries


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def verify_photo(golden_dir: Path, entry: dict[str, Any]) -> tuple[list[str], dict[str, Any]]:
    """Problemas (vacío = aceptada) e información (formato, tamaño, perfil) de una foto."""
    from PIL import Image, ImageCms, UnidentifiedImageError

    from tools.to_ppm import HEIF_SUFFIXES, looks_like_heif

    path = golden_dir / entry["file"]
    info: dict[str, Any] = {"file": entry["file"]}
    if not path.is_file():
        return [f"{entry['file']}: no existe"], info
    if path.suffix.lower() in HEIF_SUFFIXES or looks_like_heif(path):
        return [f"{entry['file']}: HEIC/HEIF rechazado (exporta PNG o JPEG sRGB de 256 px)"], info
    digest = sha256_file(path)
    problems: list[str] = []
    if digest != entry["sha256"].lower():
        problems.append(f"{entry['file']}: sha256 {digest[:12]}… != manifest {entry['sha256'][:12]}…")
    try:
        with Image.open(path) as img:
            fmt = img.format
            info.update({"format": fmt, "width": img.width, "height": img.height, "mode": img.mode})
            if fmt not in ALLOWED_FORMATS:
                problems.append(f"{entry['file']}: formato {fmt} no admitido (solo PNG o JPEG)")
            if max(img.width, img.height) > MAX_SIDE:
                problems.append(f"{entry['file']}: {img.width}x{img.height} supera {MAX_SIDE} px de lado")
            icc = img.info.get("icc_profile")
            if icc:
                try:
                    desc = ImageCms.getProfileDescription(ImageCms.ImageCmsProfile(io.BytesIO(icc))) or ""
                except ImageCms.PyCMSError:
                    desc = ""
                info["icc"] = desc.strip()
                if "srgb" not in desc.lower():
                    problems.append(f"{entry['file']}: perfil ICC {desc.strip()!r} no es sRGB")
            else:
                info["icc"] = None
    except (UnidentifiedImageError, OSError) as exc:
        problems.append(f"{entry['file']}: Pillow no puede abrirlo ({exc})")
    return problems, info


# --------------------------------------------------------------------------------------
# Consenso y acuerdo
# --------------------------------------------------------------------------------------


def consensus(labels: dict[str, int | None]) -> int | None:
    """Mayoría estricta entre los jueces (``None`` cuenta como voto "ninguna"); empate => None."""
    votes = Counter(labels.values())
    if not votes:
        return None
    ranked = votes.most_common()
    top, n_top = ranked[0]
    if len(ranked) > 1 and ranked[1][1] == n_top:
        return None
    if n_top * 2 <= len(labels):
        return None
    return top if isinstance(top, int) else None


def fleiss_kappa(rows: list[dict[str, int | None]]) -> float | None:
    """Fleiss κ sobre las etiquetas (categorías = combinaciones vistas + "ninguna").

    None si hay menos de 2 fotos, menos de 2 jueces o un número desigual de jueces por foto.
    """
    if len(rows) < 2:
        return None
    n_raters = {len(r) for r in rows}
    if len(n_raters) != 1:
        return None
    n = n_raters.pop()
    if n < 2:
        return None
    cats = sorted({("none" if v is None else v) for r in rows for v in r.values()}, key=repr)
    idx = {c: i for i, c in enumerate(cats)}
    table = [[0] * len(cats) for _ in rows]
    for i, r in enumerate(rows):
        for v in r.values():
            table[i][idx["none" if v is None else v]] += 1
    n_subj = len(rows)
    p_j = [sum(row[j] for row in table) / (n_subj * n) for j in range(len(cats))]
    p_i = [(sum(c * c for c in row) - n) / (n * (n - 1)) for row in table]
    p_bar = sum(p_i) / n_subj
    p_e = sum(p * p for p in p_j)
    if abs(1.0 - p_e) < 1e-12:
        return 1.0
    return (p_bar - p_e) / (1.0 - p_e)


# --------------------------------------------------------------------------------------
# Capa
# --------------------------------------------------------------------------------------


def resolve_thresholds(thresholds: dict[str, Any] | None) -> tuple[dict[str, Any], list[str]]:
    section = (thresholds or {}).get("L4", {}) if thresholds else {}
    values: dict[str, Any] = {}
    defaulted: list[str] = []
    for key, default in DEFAULTS.items():
        if isinstance(section, dict) and key in section:
            values[key] = section[key]
        else:
            values[key] = default
            defaulted.append(key)
    return values, defaulted


def _pct(x: float) -> str:
    return f"{100.0 * float(x):.1f} %"


def run_layer4(cli: Path | None, thresholds: dict[str, Any] | None, out_dir: Path | None,
               golden_dir: Path | None = None, log=print) -> tuple[str, list[Check], dict[str, Any]]:
    """(estado, checks, detalle). Estado ``skipped`` sin ``$COLORSAPP_GOLDEN_DIR``; si no, pass | fail."""
    golden_dir = golden_dir or golden_dir_from_env()
    if golden_dir is None:
        reason = f"sin ${GOLDEN_DIR_ENV}: el set dorado vive fuera del repo (fase 8); solo el usuario lo exporta"
        return "skipped", [Check("set dorado", "skipped", reason)], {"status": "skipped", "reason": reason}
    th, defaulted = resolve_thresholds(thresholds)
    started = time.perf_counter()
    checks: list[Check] = []
    detail: dict[str, Any] = {"golden_dir": str(golden_dir), "thresholds": th, "thresholds_defaulted": defaulted}

    def add(c: Check) -> None:
        checks.append(c)
        log(f"  [{c.status:>7}] {c.name}" + (f": {c.detail.splitlines()[0]}" if c.detail else ""))

    try:
        entries = load_manifest(golden_dir)
    except (ManifestError, json.JSONDecodeError) as exc:
        add(Check("manifest.json del set dorado", "fail", str(exc)))
        return "fail", checks, detail
    add(Check("manifest.json del set dorado", "pass", f"{len(entries)} fotos en {golden_dir}", value=len(entries)))

    # Verificación de ficheros
    accepted: list[dict[str, Any]] = []
    rejected: list[str] = []
    infos: list[dict[str, Any]] = []
    for e in entries:
        problems, info = verify_photo(golden_dir, e)
        infos.append(info)
        if problems:
            rejected += problems
        else:
            accepted.append(e)
    add(Check("fotos: sha256, PNG/JPEG sRGB, lado <= 256 px, sin HEIC", "pass" if not rejected else "fail",
              f"{len(accepted)}/{len(entries)} aceptadas" + ("\n" + "\n".join(rejected[:10]) if rejected else ""),
              value=len(rejected), threshold=0))
    add(Check(f"fotos aceptadas >= {th['golden_min_photos']} (golden_min_photos)",
              "pass" if len(accepted) >= int(th["golden_min_photos"]) else "fail",
              f"{len(accepted)} fotos (objetivo {th.get('golden_target_photos', 100)})", value=len(accepted), threshold=int(th["golden_min_photos"])))

    # Consenso y acuerdo
    with_consensus = [(e, consensus(e["labels"])) for e in accepted]
    scored = [(e, c) for e, c in with_consensus if c is not None]
    kappa = fleiss_kappa([e["labels"] for e in accepted])
    judges = sorted({j for e in accepted for j in e["labels"]})
    add(Check("consenso por mayoría de los jueces", "info",
              f"{len(scored)}/{len(accepted)} fotos con consenso; jueces: {', '.join(judges) or '—'}; "
              + (f"Fleiss κ = {kappa:.3f}" if kappa is not None else "Fleiss κ no calculable (menos de 2 jueces o número desigual por foto)"),
              value=kappa))
    detail.update({"n_entries": len(entries), "n_accepted": len(accepted), "n_scored": len(scored), "judges": judges,
                   "fleiss_kappa": kappa, "rejected": rejected, "photos": infos})
    if not scored:
        add(Check("recall contra el consenso", "fail", "ninguna foto con consenso"))
        return "fail", checks, detail
    if cli is None or not l3.has_match(cli):
        add(Check("ce batch", "fail", l3.not_implemented_reason(cli)))
        return "fail", checks, detail

    # Conversión a PPM y match
    from tools import to_ppm

    work = (out_dir / "l4" / "ppm") if out_dir is not None else Path(golden_dir) / ".l4_ppm"
    work.mkdir(parents=True, exist_ok=True)
    files: list[Path] = []
    for i, (e, _c) in enumerate(scored):
        dst = work / f"p{i:03d}.ppm"
        to_ppm.convert(golden_dir / e["file"], dst, max_side=MAX_SIDE)
        files.append(dst)
    results = l3.run_batch(cli, files)
    truth = [c for _e, c in scored]
    contract = [p for r in results for p in l3.validate_match_result(r)]
    add(Check("contrato JSON de ce batch", "pass" if not contract else "fail",
              f"{len(results)} resultados; problemas: {len(contract)}" + ("\n" + "\n".join(contract[:6]) if contract else ""),
              value=len(contract), threshold=0))
    agg = l3.metrics_for(truth, results)
    by_tag: dict[str, dict[str, Any]] = {}
    for tag in sorted({t for e, _c in scored for t in e["tags"]} | set(th.get("tags") or [])):
        idx = [i for i, (e, _c) in enumerate(scored) if tag in e["tags"]]
        by_tag[tag] = l3.metrics_for([truth[i] for i in idx], [results[i] for i in idx]) if idx else {"n": 0}
    detail.update({"aggregate": agg, "by_tag": by_tag, "per_photo": [
        {"file": e["file"], "consensus": c, "top": l3.ranked_ids(r), "ambiguous": r.get("ambiguous"), "error": r.get("error")}
        for (e, c), r in zip(scored, results)]})
    for tag, gates in (th.get("by_tag") or {}).items():
        m = by_tag.get(tag, {"n": 0})
        for key, minimum in gates.items():
            k = 1 if key.endswith("_1_min") else 3
            if not m.get("n"):
                add(Check(f"tag {tag}: recall@{k} >= {minimum}", "info", "sin fotos con este tag", threshold=minimum))
                continue
            value = float(m[f"recall_at_{k}"])
            add(Check(f"tag {tag}: recall@{k} >= {minimum}", "pass" if value >= float(minimum) else "fail",
                      f"{_pct(value)} sobre {m['n']} fotos (@1 {_pct(m['recall_at_1'])}, @3 {_pct(m['recall_at_3'])})", value=value, threshold=float(minimum)))
    a_th = th.get("aggregate") or {}
    if "recall_at_3_min" in a_th:
        add(Check(f"agregado: recall@3 >= {a_th['recall_at_3_min']}", "pass" if agg["recall_at_3"] >= float(a_th["recall_at_3_min"]) else "fail",
                  f"recall@1 {_pct(agg['recall_at_1'])}, recall@3 {_pct(agg['recall_at_3'])} sobre {agg['n']} fotos con consenso",
                  value=float(agg["recall_at_3"]), threshold=float(a_th["recall_at_3_min"])))
    if "max_class_share_max" in a_th:
        add(Check(f"agregado: cuota de la clase más frecuente <= {a_th['max_class_share_max']}",
                  "pass" if agg["max_class_share"] <= float(a_th["max_class_share_max"]) else "fail",
                  f"{_pct(agg['max_class_share'])} (combo {agg['max_class_id']}); entropía {agg['entropy_norm']:.3f}; ambiguous {_pct(agg['ambiguous_rate'])}",
                  value=float(agg["max_class_share"]), threshold=float(a_th["max_class_share_max"])))
    if defaulted:
        add(Check("umbrales L4 con valores por defecto (no promovidos)", "info", ", ".join(defaulted), value=len(defaulted)))
    detail["seconds"] = round(time.perf_counter() - started, 1)
    if out_dir is not None:
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "l4_detail.json").write_text(json.dumps(detail, indent=1, ensure_ascii=False, default=str) + "\n", encoding="utf-8")
    status = "fail" if any(c.status == "fail" for c in checks) else "pass"
    return status, checks, detail


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cli", type=str, default=None)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--golden-dir", type=Path, default=None, help=f"por defecto ${GOLDEN_DIR_ENV}")
    args = ap.parse_args(argv)
    status, checks, detail = run_layer4(find_cli_optional(args.cli), load_thresholds(), args.out, golden_dir=args.golden_dir)
    if status == "skipped":
        print(f"L4: skipped ({detail['reason']})")
        return 0
    print(f"L4: {status.upper()} ({sum(1 for c in checks if c.status == 'pass')}/{len(checks)} checks pass; {detail.get('seconds')} s)")
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
