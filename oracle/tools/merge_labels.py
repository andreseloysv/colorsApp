#!/usr/bin/env python3
"""Set dorado (fase 8): fusiona las etiquetas de los jueces en ``manifest.json`` y lo valida.

    uv run --project oracle python oracle/tools/merge_labels.py merge --golden-dir DIR --labels DIR2
    uv run --project oracle python oracle/tools/merge_labels.py check --golden-dir DIR

``merge`` lee los ``labels-<juez>.json`` que descarga ``harness/label/index.html``
(``{"schema": 1, "kind": "colorsapp-labels", "judge": "ana", "labels": [{"file", "sha256",
"combo_id": 1..348|null, "tags": [...], "note"}]}``; ``null`` = "ninguna") y escribe en
``DIR/manifest.json`` el formato que lee ``oracle/l4/run.py``: ``{"photos": [{"file", "sha256",
"tags", "labels": {juez: combo_id|null}, "masks"?: {variante: fichero.pgm}}]}`` más metadatos
(jueces, consenso, Fleiss κ). Reglas:

- una foto = cada PNG/JPEG del directorio dorado (HEIC rechazado); las fotos sin ninguna
  etiqueta no entran en el manifest (se reportan);
- el ``sha256`` del manifest es el del fichero actual; una etiqueta cuyo ``sha256`` no coincide
  se descarta (la foto cambió después de etiquetarla);
- ``tags`` = unión de los tags de los jueces (lista conocida: ``GOLDEN_TAGS`` + ``L4.tags``);
- consenso por mayoría estricta (``l4.run.consensus``): ``consensus`` = combo_id o ``null``, y
  ``consensus_kind`` distingue ``combo`` (puntúa en L4), ``none`` ("ninguna" por mayoría: los
  jueces no ven la combinación entre las candidatas; no puntúa recall, se reporta aparte) y
  ``tie`` (sin mayoría); κ de Fleiss (``l4.run.fleiss_kappa``) sobre las fotos etiquetadas por
  todos los jueces;
- ``masks`` (opcional, lo usa la capa 4 por variantes): máscaras PGM de la app junto a la foto,
  descubiertas por nombre ``<stem>.<variante>.pgm`` (``variante`` = ``[A-Za-z0-9_-]+``, p. ej.
  ``largest``, ``largest-clothing``, ``largest-clothing-skin``: lo que escribe "Exportar
  diagnóstico" y copia ``feedback_report.py --extract``); las que ya estaban en un
  ``manifest.json`` anterior se conservan.

Sale 0 si todas las fotos tienen etiqueta de todos los jueces y ningún sha256 falló; si no,
1 (el manifest se escribe igualmente, con lo que hay); 2 uso.

``check`` valida el manifest como exige la fila F8 del plan: >= ``golden_min_photos`` fotos
(50; objetivo ``golden_target_photos`` 100), todos los tags presentes al menos una vez
(``negro, denim, gris, interior, fondo-sucio, blanco, grupo``), sha256 correctos, ``judges`` (3)
etiquetas por foto, solo PNG/JPEG sRGB de lado <= 256 px, sin HEIC (``l4.run.verify_photo``) y,
si una foto trae ``masks``, que cada PGM existe y tiene las dimensiones de la foto; imprime
consenso, κ y los objetivos por tag de ``docs/SHOTLIST.md``. Exit 1 si algo falla.
Umbrales: ``harness/thresholds.json`` sección L4 (valores por defecto de ``l4.run`` si faltan).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

from l4 import run as l4
from oracle.l2 import load_thresholds

#: Tags del set dorado (PLAN §6 capa 4 + "grupo", sección 10 del contexto: fotos con varias personas).
GOLDEN_TAGS = ["negro", "denim", "gris", "interior", "fondo-sucio", "blanco", "grupo"]
#: Objetivos por tag de docs/SHOTLIST.md (informativos en golden-check; el gate es "al menos una").
SHOTLIST_TARGETS = {"negro": 15, "denim": 15, "gris": 10, "interior": 20, "fondo-sucio": 15, "blanco": 10, "grupo": 20}
PHOTO_SUFFIXES = {".png", ".jpg", ".jpeg"}
LABELS_KIND = "colorsapp-labels"
MASK_VARIANT_RE = re.compile(r"^[A-Za-z0-9_-]+$")
_PNM_TOKEN = re.compile(rb"\s*(?:#[^\n]*\n\s*)*(\S+)")


class LabelsError(ValueError):
    """Un fichero de etiquetas no tiene el formato esperado."""


def resolve_tags(th: dict[str, Any]) -> tuple[list[str], list[str]]:
    """(tags conocidos/exigidos, tags de ``GOLDEN_TAGS`` que faltan en ``L4.tags`` de thresholds.json).

    Se exige la unión: ``GOLDEN_TAGS`` en su orden y después cualquier tag extra de thresholds.json.
    ``thresholds.json`` es ruta protegida: si le falta un tag (hoy ``grupo``) no se toca, se avisa.
    """
    configured = [t for t in (th.get("tags") or []) if isinstance(t, str)]
    tags = list(GOLDEN_TAGS) + [t for t in configured if t not in GOLDEN_TAGS]
    missing = [t for t in GOLDEN_TAGS if configured and t not in configured]
    return tags, missing


# --------------------------------------------------------------------------------------
# Fotos del directorio, máscaras y ficheros de etiquetas
# --------------------------------------------------------------------------------------


def list_photos(golden_dir: Path) -> tuple[list[Path], list[str]]:
    """PNG/JPEG del directorio (sin recursión) y problemas (HEIC por extensión o cabecera)."""
    from tools.to_ppm import HEIF_SUFFIXES, looks_like_heif

    photos: list[Path] = []
    problems: list[str] = []
    for p in sorted(golden_dir.iterdir()):
        if not p.is_file() or p.name.startswith("."):
            continue
        if p.suffix.lower() in HEIF_SUFFIXES or looks_like_heif(p):
            problems.append(f"{p.name}: HEIC/HEIF rechazado (exporta PNG o JPEG sRGB de 256 px)")
        elif p.suffix.lower() in PHOTO_SUFFIXES:
            photos.append(p)
    return photos, problems


def discover_masks(golden_dir: Path, photo_names: list[str]) -> tuple[dict[str, dict[str, str]], list[str]]:
    """``{foto: {variante: fichero.pgm}}`` por nombre ``<stem>.<variante>.pgm`` y PGM huérfanos.

    Si varios stems encajan (``a.png`` y ``a.b.png`` frente a ``a.b.largest.pgm``) gana el más largo
    cuya variante cumple ``MASK_VARIANT_RE`` (sin puntos).
    """
    stems = sorted(((Path(n).stem, n) for n in photo_names), key=lambda sn: -len(sn[0]))
    found: dict[str, dict[str, str]] = {}
    orphans: list[str] = []
    for p in sorted(golden_dir.glob("*.pgm")):
        base = p.name[: -len(".pgm")]
        for stem, name in stems:
            if base.startswith(stem + ".") and MASK_VARIANT_RE.match(base[len(stem) + 1:]):
                found.setdefault(name, {})[base[len(stem) + 1:]] = p.name
                break
        else:
            orphans.append(p.name)
    return found, orphans


def read_pgm_header(path: Path) -> tuple[int, int, int]:
    """(ancho, alto, maxval) de un PGM P5/P2; ``ValueError`` si no lo es o si el cuerpo P5 está truncado."""
    data = path.read_bytes()
    if data[:2] not in (b"P5", b"P2"):
        raise ValueError("no es PGM (cabecera P5/P2)")
    pos = 2
    values: list[int] = []
    for _ in range(3):
        m = _PNM_TOKEN.match(data, pos)
        if not m or not m.group(1).isdigit():
            raise ValueError("cabecera PGM incompleta")
        values.append(int(m.group(1)))
        pos = m.end()
    w, h, maxval = values
    if w < 1 or h < 1 or not 1 <= maxval <= 65535:
        raise ValueError(f"dimensiones o maxval inválidos ({w}x{h}, maxval {maxval})")
    if data[:2] == b"P5":
        need = w * h * (1 if maxval < 256 else 2)
        if len(data) - (pos + 1) < need:
            raise ValueError(f"cuerpo truncado ({len(data) - pos - 1} bytes < {need})")
    return w, h, maxval


def validate_masks(golden_dir: Path, entry: dict[str, Any], size: tuple[int, int] | None) -> list[str]:
    """Problemas del campo opcional ``masks`` de una entrada (vacío = bien o sin máscaras)."""
    if "masks" not in entry:
        return []
    masks = entry["masks"]
    name = entry.get("file", "?")
    if not isinstance(masks, dict):
        return [f"{name}: 'masks' debe ser {{variante: fichero.pgm}}"]
    problems: list[str] = []
    for variant, rel in sorted(masks.items()):
        if not MASK_VARIANT_RE.match(str(variant)):
            problems.append(f"{name}: variante de máscara {variant!r} inválida ([A-Za-z0-9_-]+)")
            continue
        if not isinstance(rel, str) or not rel.lower().endswith(".pgm") or Path(rel).is_absolute() or ".." in Path(rel).parts:
            problems.append(f"{name}: máscara {variant}: {rel!r} debe ser un .pgm relativo al directorio dorado")
            continue
        path = golden_dir / rel
        if not path.is_file():
            problems.append(f"{name}: máscara {variant}: {rel} no existe")
            continue
        try:
            w, h, _maxval = read_pgm_header(path)
        except (OSError, ValueError) as exc:
            problems.append(f"{name}: máscara {variant}: {rel}: {exc}")
            continue
        if size is not None and (w, h) != tuple(size):
            problems.append(f"{name}: máscara {variant}: {rel} mide {w}x{h} y la foto {size[0]}x{size[1]}")
    return problems


def consensus_kind(labels: dict[str, int | None]) -> str:
    """``combo`` (mayoría estricta por una combinación), ``none`` (mayoría estricta por "ninguna") o
    ``tie`` (sin mayoría). Coherente con ``l4.run.consensus``, que devuelve None en los dos últimos."""
    if l4.consensus(labels) is not None:
        return "combo"
    votes = list(labels.values())
    return "none" if votes and votes.count(None) * 2 > len(votes) else "tie"


def judge_slug(name: str) -> str:
    """Mismo slug que usa index.html para el nombre del fichero (ASCII: [a-z0-9_-], guiones colapsados)."""
    slug = re.sub(r"[^a-z0-9_-]+", "-", name.strip().lower()).strip("-")
    return slug or "juez"


def read_labels_file(path: Path) -> tuple[str, dict[str, dict[str, Any]]]:
    """(juez, {file: entrada}) de un labels-<juez>.json."""
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise LabelsError(f"{path.name}: no es JSON ({exc})") from exc
    if not isinstance(doc, dict) or not isinstance(doc.get("labels"), list):
        raise LabelsError(f"{path.name}: se esperaba {{'judge', 'labels': [...]}}")
    if doc.get("kind", LABELS_KIND) != LABELS_KIND:
        raise LabelsError(f"{path.name}: kind {doc.get('kind')!r} != {LABELS_KIND!r}")
    judge = str(doc.get("judge") or "").strip()
    if not judge:
        stem = path.stem
        judge = stem[len("labels-"):] if stem.startswith("labels-") else stem
    entries: dict[str, dict[str, Any]] = {}
    for i, e in enumerate(doc["labels"]):
        if not isinstance(e, dict) or not isinstance(e.get("file"), str) or not e["file"]:
            raise LabelsError(f"{path.name}: entrada {i} sin 'file'")
        if e.get("decided") is False:  # borrador pendiente exportado a mano: no es un voto
            continue
        combo = e.get("combo_id")
        if not (combo is None or (isinstance(combo, int) and not isinstance(combo, bool) and 1 <= combo <= 348)):
            raise LabelsError(f"{path.name}: {e['file']}: combo_id {combo!r} no es null ni 1..348")
        tags = e.get("tags") or []
        if not isinstance(tags, list) or not all(isinstance(t, str) for t in tags):
            raise LabelsError(f"{path.name}: {e['file']}: 'tags' debe ser una lista de cadenas")
        if e["file"] in entries:
            raise LabelsError(f"{path.name}: {e['file']} repetido")
        sha = e.get("sha256")
        entries[e["file"]] = {"combo_id": combo, "tags": tags, "sha256": sha if isinstance(sha, str) else None,
                              "note": str(e.get("note") or "")}
    return judge, entries


def labels_meta(path: Path) -> dict[str, Any]:
    """Metadatos de un labels-<juez>.json: versión del motor y top-K mostrados, diccionario y set_hash."""
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return {}
    if not isinstance(doc, dict):
        return {}
    return {k: doc[k] for k in ("engine", "top", "dict_version", "set_hash", "generated_at") if k in doc}


def find_labels_files(labels: Path) -> list[Path]:
    if labels.is_file():
        return [labels]
    return sorted(labels.glob("labels-*.json")) if labels.is_dir() else []


def previous_masks(golden_dir: Path) -> dict[str, dict[str, str]]:
    """``masks`` de un ``manifest.json`` anterior (si existe y se puede leer)."""
    path = golden_dir / l4.MANIFEST_NAME
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return {}
    entries = doc.get("photos", doc.get("entries")) if isinstance(doc, dict) else doc
    out: dict[str, dict[str, str]] = {}
    for e in entries if isinstance(entries, list) else []:
        if isinstance(e, dict) and isinstance(e.get("file"), str) and isinstance(e.get("masks"), dict):
            out[e["file"]] = {str(k): v for k, v in e["masks"].items() if isinstance(v, str)}
    return out


# --------------------------------------------------------------------------------------
# merge
# --------------------------------------------------------------------------------------


def merge(golden_dir: Path, labels_paths: list[Path], known_tags: list[str], expected_judges: int | None,
          log=print) -> tuple[dict[str, Any], list[str]]:
    """Manifest fusionado y lista de problemas (vacía = fusión completa)."""
    photos, problems = list_photos(golden_dir)
    judges: dict[str, dict[str, dict[str, Any]]] = {}
    sources: dict[str, dict[str, Any]] = {}
    for p in labels_paths:
        try:
            judge, entries = read_labels_file(p)
        except LabelsError as exc:
            problems.append(str(exc))
            continue
        if judge in judges:
            problems.append(f"{p.name}: juez {judge!r} repetido (ya cargado); fichero ignorado")
            continue
        judges[judge] = entries
        sources[judge] = {"file": p.name, **labels_meta(p)}
        unknown = sorted(set(entries) - {ph.name for ph in photos})
        if unknown:
            problems.append(f"{judge}: {len(unknown)} etiqueta(s) de ficheros que no están en {golden_dir}: {', '.join(unknown[:5])}")
    if not judges:
        problems.append("ningún fichero de etiquetas legible")
    for key in ("set_hash", "dict_version"):
        values = {m[key] for m in sources.values() if key in m}
        if len(values) > 1:
            problems.append(f"los jueces etiquetaron páginas distintas ({key}: {', '.join(sorted(map(str, values)))}); regenera index.html una vez y reetiqueta")
    if expected_judges is not None and judges and len(judges) != expected_judges:
        problems.append(f"{len(judges)} juez/jueces ({', '.join(sorted(judges))}); se esperaban {expected_judges}")

    discovered, orphans = discover_masks(golden_dir, [ph.name for ph in photos])
    kept = previous_masks(golden_dir)
    if orphans:
        problems.append(f"{len(orphans)} máscara(s) PGM sin foto (se esperaba <stem>.<variante>.pgm): {', '.join(orphans[:5])}")

    entries_out: list[dict[str, Any]] = []
    unlabeled: list[str] = []
    without_consensus: list[str] = []
    consensus_none: list[str] = []
    n_consensus = 0
    for ph in photos:
        digest = l4.sha256_file(ph)
        labels: dict[str, int | None] = {}
        tags: set[str] = set()
        notes: dict[str, str] = {}
        for judge, entries in sorted(judges.items()):
            e = entries.get(ph.name)
            if e is None:
                problems.append(f"{ph.name}: sin etiqueta de {judge}")
                continue
            if e["sha256"] and e["sha256"].lower() != digest:
                problems.append(f"{ph.name}: sha256 de {judge} ({e['sha256'][:12]}…) != fichero actual ({digest[:12]}…): etiqueta descartada, la foto cambió después de etiquetarla")
                continue
            labels[judge] = e["combo_id"]
            for t in e["tags"]:
                if t not in known_tags:
                    problems.append(f"{ph.name}: tag {t!r} de {judge} no está en la lista conocida ({', '.join(known_tags)})")
                tags.add(t)
            if e["note"]:
                notes[judge] = e["note"]
        if not labels:
            unlabeled.append(ph.name)
            continue
        c = l4.consensus(labels)
        kind = consensus_kind(labels)
        if kind == "combo":
            n_consensus += 1
        elif kind == "none":
            consensus_none.append(ph.name)
        else:
            without_consensus.append(ph.name)
        entry: dict[str, Any] = {"file": ph.name, "sha256": digest, "tags": sorted(tags), "labels": labels, "consensus": c,
                                 "consensus_kind": kind}
        masks = {**discovered.get(ph.name, {}), **kept.get(ph.name, {})}
        if masks:
            entry["masks"] = dict(sorted(masks.items()))
        if notes:
            entry["notes"] = notes
        entries_out.append(entry)
    if unlabeled:
        problems.append(f"{len(unlabeled)} foto(s) sin ninguna etiqueta válida (no entran en el manifest): {', '.join(unlabeled[:10])}")
    n_judges = max((len(e["labels"]) for e in entries_out), default=0)
    complete = [e["labels"] for e in entries_out if len(e["labels"]) == n_judges]
    kappa = l4.fleiss_kappa(complete) if complete else None
    sde = os.environ.get("SOURCE_DATE_EPOCH")
    generated = (dt.datetime.fromtimestamp(int(sde), dt.timezone.utc) if sde else dt.datetime.now(dt.timezone.utc)).replace(microsecond=0).isoformat()
    manifest = {
        "schema": 1,
        "generated_by": "oracle/tools/merge_labels.py",
        "generated_at": generated,
        "judges": sorted(judges),
        "label_sources": {j: sources[j] for j in sorted(sources)},
        "tags_known": list(known_tags),
        "n_photos": len(entries_out),
        "n_consensus": n_consensus,
        "consensus_none": consensus_none,
        "without_consensus": without_consensus,
        "unlabeled": unlabeled,
        "fleiss_kappa": kappa,
        "fleiss_kappa_photos": len(complete) if kappa is not None else 0,
        "n_with_masks": sum(1 for e in entries_out if "masks" in e),
        "photos": entries_out,
    }
    return manifest, problems


def cmd_merge(args: argparse.Namespace) -> int:
    th, _defaulted = l4.resolve_thresholds(load_thresholds(args.thresholds))
    known_tags, _missing = resolve_tags(th)
    expected = int(th["judges"]) if not args.any_judges else None
    if not args.golden_dir.is_dir():
        print(f"labels-merge: {args.golden_dir} no es un directorio", file=sys.stderr)
        return 2
    labels_paths = find_labels_files(args.labels)
    if not labels_paths:
        print(f"labels-merge: no hay labels-*.json en {args.labels}", file=sys.stderr)
        return 2
    manifest, problems = merge(args.golden_dir, labels_paths, known_tags, expected)
    out = args.out or (args.golden_dir / l4.MANIFEST_NAME)
    out.write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    kappa = manifest["fleiss_kappa"]
    print(f"labels-merge: {manifest['n_photos']} fotos, jueces: {', '.join(manifest['judges']) or '—'}; "
          f"consenso en {manifest['n_consensus']}/{manifest['n_photos']} (+{len(manifest['consensus_none'])} \"ninguna\" por mayoría); "
          + (f"Fleiss κ = {kappa:.3f} (sobre {manifest['fleiss_kappa_photos']} fotos con todos los jueces)" if kappa is not None
             else "Fleiss κ no calculable (menos de 2 fotos o de 2 jueces)")
          + f"; {manifest['n_with_masks']} con máscaras")
    if manifest["without_consensus"]:
        print(f"  sin consenso ({len(manifest['without_consensus'])}): {', '.join(manifest['without_consensus'][:20])}"
              + (" …" if len(manifest["without_consensus"]) > 20 else ""))
    if manifest["consensus_none"]:
        print(f"  \"ninguna\" por mayoría ({len(manifest['consensus_none'])}; no puntúan recall, el motor no propuso la combinación): "
              + ", ".join(manifest["consensus_none"][:20]) + (" …" if len(manifest["consensus_none"]) > 20 else ""))
    for p in problems[:40]:
        print(f"  [problema] {p}")
    if len(problems) > 40:
        print(f"  … {len(problems) - 40} problema(s) más")
    print(f"  escrito {out}")
    return 1 if problems else 0


# --------------------------------------------------------------------------------------
# check
# --------------------------------------------------------------------------------------


def check(golden_dir: Path, thresholds: dict[str, Any] | None, log=print) -> tuple[bool, list[l4.Check]]:
    th, defaulted = l4.resolve_thresholds(thresholds)
    tags_required, tags_missing_in_th = resolve_tags(th)
    judges_required = int(th["judges"])
    checks: list[l4.Check] = []

    def add(c: l4.Check) -> None:
        checks.append(c)
        log(f"  [{c.status:>7}] {c.name}" + (f": {c.detail.splitlines()[0]}" if c.detail else ""))
        for extra in c.detail.splitlines()[1:12]:
            log(f"            {extra}")

    if not golden_dir.is_dir():
        add(l4.Check("directorio dorado", "fail", f"{golden_dir} no existe"))
        return False, checks
    try:
        entries = l4.load_manifest(golden_dir)
    except (l4.ManifestError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        add(l4.Check("manifest.json", "fail", f"{exc} (genera el manifest con make labels-merge GOLDEN_DIR=... LABELS=...)"))
        return False, checks
    add(l4.Check("manifest.json", "pass", f"{len(entries)} fotos en {golden_dir}", value=len(entries)))
    files = [e["file"] for e in entries]
    dupes = sorted({f for f in files if files.count(f) > 1})
    if dupes:
        add(l4.Check("ficheros repetidos en el manifest", "fail", ", ".join(dupes[:10]), value=len(dupes), threshold=0))

    rejected: list[str] = []
    rejected_files: set[str] = set()
    sizes: dict[str, tuple[int, int]] = {}
    for e in entries:
        problems, info = l4.verify_photo(golden_dir, e)
        if "width" in info:
            sizes[e["file"]] = (int(info["width"]), int(info["height"]))
        if problems:
            rejected += problems
            rejected_files.add(e["file"])
    add(l4.Check("fotos: sha256, PNG/JPEG sRGB, lado <= 256 px, sin HEIC", "pass" if not rejected else "fail",
                 f"{len(entries) - len(rejected_files)}/{len(entries)} aceptadas" + ("\n" + "\n".join(rejected[:10]) if rejected else ""),
                 value=len(rejected), threshold=0))
    photos_in_dir, dir_problems = list_photos(golden_dir)
    extra = sorted({p.name for p in photos_in_dir} - set(files))
    if dir_problems:
        add(l4.Check("ficheros HEIC en el directorio", "fail", "\n".join(dir_problems[:10]), value=len(dir_problems), threshold=0))
    if extra:
        add(l4.Check("fotos del directorio sin entrada en el manifest", "info",
                     f"{len(extra)} (no puntúan; etiquétalas y repite labels-merge): {', '.join(extra[:10])}", value=len(extra)))

    n_min, n_target = int(th["golden_min_photos"]), int(th.get("golden_target_photos", 100))
    n = len(entries)
    if n < n_min:
        detail = f"{n} fotos: faltan {n_min - n} para el mínimo de {n_min} ({n_target - n} para el objetivo de {n_target}); ver docs/SHOTLIST.md"
    elif n < n_target:
        detail = f"{n} fotos (mínimo cumplido; faltan {n_target - n} para el objetivo de {n_target})"
    else:
        detail = f"{n} fotos (objetivo de {n_target} alcanzado)"
    add(l4.Check(f"fotos >= {n_min} (golden_min_photos; objetivo {n_target})", "pass" if n >= n_min else "fail", detail,
                 value=n, threshold=n_min))

    seen_tags = {t for e in entries for t in e["tags"]}
    missing_tags = [t for t in tags_required if t not in seen_tags]
    unknown_tags = sorted(seen_tags - set(tags_required))
    per_tag = {t: sum(1 for e in entries if t in e["tags"]) for t in tags_required}
    add(l4.Check("todos los tags presentes al menos una vez", "pass" if not missing_tags else "fail",
                 ", ".join(f"{t} {k}" for t, k in per_tag.items()) + (f"; faltan: {', '.join(missing_tags)}" if missing_tags else "")
                 + (f"; tags desconocidos: {', '.join(unknown_tags)}" if unknown_tags else ""), value=len(missing_tags), threshold=0))
    short = [f"{t} {per_tag[t]}/{goal}" for t, goal in SHOTLIST_TARGETS.items() if per_tag.get(t, 0) < goal]
    add(l4.Check("objetivos por tag de docs/SHOTLIST.md", "info",
                 ("por debajo del objetivo: " + ", ".join(short)) if short else "todos los objetivos por tag alcanzados", value=len(short)))
    if tags_missing_in_th:
        add(l4.Check("thresholds.json L4.tags incompleto", "info",
                     f"falta {', '.join(tags_missing_in_th)} en harness/thresholds.json (ruta protegida: lo promueve el usuario); se exige igualmente"))

    bad_judges = [f"{e['file']} ({len(e['labels'])})" for e in entries if len(e["labels"]) != judges_required]
    judges = sorted({j for e in entries for j in e["labels"]})
    add(l4.Check(f"{judges_required} etiquetas por foto (judges)", "pass" if not bad_judges else "fail",
                 f"jueces: {', '.join(judges) or '—'}" + (f"; fotos con otro número: {', '.join(bad_judges[:10])}" if bad_judges else ""),
                 value=len(bad_judges), threshold=0))

    with_masks = [e for e in entries if "masks" in e]
    mask_problems = [p for e in with_masks for p in validate_masks(golden_dir, e, sizes.get(e["file"]))]
    if with_masks:
        variants = sorted({v for e in with_masks if isinstance(e["masks"], dict) for v in e["masks"]})
        add(l4.Check("máscaras (masks): existen y miden como la foto", "pass" if not mask_problems else "fail",
                     f"{len(with_masks)} foto(s) con máscaras; variantes: {', '.join(variants) or '—'}"
                     + ("\n" + "\n".join(mask_problems[:10]) if mask_problems else ""), value=len(mask_problems), threshold=0))
    else:
        add(l4.Check("máscaras (masks)", "info", "ninguna foto trae máscaras (campo opcional; las exporta la app junto a cada PNG)"))

    kinds = [(e["file"], consensus_kind(e["labels"])) for e in entries]
    n_cons = sum(1 for _f, k in kinds if k == "combo")
    none_files = [f for f, k in kinds if k == "none"]
    tie_files = [f for f, k in kinds if k == "tie"]
    kappa = l4.fleiss_kappa([e["labels"] for e in entries])
    add(l4.Check("consenso por mayoría y Fleiss κ", "info",
                 f"{n_cons}/{len(entries)} fotos con consenso en una combinación (puntúan en L4); "
                 + (f"Fleiss κ = {kappa:.3f}" if kappa is not None else "Fleiss κ no calculable (menos de 2 fotos/jueces o número desigual de jueces por foto)")
                 + (("; \"ninguna\" por mayoría: " + ", ".join(none_files))[:400] if none_files else "")
                 + (("; sin consenso: " + ", ".join(tie_files))[:400] if tie_files else ""),
                 value=kappa))
    if defaulted:
        add(l4.Check("umbrales L4 con valores por defecto (no promovidos)", "info", ", ".join(defaulted), value=len(defaulted)))
    ok = not any(c.status == "fail" for c in checks)
    return ok, checks


def cmd_check(args: argparse.Namespace) -> int:
    print(f"golden-check (set dorado): {args.golden_dir}")
    ok, checks = check(args.golden_dir, load_thresholds(args.thresholds))
    n_pass = sum(1 for c in checks if c.status == "pass")
    n_fail = sum(1 for c in checks if c.status == "fail")
    fails = [c.name for c in checks if c.status == "fail"]
    print(f"golden-check: {'PASS' if ok else 'FAIL'} ({n_pass} pass, {n_fail} fail, {len(checks) - n_pass - n_fail} info)"
          + (f"; falla: {'; '.join(fails)}" if fails else ""))
    return 0 if ok else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python oracle/tools/merge_labels.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    m = sub.add_parser("merge", help="fusiona labels-<juez>.json en manifest.json")
    m.add_argument("--golden-dir", type=Path, required=True)
    m.add_argument("--labels", type=Path, required=True, help="directorio con labels-*.json (o un fichero)")
    m.add_argument("--out", type=Path, default=None, help="por defecto <golden-dir>/manifest.json")
    m.add_argument("--thresholds", type=Path, default=l4.REPO_ROOT / "harness" / "thresholds.json")
    m.add_argument("--any-judges", action="store_true", help="no exigir L4.judges jueces (fusión parcial)")
    c = sub.add_parser("check", help="valida manifest.json y las fotos (fila F8 del plan)")
    c.add_argument("--golden-dir", type=Path, required=True)
    c.add_argument("--thresholds", type=Path, default=l4.REPO_ROOT / "harness" / "thresholds.json")
    args = ap.parse_args(argv)
    return cmd_merge(args) if args.command == "merge" else cmd_check(args)


if __name__ == "__main__":
    sys.exit(main())
