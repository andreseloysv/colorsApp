"""Capa 4 por variantes de recorte (sección 10 del contexto: fotos con varias personas; F9).

La app analiza por defecto la persona más grande, solo la ropa y con piel adaptativa
(``largest-clothing-skin``). Este módulo mide, sobre las mismas fotos con consenso del set
dorado, cuánto cambia el acierto frente a analizar la foto completa (``none``):

- Variantes: ``none``, ``allPeople``, ``largest``, ``largest-clothing`` y
  ``largest-clothing-skin`` (oficial, la de la app).
- Origen de la máscara de cada foto y variante, en este orden:
  (a) campo ``masks`` del manifest (``{variante: fichero.pgm}``, relativo al directorio
      dorado): las máscaras que exporta la app, preferidas porque son las del dispositivo;
  (b) ``visionmask`` ejecutado sobre la foto (``$COLORSAPP_VISIONMASK`` o
      ``build-subject/visionmask``; con ``build=True`` se compila con ``make visionmask`` si
      falta). Si Vision no encuentra a nadie, la variante se analiza sin máscara, igual que
      la app (``SubjectMaskResult.mask == nil``);
  (c) sin máscara del manifest ni ``visionmask``: la variante queda ``skipped`` en esa foto
      con el motivo.
- Todas las variantes usan el mismo PPM de ``tools.to_ppm`` (el único decodificador de la
  capa 4) y una sola invocación de ``ce batch`` con líneas ``"imagen.ppm" "mascara.pgm"``.
- Métricas por variante y por tag (``grupo`` incluido): recall@1/@3 contra el consenso,
  delta frente a ``none`` sobre las mismas fotos (pareado), cuota de la clase más frecuente,
  tasa de ``ambiguous``, fracción de fotos con persona detectada y con máscara, pasos de
  fallback más frecuentes (``poseRegions``, ``headCut``, ``wholePerson``, ``skinGuard``...).
- Gate propuesto, no promovido: la variante oficial no puede quedar más de 3 puntos por
  debajo de ``none`` en recall@3 agregado. Mientras ``harness/thresholds.json`` no tenga la
  sección ``L4_variants`` el check es ``info``; la propuesta se escribe en
  ``<out>/thresholds.proposed.json`` (``harness/thresholds.proposed.json`` es ruta protegida).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from oracle import l3
from oracle.l2 import Check

REPO_ROOT = Path(__file__).resolve().parents[2]
VARIANTS: tuple[str, ...] = ("none", "allPeople", "largest", "largest-clothing", "largest-clothing-skin")
OFFICIAL_VARIANT = "largest-clothing-skin"
VARIANT_LABELS = {
    "none": "foto completa",
    "allPeople": "todas las personas",
    "largest": "persona más grande",
    "largest-clothing": "más grande, solo ropa",
    "largest-clothing-skin": "más grande, ropa sin piel (app)",
}
VARIANT_RE = re.compile(r"^[A-Za-z0-9_-]+$")
VISIONMASK_ENV = "COLORSAPP_VISIONMASK"
DEFAULT_VISIONMASK = REPO_ROOT / "build-subject" / "visionmask"
VISIONMASK_TIMEOUT = 300.0
GROUP_TAG = "grupo"
GATE_KEY = "official_recall_at_3_minus_none_min_points"
PROPOSAL: dict[str, Any] = {
    "description": ("Capa 4 por variantes de recorte (sección 10 del contexto). La variante oficial es la que usa "
                    "la app por defecto; el delta se mide frente a 'none' sobre las mismas fotos con consenso."),
    "variants": list(VARIANTS),
    "official_variant": OFFICIAL_VARIANT,
    GATE_KEY: -3.0,
    "note": ("Propuesta del agente, no promovida: con el set dorado real, la variante oficial no puede quedar más "
             "de 3 puntos por debajo de 'none' en recall@3 agregado. Mientras harness/thresholds.json no tenga "
             "L4_variants el check es informativo."),
    "proposed_by": "agent",
    "promoted_by": None,
}

Log = Callable[[str], None]


class VariantError(RuntimeError):
    """visionmask o ce batch no produjeron una salida utilizable."""


# --------------------------------------------------------------------------------------
# PNM y visionmask
# --------------------------------------------------------------------------------------

_PNM_TOKEN = re.compile(rb"(?:\s|#[^\n]*\n)*(\S+)")


def pnm_header(path: Path) -> tuple[bytes, int, int, int, int]:
    """(magic, ancho, alto, maxval, offset del cuerpo) de un PPM/PGM binario (P6/P5)."""
    data = path.read_bytes()[:256]
    magic = data[:2]
    if magic not in (b"P5", b"P6"):
        raise ValueError(f"{path.name}: no es P5/P6")
    pos = 2
    values: list[int] = []
    for _ in range(3):
        m = _PNM_TOKEN.match(data, pos)
        if not m or not m.group(1).isdigit():
            raise ValueError(f"{path.name}: cabecera PNM incompleta")
        values.append(int(m.group(1)))
        pos = m.end()
    return magic, values[0], values[1], values[2], pos + 1


def pgm_foreground_pixels(path: Path) -> int:
    """Píxeles >= 128 de un PGM P5 de 8 bits (la cobertura que usa SubjectKit)."""
    magic, w, h, maxval, off = pnm_header(path)
    if magic != b"P5" or maxval != 255:
        raise ValueError(f"{path.name}: se esperaba P5 con maxval 255")
    body = path.read_bytes()[off:off + w * h]
    if len(body) < w * h:
        raise ValueError(f"{path.name}: cuerpo truncado")
    return sum(1 for b in body if b >= 128)


def find_visionmask(explicit: Path | str | None = None) -> Path | None:
    """Ruta explícita (solo esa) o, sin ella, ``$COLORSAPP_VISIONMASK`` y ``build-subject/visionmask``."""
    if explicit:
        candidates = [Path(explicit).expanduser()]
    else:
        env = os.environ.get(VISIONMASK_ENV)
        candidates = ([Path(env).expanduser()] if env else []) + [DEFAULT_VISIONMASK]
    for c in candidates:
        if c.is_file() and os.access(c, os.X_OK):
            return c
    return None


def ensure_visionmask(explicit: Path | str | None, build: bool, log: Log = print) -> tuple[Path | None, str]:
    """(ruta, motivo). Si no existe y ``build``: ``make visionmask`` (solo macOS) y se vuelve a buscar."""
    found = find_visionmask(explicit)
    if found is not None:
        return found, ""
    missing = str(explicit) if explicit else f"{DEFAULT_VISIONMASK.relative_to(REPO_ROOT)} ni ${VISIONMASK_ENV}"
    if not build:
        return None, f"no existe {missing} (make visionmask)"
    log("  visionmask no existe: make visionmask")
    proc = subprocess.run(["make", "-C", str(REPO_ROOT), "visionmask"], capture_output=True, text=True, check=False)
    found = find_visionmask(explicit)
    if proc.returncode != 0 or found is None:
        tail = (proc.stdout + proc.stderr).strip().splitlines()[-3:]
        return None, f"no existe {missing} y make visionmask falló (exit {proc.returncode}): {' | '.join(tail)}"
    return found, ""


def run_visionmask(visionmask: Path, image: Path, out_dir: Path, variants: list[str], *, layers: bool = False,
                   max_side: int | None = None, timeout: float = VISIONMASK_TIMEOUT) -> dict[str, Any]:
    """Ejecuta ``visionmask <image> --out-dir out_dir --variants ...`` y devuelve su ``<base>.json``.

    Exit 1 (Vision no disponible o error del motor) no es excepción: el JSON lo refleja con
    ``steps: [visionUnavailable]`` o ``error`` por variante. Exit 2 o falta de JSON sí lo son.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    cmd = [str(visionmask), str(image), "--out-dir", str(out_dir), "--variants", ",".join(variants)]
    if layers:
        cmd.append("--layers")
    if max_side:
        cmd += ["--max-side", str(int(max_side))]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise VariantError(f"visionmask {image.name}: timeout de {timeout:.0f} s") from exc
    except OSError as exc:
        raise VariantError(f"visionmask {image.name}: {exc}") from exc
    summary = out_dir / f"{image.stem}.json"
    stderr = "\n".join(line for line in proc.stderr.splitlines() if "FBBA" not in line).strip()
    if proc.returncode not in (0, 1) or not summary.is_file():
        raise VariantError(f"visionmask {image.name} -> exit {proc.returncode}: {stderr[:300]}")
    try:
        doc = json.loads(summary.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise VariantError(f"visionmask {image.name}: {summary.name} no es JSON ({exc})") from exc
    if not isinstance(doc, dict) or doc.get("tool") != "visionmask" or not isinstance(doc.get("variants"), list):
        raise VariantError(f"visionmask {image.name}: {summary.name} no tiene el formato de visionmask")
    doc["_exit"] = proc.returncode
    doc["_stderr"] = stderr
    return doc


def variant_entry(doc: dict[str, Any], name: str) -> dict[str, Any] | None:
    for v in doc.get("variants") or []:
        if isinstance(v, dict) and v.get("name") == name:
            return v
    return None


# --------------------------------------------------------------------------------------
# Resolución de máscaras
# --------------------------------------------------------------------------------------


@dataclass
class MaskChoice:
    """Máscara de una foto para una variante. ``status``: ok | skipped | error."""

    variant: str
    status: str
    source: str | None = None  # none | manifest | visionmask
    mask: Path | None = None
    detected: bool | None = None
    steps: list[str] = field(default_factory=list)
    people: int | None = None
    coverage: float | None = None
    reason: str = ""

    def as_json(self) -> dict[str, Any]:
        return {"variant": self.variant, "status": self.status, "source": self.source,
                "mask": str(self.mask) if self.mask is not None else None, "detected": self.detected,
                "steps": list(self.steps), "people": self.people, "coverage": self.coverage, "reason": self.reason}


def _manifest_mask(golden_dir: Path, rel: Any, size: tuple[int, int] | None) -> tuple[Path | None, str]:
    if not isinstance(rel, str) or not rel.lower().endswith(".pgm") or Path(rel).is_absolute() or ".." in Path(rel).parts:
        return None, f"máscara {rel!r} del manifest: debe ser un .pgm relativo al directorio dorado"
    path = golden_dir / rel
    if not path.is_file():
        return None, f"máscara {rel} del manifest: no existe"
    try:
        magic, w, h, maxval, _off = pnm_header(path)
    except (OSError, ValueError) as exc:
        return None, f"máscara {rel} del manifest: {exc}"
    if magic != b"P5" or maxval != 255:
        return None, f"máscara {rel} del manifest: se esperaba PGM P5 de 8 bits"
    if size is not None and (w, h) != tuple(size):
        return None, f"máscara {rel} del manifest mide {w}x{h} y la foto {size[0]}x{size[1]}"
    return path, ""


def resolve_masks(golden_dir: Path, entry: dict[str, Any], variants: list[str], visionmask: Path | None,
                  work_dir: Path, *, image_size: tuple[int, int] | None = None, no_visionmask_reason: str = "",
                  photo_path: Path | None = None) -> tuple[dict[str, MaskChoice], dict[str, Any] | None]:
    """Máscara por variante para una foto: manifest > visionmask > skipped. Devuelve también el JSON de
    visionmask si se ejecutó (``None`` si no hizo falta o no había binario)."""
    choices: dict[str, MaskChoice] = {}
    declared = entry.get("masks") if isinstance(entry.get("masks"), dict) else {}
    pending: list[str] = []
    for v in variants:
        if v == "none":
            choices[v] = MaskChoice(v, "ok", source="none", steps=[])
            continue
        if v in declared:
            path, problem = _manifest_mask(golden_dir, declared[v], image_size)
            if path is None:
                choices[v] = MaskChoice(v, "error", source="manifest", reason=problem)
                continue
            try:
                fg = pgm_foreground_pixels(path)
            except (OSError, ValueError) as exc:
                choices[v] = MaskChoice(v, "error", source="manifest", reason=str(exc))
                continue
            w, h = image_size if image_size else pnm_header(path)[1:3]
            choices[v] = MaskChoice(v, "ok", source="manifest", mask=path, detected=fg > 0,
                                    coverage=fg / float(w * h) if w * h else None)
            continue
        pending.append(v)
    doc: dict[str, Any] | None = None
    if not pending:
        return choices, doc
    if visionmask is None:
        reason = "sin máscara en el manifest y sin visionmask" + (f" ({no_visionmask_reason})" if no_visionmask_reason else "")
        for v in pending:
            choices[v] = MaskChoice(v, "skipped", reason=reason)
        return choices, doc
    image = photo_path if photo_path is not None else golden_dir / entry["file"]
    try:
        doc = run_visionmask(visionmask, image, work_dir, pending)
    except VariantError as exc:
        for v in pending:
            choices[v] = MaskChoice(v, "error", source="visionmask", reason=str(exc))
        return choices, None
    people = int(doc.get("people_count") or 0)
    vision_ok = bool((doc.get("vision") or {}).get("available", True))
    size_problem = ""
    if image_size is not None and (doc.get("width"), doc.get("height")) != tuple(image_size):
        size_problem = (f"visionmask rasterizó {doc.get('width')}x{doc.get('height')} y la foto mide "
                        f"{image_size[0]}x{image_size[1]}")
    for v in pending:
        ve = variant_entry(doc, v)
        if ve is None:
            choices[v] = MaskChoice(v, "error", source="visionmask", reason=f"visionmask no devolvió la variante {v}")
            continue
        if "error" in ve:
            choices[v] = MaskChoice(v, "error", source="visionmask", reason=f"visionmask {v}: {ve['error']}")
            continue
        mask = Path(ve["mask"]) if isinstance(ve.get("mask"), str) else None
        choice = MaskChoice(v, "ok", source="visionmask", mask=mask, detected=(people > 0) if vision_ok else None,
                            steps=[str(s) for s in ve.get("steps") or []], people=people,
                            coverage=float(ve["mask_coverage"]) if isinstance(ve.get("mask_coverage"), (int, float)) else None)
        if size_problem and mask is not None:
            choice.status, choice.reason = "error", size_problem
        choices[v] = choice
    return choices, doc


# --------------------------------------------------------------------------------------
# ce batch con máscara por línea
# --------------------------------------------------------------------------------------


def _quote(path: Path) -> str:
    text = str(path)
    if '"' in text or "\n" in text:
        raise VariantError(f"ruta no representable en una línea de ce batch: {text!r}")
    return f'"{text}"'


def run_batch_lines(cli: Path, lines: list[tuple[Path, Path | None]], *, top: int = l3.TOP_K,
                    timeout: float = l3.BATCH_TIMEOUT) -> list[dict[str, Any]]:
    """Una invocación de ``ce batch`` con líneas ``"imagen" ["mascara"]``; una fila por línea, en orden."""
    if not lines:
        return []
    with tempfile.TemporaryDirectory(prefix="colorsapp-l4v-") as tmp:
        listing = Path(tmp) / "batch.txt"
        listing.write_text("".join(f"{_quote(img)}" + (f" {_quote(m)}" if m is not None else "") + "\n"
                                   for img, m in lines), encoding="utf-8")
        cmd = [str(cli), "batch", str(listing), "--top", str(int(top)), "--json"]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            raise VariantError(f"ce batch: timeout de {timeout:.0f} s") from exc
    if proc.returncode not in (0, 1):
        raise VariantError(f"ce batch -> exit {proc.returncode}: {proc.stderr.strip()[:300]}")
    rows: list[dict[str, Any]] = []
    for line in proc.stdout.splitlines():
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            raise VariantError(f"ce batch: línea que no es JSON ({exc}): {line[:200]!r}") from exc
        rows.append(obj if isinstance(obj, dict) else {"error": "línea JSON que no es un objeto"})
    if len(rows) != len(lines):
        raise VariantError(f"ce batch: {len(rows)} líneas JSON para {len(lines)} entradas (exit {proc.returncode})")
    return rows


# --------------------------------------------------------------------------------------
# Métricas (puras: sin CLI)
# --------------------------------------------------------------------------------------


def _points(a: float, b: float) -> float:
    return round(100.0 * (float(a) - float(b)), 6)


def subset_metrics(truth: list[int], results: list[dict[str, Any]], none_results: list[dict[str, Any]],
                   choices: list[MaskChoice]) -> dict[str, Any]:
    """Métricas de una variante sobre las fotos que no quedaron ``skipped`` (índices ya filtrados)."""
    m = l3.metrics_for(truth, results)
    base = l3.metrics_for(truth, none_results)
    known = [c.detected for c in choices if c.detected is not None]
    steps: Counter = Counter()
    for c in choices:
        for s in dict.fromkeys(c.steps):  # un paso cuenta una vez por foto
            steps[s] += 1
    out = {
        **m,
        "none_recall_at_1": base["recall_at_1"],
        "none_recall_at_3": base["recall_at_3"],
        "delta_recall_at_1_points": _points(m["recall_at_1"], base["recall_at_1"]) if m["n"] else None,
        "delta_recall_at_3_points": _points(m["recall_at_3"], base["recall_at_3"]) if m["n"] else None,
        "person_detected_rate": (sum(1 for k in known if k) / len(known)) if known else None,
        "person_known": len(known),
        "mask_rate": (sum(1 for c in choices if c.mask is not None) / len(choices)) if choices else 0.0,
        "sources": dict(Counter(c.source for c in choices if c.source)),
        "top_steps": [[s, n] for s, n in sorted(steps.items(), key=lambda kv: (-kv[1], kv[0]))[:4]],
    }
    return out


def compute_variant_metrics(variants: list[str], truth: list[int], tags: list[list[str]],
                            choices: dict[str, list[MaskChoice]], results: dict[str, list[dict[str, Any]]],
                            all_tags: list[str] | None = None) -> dict[str, Any]:
    """Métricas agregadas y por tag de cada variante.

    ``choices[v][i]`` y ``results[v][i]`` son la máscara y el resultado de ``ce`` de la foto ``i``
    (``results["none"]`` es obligatorio). Las fotos ``skipped`` de una variante no cuentan en su
    ``n``; las ``error`` sí (fallan el recall, como en L3). El delta frente a ``none`` es pareado:
    ``none`` se recalcula sobre las mismas fotos.
    """
    n = len(truth)
    if "none" not in results or len(results["none"]) != n:
        raise ValueError("results['none'] debe tener un resultado por foto")
    tag_list = sorted(set(all_tags or []) | {t for ts in tags for t in ts} | {GROUP_TAG})
    out: dict[str, Any] = {}
    for v in variants:
        ch = choices[v]
        res = results[v]
        idx = [i for i in range(n) if ch[i].status != "skipped"]
        skipped = [i for i in range(n) if ch[i].status == "skipped"]
        reasons = Counter(ch[i].reason for i in skipped)
        status = "skipped" if not idx else ("partial" if skipped else "ok")

        def pick(ids: list[int]) -> dict[str, Any]:
            return subset_metrics([truth[i] for i in ids], [res[i] for i in ids], [results["none"][i] for i in ids],
                                  [ch[i] for i in ids])

        entry: dict[str, Any] = {"variant": v, "label": VARIANT_LABELS.get(v, v), "official": v == OFFICIAL_VARIANT,
                                 "status": status, "n_photos": n, "n_skipped": len(skipped),
                                 "skip_reasons": [[r, c] for r, c in reasons.most_common()],
                                 "errors_detail": [ch[i].reason for i in idx if ch[i].status == "error"][:10]}
        if idx:
            entry["aggregate"] = pick(idx)
            by_tag: dict[str, Any] = {}
            for t in tag_list:
                ids = [i for i in idx if t in tags[i]]
                by_tag[t] = pick(ids) if ids else {"n": 0}
            entry["by_tag"] = by_tag
        out[v] = entry
    return {"variants": out, "order": list(variants), "official": OFFICIAL_VARIANT, "tags": tag_list}


# --------------------------------------------------------------------------------------
# Gate, tabla y propuesta
# --------------------------------------------------------------------------------------


def _pct(x: float | None) -> str:
    return "—" if x is None else f"{100.0 * float(x):.1f} %"


def _pts(x: float | None) -> str:
    return "—" if x is None else f"{x:+.1f}"


def gate_check(summary: dict[str, Any], thresholds: dict[str, Any] | None) -> Check:
    """Gate de la variante oficial frente a ``none`` (recall@3 agregado, pareado)."""
    section = (thresholds or {}).get("L4_variants") if thresholds else None
    promoted = isinstance(section, dict) and GATE_KEY in section
    minimum = float(section[GATE_KEY]) if promoted else float(PROPOSAL[GATE_KEY])
    name = (f"variantes: {OFFICIAL_VARIANT} recall@3 >= none {minimum:+.0f} puntos"
            + ("" if promoted else " (propuesto, no promovido)"))
    entry = summary["variants"].get(OFFICIAL_VARIANT)
    if entry is None or entry["status"] == "skipped" or "aggregate" not in entry:
        reason = "; ".join(r for r, _c in (entry or {}).get("skip_reasons", [])) or "variante oficial no evaluada"
        return Check(name, "skipped", f"skipped: {reason}", threshold=minimum)
    agg = entry["aggregate"]
    delta = agg["delta_recall_at_3_points"]
    ok = delta is not None and delta >= minimum
    detail = (f"{_pct(agg['recall_at_3'])} frente a none {_pct(agg['none_recall_at_3'])} sobre las mismas {agg['n']} fotos "
              f"(Δ {_pts(delta)} puntos)")
    if promoted:
        return Check(name, "pass" if ok else "fail", detail, value=delta, threshold=minimum)
    return Check(name, "info", f"{'cumpliría' if ok else 'NO cumpliría'} el gate propuesto: {detail}", value=delta, threshold=minimum)


def render_markdown(summary: dict[str, Any], gate: Check | None = None) -> str:
    """Tabla comparativa de variantes (oficial en negrita) y recall@3 por tag."""
    order = summary["order"]
    rows = summary["variants"]
    lines = [
        f"Variante oficial: **{OFFICIAL_VARIANT}** (la que usa la app por defecto). Δ = puntos frente a `none` sobre "
        "las mismas fotos con consenso. Origen de máscaras: manifest (app) > visionmask > skipped.",
        "",
        "| variante | estado | fotos | origen | recall@1 | recall@3 | Δ@1 | Δ@3 | cuota máx. | ambiguous | persona detectada | con máscara | pasos más frecuentes |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for v in order:
        e = rows[v]
        label = f"**{v} (oficial)**" if e["official"] else v
        if "aggregate" not in e:
            reason = "; ".join(r for r, _c in e["skip_reasons"]) or "—"
            lines.append(f"| {label} | skipped | 0/{e['n_photos']} | — | — | — | — | — | — | — | — | — | {reason} |")
            continue
        a = e["aggregate"]
        src = ", ".join(f"{k} {c}" for k, c in sorted(a["sources"].items())) or "—"
        steps = ", ".join(f"{s} {c}" for s, c in a["top_steps"]) or "—"
        share = f"{_pct(a['max_class_share'])} (combo {a['max_class_id']})" if a["max_class_id"] is not None else "—"
        is_none = v == "none"
        cells = [label, e["status"] + (f" ({e['n_skipped']} skipped)" if e["n_skipped"] else ""), f"{a['n']}/{e['n_photos']}", src,
                 _pct(a["recall_at_1"]), _pct(a["recall_at_3"]),
                 "—" if is_none else _pts(a["delta_recall_at_1_points"]), "—" if is_none else _pts(a["delta_recall_at_3_points"]),
                 share, _pct(a["ambiguous_rate"]), "—" if is_none else _pct(a["person_detected_rate"]),
                 "—" if is_none else _pct(a["mask_rate"]), "—" if is_none else steps]
        if e["official"]:
            cells = [c if c.startswith("**") else f"**{c}**" for c in cells]
        lines.append("| " + " | ".join(cells) + " |")
    lines += ["", "recall@3 por tag (n = fotos con consenso del tag; Δ frente a none en las mismas fotos):", "",
              "| tag | " + " | ".join(f"**{v}**" if v == OFFICIAL_VARIANT else v for v in order) + " |",
              "|---|" + "---|" * len(order)]
    for t in summary["tags"]:
        cells = []
        for v in order:
            bt = (rows[v].get("by_tag") or {}).get(t)
            if not bt or not bt.get("n"):
                cells.append("—")
                continue
            delta = "" if v == "none" else f", Δ {_pts(bt['delta_recall_at_3_points'])}"
            cells.append(f"{_pct(bt['recall_at_3'])} (n={bt['n']}{delta})")
        lines.append(f"| {t} | " + " | ".join(cells) + " |")
    if gate is not None:
        lines += ["", f"Gate: `{gate.name}` → **{gate.status}**: {gate.detail}"]
    return "\n".join(lines) + "\n"


def write_proposal(out_dir: Path) -> Path:
    """Añade/actualiza la sección ``L4_variants`` en ``<out_dir>/thresholds.proposed.json``."""
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "thresholds.proposed.json"
    doc: dict[str, Any] = {}
    if path.is_file():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            doc = loaded if isinstance(loaded, dict) else {}
        except json.JSONDecodeError:
            doc = {}
    doc.setdefault("schema", 1)
    doc.setdefault("note", "Propuestas del agente (no promovidas). Solo el usuario copia claves a harness/thresholds.json.")
    doc["L4_variants"] = PROPOSAL
    path.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


# --------------------------------------------------------------------------------------
# Orquestación dentro de run_layer4
# --------------------------------------------------------------------------------------


def run_variants(cli: Path, golden_dir: Path, scored: list[tuple[dict[str, Any], int]], ppm_files: list[Path],
                 none_results: list[dict[str, Any]], work: Path, *, variants: list[str] | None = None,
                 visionmask: Path | str | None = "auto", build_visionmask: bool = False,
                 thresholds: dict[str, Any] | None = None, all_tags: list[str] | None = None,
                 log: Log = print) -> tuple[list[Check], dict[str, Any]]:
    """Evalúa las variantes sobre las fotos puntuables. ``visionmask``: ``"auto"`` (entorno o
    build-subject), una ruta, o ``None`` (no usar visionmask)."""
    variants = list(variants or VARIANTS)
    if "none" not in variants:
        variants.insert(0, "none")
    bad = [v for v in variants if not VARIANT_RE.match(v)]
    if bad:
        raise ValueError(f"variantes inválidas: {bad}")
    needs_vm = any(v != "none" and not (isinstance(e.get("masks"), dict) and v in e["masks"])
                   for e, _c in scored for v in variants)
    vm_path: Path | None = None
    vm_reason = ""
    if visionmask is None:
        vm_reason = "visionmask desactivado"
    elif needs_vm:
        vm_path, vm_reason = ensure_visionmask(None if visionmask == "auto" else visionmask, build_visionmask, log)
    truth = [c for _e, c in scored]
    tags = [list(e.get("tags") or []) for e, _c in scored]
    choices: dict[str, list[MaskChoice]] = {v: [] for v in variants}
    vm_docs: list[dict[str, Any] | None] = []
    for i, ((e, _c), ppm) in enumerate(zip(scored, ppm_files)):
        _magic, w, h, _maxval, _off = pnm_header(ppm)
        ch, doc = resolve_masks(golden_dir, e, variants, vm_path, work / "visionmask" / f"p{i:03d}",
                                image_size=(w, h), no_visionmask_reason=vm_reason)
        vm_docs.append(doc)
        for v in variants:
            choices[v].append(ch[v])
    # Una sola invocación de ce batch para todas las variantes con máscara (none ya está calculado).
    lines: list[tuple[Path, Path | None]] = []
    where: list[tuple[str, int]] = []
    results: dict[str, list[dict[str, Any]]] = {v: [{} for _ in scored] for v in variants}
    results["none"] = list(none_results)
    for v in variants:
        if v == "none":
            continue
        for i, c in enumerate(choices[v]):
            if c.status == "ok":
                lines.append((ppm_files[i], c.mask))
                where.append((v, i))
            elif c.status == "error":
                results[v][i] = {"error": c.reason}
            else:
                results[v][i] = {"skipped": c.reason}
    rows = run_batch_lines(cli, lines) if lines else []
    for (v, i), r in zip(where, rows):
        results[v][i] = r
    summary = compute_variant_metrics(variants, truth, tags, choices, results, all_tags=all_tags)
    checks: list[Check] = []
    src_counts = {v: dict(Counter((c.source or c.status) for c in choices[v])) for v in variants if v != "none"}
    checks.append(Check("variantes: origen de las máscaras (manifest > visionmask > skipped)", "info",
                        "; ".join(f"{v}: " + ", ".join(f"{k} {n}" for k, n in sorted(cnt.items())) for v, cnt in src_counts.items())
                        + (f"; visionmask: {vm_path}" if vm_path else (f"; visionmask no disponible ({vm_reason})" if vm_reason else ""))))
    contract = []
    for v in variants:
        if v == "none":
            continue
        for i, r in enumerate(results[v]):
            if "skipped" in r:
                continue
            problems = l3.validate_match_result(r)
            if not problems and r.get("mask") != (str(choices[v][i].mask) if choices[v][i].mask is not None else None):
                problems = [f"ce batch usó la máscara {r.get('mask')!r} y se pidió {choices[v][i].mask}"]
            contract += [f"{v} {scored[i][0]['file']}: {p}" for p in problems]
    checks.append(Check("variantes: ce batch con máscara por línea (contrato y máscara usada)", "pass" if not contract else "fail",
                        f"{len(rows)} análisis con máscara o sin ella; problemas: {len(contract)}"
                        + ("\n" + "\n".join(contract[:8]) if contract else ""), value=len(contract), threshold=0))
    for v in variants:
        e = summary["variants"][v]
        name = f"variante {v}{' (oficial)' if e['official'] else ''}: recall@3"
        if "aggregate" not in e:
            checks.append(Check(name, "skipped", "skipped: " + ("; ".join(r for r, _c in e["skip_reasons"]) or "sin fotos")))
            continue
        a = e["aggregate"]
        extra = "" if v == "none" else (f", Δ@3 {_pts(a['delta_recall_at_3_points'])} puntos vs none, persona detectada "
                                        f"{_pct(a['person_detected_rate'])}, con máscara {_pct(a['mask_rate'])}, pasos "
                                        + (", ".join(f"{s} {c}" for s, c in a["top_steps"]) or "—"))
        checks.append(Check(name, "info", f"recall@1 {_pct(a['recall_at_1'])}, recall@3 {_pct(a['recall_at_3'])} sobre {a['n']} fotos"
                            + (f" ({e['n_skipped']} skipped)" if e["n_skipped"] else "")
                            + f"; cuota {_pct(a['max_class_share'])}, ambiguous {_pct(a['ambiguous_rate'])}{extra}",
                            value=float(a["recall_at_3"])))
    gate = gate_check(summary, thresholds)
    checks.append(gate)
    detail = {
        **summary,
        "gate": {"name": gate.name, "status": gate.status, "detail": gate.detail, "value": gate.value, "threshold": gate.threshold},
        "visionmask": str(vm_path) if vm_path else None,
        "visionmask_reason": vm_reason or None,
        "per_photo": [
            {"file": e["file"], "consensus": c, "tags": e.get("tags") or [],
             "people": (vm_docs[i] or {}).get("people_count") if vm_docs[i] else None,
             "variants": {v: {**choices[v][i].as_json(), "top": l3.ranked_ids(results[v][i]),
                              "ambiguous": results[v][i].get("ambiguous"),
                              "error": results[v][i].get("error")} for v in variants}}
            for i, (e, c) in enumerate(scored)],
    }
    detail["markdown"] = render_markdown(summary, gate)
    return checks, detail
