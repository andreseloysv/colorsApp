#!/usr/bin/env python3
"""Página estática de etiquetado del set dorado (fase 8): ``harness/label/index.html``.

    uv run --project oracle python oracle/tools/label_page.py --golden-dir DIR
        [--out harness/label/index.html] [--ce build/tools/ce] [--top 10] [--strict]

Para cada foto del directorio dorado (solo PNG o JPEG sRGB de lado <= 256 px; HEIC/HEIF y
fotos grandes se rechazan con mensaje y no entran en la página, igual que
``l4.run.verify_photo``) incrusta la imagen en base64 y el top-``K`` del motor calculado con
``ce batch`` sobre la foto completa (opciones por defecto; swatches de cada candidata con número
y nombre curado si ``data/wada/names.es.json`` lo tiene), con botones para elegir una candidata
o "ninguna"; campos: juez, tags (multiselección: ``negro, denim, gris, interior, fondo-sucio,
blanco, grupo``) y nota. El botón "Descargar" produce ``labels-<juez>.json`` (``{"schema": 1,
"kind": "colorsapp-labels", "judge", "dict_version", "labels": [{"file", "sha256", "combo_id":
1..348|null, "tags", "note"}]}``), que ``merge_labels.py`` fusiona en ``manifest.json``. Sin
``fetch`` ni red; el borrador vive en localStorage por juez.

Capas de la app (opcional): si junto a una foto hay máscaras ``<stem>.<variante>.pgm`` (las que
exporta "Exportar diagnóstico") o el ``manifest.json`` las declara en ``masks``, la tarjeta
permite cambiar de vista (foto completa / persona principal / solo ropa / sin piel): la máscara
se superpone a la foto (fuera de la máscara, atenuado) y las candidatas pasan a ser el top-K de
``ce match --mask`` con esa máscara. Así el juez ve qué persona toma la app en una foto de grupo.

La página documenta el protocolo: tres jueces independientes, sin ver las etiquetas de los
otros, consenso por mayoría; en fotos de grupo se etiqueta la PERSONA MÁS GRANDE (la que usa la
app por defecto). Cada foto se escribe también como bloque HTML estático (``<article
class="card">`` con la imagen y el top-K), legible sin JavaScript.

**La página contiene las fotos**: por defecto se genera en una ruta protegida del repo
(``harness/label/**``); con fotos personales usa ``--out $COLORSAPP_GOLDEN_DIR/index.html``
(las fotos nunca entran en un commit, CLAUDE.md).

Códigos de salida: 0 página escrita (las fotos rechazadas se listan; con ``--strict`` un rechazo
da 2); 1 HTML mal formado; 2 sin fotos válidas, ``ce`` inexistente o sin ``batch``.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import datetime as dt
import hashlib
import html as htmlmod
import io
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from l4 import run as l4
from oracle import l3
from oracle import names as nm
from oracle.l2 import load_thresholds
from tools import merge_labels as ml

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "harness" / "label" / "index.html"
DEFAULT_DICTIONARY = REPO_ROOT / "data" / "wada" / "dictionary.json"
DEFAULT_NAMES = REPO_ROOT / "data" / "wada" / "names.es.json"
DEFAULT_TAGS = list(ml.GOLDEN_TAGS)
TOP_DEFAULT = 10
MIME = {"PNG": "image/png", "JPEG": "image/jpeg"}
#: Variantes de máscara en el orden de preferencia de la vista inicial (la primera es la que usa la app por defecto).
VIEW_ORDER = ["largest-clothing-skin", "largest-clothing", "largest", "allPeople"]
VIEW_LABELS = {
    "none": "Foto completa",
    "allPeople": "Todas las personas",
    "largest": "Persona principal",
    "largest-clothing": "Principal · solo ropa",
    "largest-clothing-skin": "Principal · ropa sin piel (app)",
}
_PLACEHOLDER = re.compile(r"__(STATIC_CARDS|TAG_LABELS|TAGS|META|NAMES|DICTIONARY|PHOTOS)__")
TAG_LABELS = {"interior": "interior / luz cálida", "fondo-sucio": "fondo sucio", "grupo": "grupo (varias personas)"}


# --------------------------------------------------------------------------------------
# Fotos y motor
# --------------------------------------------------------------------------------------


def collect_photos(golden_dir: Path) -> tuple[list[dict[str, Any]], list[str]]:
    """Fotos aceptadas (file, sha256, format, width, height, masks) y problemas (HEIC, > 256 px, ...)."""
    photos, problems = ml.list_photos(golden_dir)
    discovered, _orphans = ml.discover_masks(golden_dir, [p.name for p in photos])
    declared = ml.previous_masks(golden_dir)
    accepted: list[dict[str, Any]] = []
    for p in photos:
        digest = l4.sha256_file(p)
        errs, info = l4.verify_photo(golden_dir, {"file": p.name, "sha256": digest})
        if errs:
            problems += errs
            continue
        masks = {**discovered.get(p.name, {}), **declared.get(p.name, {})}
        accepted.append({"file": p.name, "sha256": digest, "format": info["format"], "width": info["width"],
                         "height": info["height"], "masks": masks})
    return accepted, problems


def resolve_ce(explicit: str | None) -> tuple[Path | None, str]:
    """(ruta a ``ce`` o None, motivo). Una ruta explícita que no existe es un error (no se cae a build/)."""
    if explicit:
        p = Path(explicit)
        if p.is_file() and os.access(p, os.X_OK):
            return p, ""
        return None, f"--ce {explicit}: no existe o no es ejecutable (make build, o cmake --build <dir> --target ce)"
    p = l3.find_cli_optional(None)
    return (p, "") if p is not None else (None, l3.not_implemented_reason(None))


def ordered_variants(masks: dict[str, str]) -> list[str]:
    return [v for v in VIEW_ORDER if v in masks] + sorted(v for v in masks if v not in VIEW_ORDER)


def _hits_payload(r: dict[str, Any]) -> dict[str, Any]:
    view: dict[str, Any] = {
        "hits": [{"id": int(h["id"]), "score": round(float(h["score"]), 3)} for h in r.get("hits", []) if isinstance(h, dict)],
        "swatches": [{"hex": s["hex"], "weight": round(float(s["weight"]), 3)} for s in r.get("swatches", []) if isinstance(s, dict)],
        "ambiguous": int(r.get("ambiguous", 0) or 0),
    }
    if "error" in r or not view["hits"]:
        view["error"] = str(r.get("error") or "el motor no devolvió candidatas")
    return view


def run_masked_match(cli: Path, ppm: Path, pgm: Path, top: int, timeout: float = 60.0) -> dict[str, Any]:
    """``ce match img.ppm --mask m.pgm --top K --json``; un error del CLI se devuelve como ``{"error"}``."""
    cmd = [str(cli), "match", str(ppm), "--mask", str(pgm), "--top", str(int(top)), "--json"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"error": f"ce match --mask: {exc}"}
    if proc.returncode != 0:
        return {"error": f"ce match --mask -> exit {proc.returncode}: {proc.stderr.strip()[:200]}"}
    try:
        doc = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        return {"error": f"ce match --mask: stdout no es JSON ({exc})"}
    return doc if isinstance(doc, dict) else {"error": "ce match --mask: el JSON no es un objeto"}


def mask_overlay_png(pgm: Path) -> str:
    """PNG RGBA en base64: transparente dentro de la máscara (>= 128), negro semitransparente fuera."""
    from PIL import Image

    with Image.open(pgm) as m:
        mask = m.convert("L")
    alpha = mask.point(lambda v: 0 if v >= 128 else 170)
    black = Image.new("L", mask.size, 0)
    buf = io.BytesIO()
    Image.merge("RGBA", (black, black, black, alpha)).save(buf, format="PNG", optimize=True)
    return base64.b64encode(buf.getvalue()).decode("ascii")


def run_engine(cli: Path, golden_dir: Path, photos: list[dict[str, Any]], top: int) -> list[list[dict[str, Any]]]:
    """Vistas por foto: ``none`` (``ce batch --top K`` sobre la foto completa) y una por máscara disponible."""
    from tools import to_ppm

    with tempfile.TemporaryDirectory(prefix="colorsapp-label-") as tmp:
        files: list[Path] = []
        sizes: list[tuple[int, int]] = []
        with contextlib.redirect_stderr(io.StringIO()):
            for i, ph in enumerate(photos):
                dst = Path(tmp) / f"p{i:04d}.ppm"
                sizes.append(to_ppm.convert(golden_dir / ph["file"], dst, max_side=l4.MAX_SIDE))
                files.append(dst)
        whole = l3.run_batch(cli, files, top=top, use_batch=True)
        out: list[list[dict[str, Any]]] = []
        for ph, ppm, size, r in zip(photos, files, sizes, whole):
            views = [{"key": "none", "label": VIEW_LABELS["none"], **_hits_payload(r)}]
            for variant in ordered_variants(ph.get("masks") or {}):
                rel = ph["masks"][variant]
                view: dict[str, Any] = {"key": variant, "label": VIEW_LABELS.get(variant, variant), "mask": rel}
                problems = ml.validate_masks(golden_dir, {"file": ph["file"], "masks": {variant: rel}}, size)
                if problems:
                    view.update({"hits": [], "swatches": [], "ambiguous": 0, "error": "; ".join(problems)})
                else:
                    view.update(_hits_payload(run_masked_match(cli, ppm, golden_dir / rel, top)))
                    view["overlay"] = mask_overlay_png(golden_dir / rel)
                views.append(view)
            out.append(views)
        return out


def curated_names(names: list[dict[str, Any]]) -> dict[str, str]:
    """id -> nombre curado (solo entradas con nombre y estado distinto de pending)."""
    return {str(e["id"]): e["name"].strip() for e in names if not nm.is_pending(e) and e.get("name", "").strip()}


# --------------------------------------------------------------------------------------
# HTML
# --------------------------------------------------------------------------------------

HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Etiquetado del set dorado</title>
<style>
  :root { --bg:#f7f6f3; --card:#fff; --ink:#1d1d1b; --muted:#6b6b66; --line:#dcdad3; --accent:#1f5fa8; --warn:#b3261e; --ok:#2e7d32; --amber:#ef6c00; }
  * { box-sizing:border-box; }
  body { margin:0; font:15px/1.45 -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif; color:var(--ink); background:var(--bg); }
  header { position:sticky; top:0; z-index:5; background:var(--card); border-bottom:1px solid var(--line); padding:12px 20px; }
  header h1 { font-size:18px; margin:0 0 6px; }
  header h1 .meta { font-weight:normal; color:var(--muted); font-size:13px; }
  .help { font-size:13px; color:var(--muted); margin:0 0 8px; max-width:1100px; }
  .help strong { color:var(--ink); }
  .banner { font-size:13px; margin:0 0 8px; max-width:1100px; padding:7px 10px; border-radius:6px; background:#fff3e6; border:1px solid #f3c99a; color:#6d3a00; }
  details.protocol { font-size:13px; color:var(--muted); margin:0 0 10px; max-width:1100px; }
  details.protocol summary { cursor:pointer; color:var(--ink); font-weight:600; }
  details.protocol ol { margin:6px 0 0; padding-left:20px; }
  details.protocol li { margin:2px 0; }
  .toolbar { display:flex; flex-wrap:wrap; gap:10px; align-items:center; }
  .toolbar button, .toolbar label.btn { font:inherit; padding:6px 12px; border:1px solid var(--line); border-radius:6px; background:#fafaf8; cursor:pointer; }
  .toolbar button.primary { background:var(--accent); color:#fff; border-color:var(--accent); }
  .toolbar button:disabled { opacity:.45; cursor:default; }
  .toolbar input[type=text] { font:inherit; padding:6px 9px; border:1px solid var(--line); border-radius:6px; min-width:180px; }
  .toolbar .spacer { flex:1; }
  .toolbar .progress { font-variant-numeric:tabular-nums; color:var(--muted); }
  main { padding:16px 20px 60px; max-width:1400px; margin:0 auto; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:14px 16px 16px; margin:0 0 16px; display:grid; grid-template-columns: minmax(280px, 300px) minmax(320px, 1fr); gap:18px; border-left:5px solid #c7c5bd; }
  @media (max-width: 760px) { .card { grid-template-columns: 1fr; } }
  .card.done { border-left-color:var(--ok); }
  .card.none { border-left-color:var(--amber); }
  .card h2 { margin:0 0 8px; font-size:16px; display:flex; gap:10px; align-items:baseline; flex-wrap:wrap; }
  .card h2 .meta { font-weight:normal; color:var(--muted); font-size:13px; word-break:break-all; }
  .card h2 .state { font-weight:600; font-size:13px; color:var(--ok); }
  .card.none h2 .state { color:var(--amber); }
  .frame { position:relative; width:256px; max-width:100%; }
  .frame img { display:block; width:256px; max-width:100%; height:auto; border-radius:8px; border:1px solid var(--line); background:#eee; }
  .frame img.overlay { position:absolute; left:0; top:0; pointer-events:none; background:transparent; }
  .views { display:flex; flex-wrap:wrap; gap:4px; margin-top:8px; width:256px; max-width:100%; }
  .views button { font:inherit; font-size:12px; padding:3px 7px; border:1px solid var(--line); border-radius:12px; background:#fafaf8; cursor:pointer; }
  .views button.on { background:var(--accent); border-color:var(--accent); color:#fff; }
  .palette { display:flex; height:18px; border-radius:5px; overflow:hidden; margin-top:8px; width:256px; max-width:100%; border:1px solid rgba(0,0,0,.12); }
  .palette span { display:block; height:100%; }
  .photo .meta { font-size:12px; color:var(--muted); margin-top:6px; }
  .grupo-aviso { font-size:12px; margin-top:8px; padding:5px 8px; border-radius:6px; background:#fff3e6; border:1px solid #f3c99a; color:#6d3a00; width:256px; max-width:100%; }
  .cands { display:grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap:8px; }
  .cands-title { font-size:12px; color:var(--muted); margin:0 0 6px; }
  .cand { font:inherit; text-align:left; padding:8px; border:1px solid var(--line); border-radius:8px; background:#fafaf8; cursor:pointer; display:flex; flex-direction:column; gap:6px; }
  .cand:hover { border-color:var(--accent); }
  .cand.chosen { border:2px solid var(--accent); background:#eef4fb; }
  .cand .chips { display:flex; gap:3px; height:34px; }
  .cand .chips span { flex:1; border-radius:4px; border:1px solid rgba(0,0,0,.12); }
  .cand .label { font-size:12px; line-height:1.3; }
  .cand .label b { display:block; font-weight:600; font-size:13px; }
  .cand .label .score { color:var(--muted); }
  .cand.nonebtn { justify-content:center; align-items:center; font-weight:600; color:var(--warn); min-height:64px; }
  .cand.nonebtn.chosen { border-color:var(--amber); background:#fff3e6; color:var(--amber); }
  .chosen-outside { font-size:12px; color:var(--accent); margin:6px 0 0; }
  .other { display:flex; flex-wrap:wrap; gap:6px; align-items:center; margin-top:8px; font-size:13px; }
  .other input { font:inherit; width:84px; padding:4px 6px; border:1px solid var(--line); border-radius:6px; }
  .other button { font:inherit; font-size:13px; padding:4px 10px; border:1px solid var(--line); border-radius:6px; background:#fafaf8; cursor:pointer; }
  .other .chips { display:flex; gap:2px; height:20px; min-width:60px; }
  .other .chips span { width:20px; border-radius:3px; border:1px solid rgba(0,0,0,.12); }
  .error { color:var(--warn); font-size:13px; }
  .static-cands ol { margin:0; padding-left:22px; font-size:13px; }
  .static-cands .chip { display:inline-block; width:14px; height:14px; border-radius:3px; margin-right:2px; vertical-align:-2px; border:1px solid rgba(0,0,0,.15); }
  .fields { margin-top:12px; }
  .fields label.t { display:block; font-size:12px; color:var(--muted); margin:8px 0 4px; }
  .tags { display:flex; flex-wrap:wrap; gap:6px 12px; }
  .tags label { font-size:13px; display:flex; gap:4px; align-items:center; cursor:pointer; }
  .fields textarea { width:100%; font:inherit; padding:7px 9px; border:1px solid var(--line); border-radius:6px; background:#fff; min-height:44px; resize:vertical; }
  .foot { text-align:center; color:var(--muted); font-size:13px; margin-top:20px; }
  .toast { position:fixed; bottom:16px; left:50%; transform:translateX(-50%); background:#333; color:#fff; padding:8px 14px; border-radius:6px; font-size:13px; opacity:0; transition:opacity .2s; pointer-events:none; }
  .toast.show { opacity:1; }
</style>
</head>
<body>
<header>
  <h1>Etiquetado del set dorado <span class="meta" id="meta"></span></h1>
  <p class="help">
    Para cada foto, mira la <strong>prenda</strong> (no los swatches) y elige la combinación de Wada que dirías que lleva puesta
    entre las candidatas del motor; si ninguna encaja, pulsa <strong>Ninguna de estas</strong> (es una respuesta válida y útil).
    Marca los <strong>tags</strong> que describen la foto y deja una nota si quieres. Escribe tu <strong>nombre de juez</strong> arriba y, al terminar,
    pulsa <strong>Descargar labels-&lt;juez&gt;.json</strong>; entrega ese fichero (fuera del repo) para <code>make labels-merge</code>.
    El borrador se guarda solo en este navegador (localStorage) por juez; <strong>Cargar</strong> retoma un JSON descargado antes.
  </p>
  <p class="banner" id="grupo-banner">
    <strong>Fotos de grupo (varias personas):</strong> etiqueta solo a la <strong>persona más grande</strong> de la foto (la que ocupa más área),
    que es la que analiza la app por defecto, y marca el tag <strong>grupo</strong>. Si la foto trae las máscaras de la app, la vista
    <em>Persona principal</em> la resalta y atenúa el resto.
  </p>
  <details class="protocol">
    <summary>Protocolo de etiquetado (tres jueces independientes)</summary>
    <ol>
      <li><strong>Tres jueces</strong> etiquetan el mismo set completo, cada uno en su propio navegador o dispositivo, con su propio nombre de juez.</li>
      <li><strong>Independencia</strong>: no se comentan las fotos ni se miran las etiquetas de los otros hasta que los tres hayan descargado su <code>labels-&lt;juez&gt;.json</code>. Si compartís ordenador, cada juez usa su nombre (el borrador es por juez) y no abre el borrador ajeno.</li>
      <li><strong>Criterio</strong>: la etiqueta es la combinación que <em>lleva la prenda</em> en la foto, juzgada a ojo; el orden y los scores del motor son solo ayuda. Si reconoces la combinación y no está entre las candidatas, escríbela en <em>Otra combinación</em> (Nº 1–348); "Ninguna" cuando ninguna se parece.</li>
      <li><strong>Fotos de grupo</strong>: se etiqueta la <strong>persona más grande</strong> (la misma que usa la app por defecto: persona principal, solo ropa, piel excluida), nunca una mezcla de varias personas ni el fondo.</li>
      <li><strong>Consenso por mayoría</strong>: <code>make labels-merge</code> fusiona los tres ficheros; la etiqueta de consenso es la que eligen al menos 2 de 3. Si es una combinación, la foto puntúa en la capa 4; si es "ninguna", queda como <em>ninguna por mayoría</em> (el motor no propuso la combinación: se reporta aparte y no puntúa recall). Sin mayoría queda <em>sin consenso</em> y se reporta; el acuerdo global se mide con Fleiss κ.</li>
      <li><strong>Tags</strong>: describen la condición de la foto (negro, denim, gris, interior/luz cálida, fondo sucio, blanco, grupo); en la fusión se unen los de todos los jueces.</li>
      <li>Las fotos son personales: este fichero y los <code>labels-*.json</code> no se suben al repo; viven con <code>$COLORSAPP_GOLDEN_DIR</code>.</li>
    </ol>
  </details>
  <div class="toolbar">
    <input type="text" id="judge" placeholder="nombre de juez (p. ej. ana)" autocomplete="off">
    <label><input type="checkbox" id="onlyPending"> solo pendientes</label>
    <label><input type="checkbox" id="showMask" checked> atenuar fuera de la máscara</label>
    <span class="progress" id="progress"></span>
    <span class="spacer"></span>
    <button id="reset">Descartar borrador</button>
    <label class="btn">Cargar labels-*.json <input type="file" id="load" accept="application/json,.json" hidden></label>
    <button class="primary" id="download">Descargar labels-&lt;juez&gt;.json</button>
  </div>
</header>
<main id="main">
__STATIC_CARDS__
</main>
<div class="toast" id="toast"></div>
<script>
// Datos incrustados por oracle/tools/label_page.py (sin peticiones de red): por foto, las vistas del motor
// (foto completa y, si hay, cada máscara de la app) con su top-K; diccionario recortado, nombres
// curados y tags. Las imágenes están una sola vez, en los bloques estáticos de <main>.
const PHOTOS = __PHOTOS__;
const DICT = __DICTIONARY__;
const NAMES = __NAMES__;
const TAGS = __TAGS__;
const TAG_LABELS = __TAG_LABELS__;
const META = __META__;
const STORAGE_PREFIX = "colorsapp.labels." + META.set_hash + ".";

const colorsByIndex = new Map(DICT.colors.map(c => [c.index, c]));
const combosById = new Map(DICT.combinations.map(c => [c.id, c]));
const $ = id => document.getElementById(id);
const IMG_SRC = new Map();
for (const p of PHOTOS) {
  const img = document.querySelector(`#photo-${p.i} img.photo-img`);
  IMG_SRC.set(p.i, img ? img.getAttribute("src") : "");
}

// Estado: file -> {combo: undefined (pendiente) | null ("ninguna") | id, tags: [], note: ""}.
let state = new Map();
const view = new Map(PHOTOS.map(p => [p.file, p.default_view]));
let judge = "";
function slug(name) { return (name || "").trim().toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, ""); }
function storageKey() { return STORAGE_PREFIX + (slug(judge) || "_"); }
function blank() { state = new Map(); for (const p of PHOTOS) state.set(p.file, { combo: undefined, tags: [], note: "" }); }
function seed(labels) {
  blank();
  for (const e of labels || []) {
    if (!state.has(e.file)) continue;
    const combo = (e.combo_id === null || e.combo_id === undefined) ? (e.decided === false ? undefined : null) : Number(e.combo_id);
    state.set(e.file, { combo, tags: Array.isArray(e.tags) ? e.tags.filter(t => TAGS.includes(t)) : [], note: String(e.note || "") });
  }
}
function exportLabels(includePending) {
  const out = [];
  for (const p of PHOTOS) {
    const e = state.get(p.file);
    if (e.combo === undefined && !includePending) continue;
    const row = { file: p.file, sha256: p.sha256, combo_id: e.combo === undefined ? null : e.combo, tags: e.tags.slice(), note: e.note };
    if (e.combo === undefined) row.decided = false;
    out.push(row);
  }
  return out;
}
function loadDraft() {
  try {
    const raw = localStorage.getItem(storageKey());
    if (raw) { seed(JSON.parse(raw)); return true; }
  } catch (err) { /* sin localStorage: se trabaja en memoria */ }
  return false;
}
function saveDraft() {
  try {
    localStorage.setItem(storageKey(), JSON.stringify(exportLabels(true)));
    localStorage.setItem(STORAGE_PREFIX + "judge", judge);
  } catch (err) { /* ignorar */ }
}
function isPending(e) { return e.combo === undefined; }
function updateProgress() {
  const done = PHOTOS.filter(p => !isPending(state.get(p.file))).length;
  $("progress").textContent = `${done} / ${PHOTOS.length} etiquetadas`;
  $("download").disabled = !slug(judge);
}
function pad3(n) { return String(n).padStart(3, "0"); }
function el(tag, attrs, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === "class") node.className = v; else if (k.startsWith("on")) node.addEventListener(k.slice(2), v); else node.setAttribute(k, v);
  }
  for (const ch of children) node.append(ch);
  return node;
}
function currentView(photo) { return photo.views.find(v => v.key === view.get(photo.file)) || photo.views[0]; }
function comboLabel(id) { const name = NAMES[String(id)]; return `Nº ${pad3(id)}` + (name ? ` · ${name}` : ""); }
function candidate(photo, hit, rank) {
  const combo = combosById.get(hit.id);
  const e = state.get(photo.file);
  const btn = el("button", { class: "cand" + (e.combo === hit.id ? " chosen" : ""), type: "button", onclick: () => choose(photo, hit.id) });
  const chips = el("div", { class: "chips" });
  for (const k of combo.colors) {
    const c = colorsByIndex.get(k);
    chips.append(el("span", { style: "background:" + c.hex, title: `${c.name} ${c.hex}` }));
  }
  const label = el("div", { class: "label" }, el("b", {}, `${rank}. ${comboLabel(hit.id)}`));
  label.append(el("span", { class: "score" }, `${combo.size} colores · score ${hit.score.toFixed(2)}`));
  btn.append(chips, label);
  return btn;
}
function choose(photo, combo) {
  const e = state.get(photo.file);
  e.combo = (e.combo === combo) ? undefined : combo;
  saveDraft(); renderCard(photo); updateProgress();
}
function stateLabel(e) {
  if (e.combo === undefined) return "";
  return e.combo === null ? "ninguna" : `elegida Nº ${pad3(e.combo)}`;
}
function renderCard(photo) {
  const e = state.get(photo.file);
  const v = currentView(photo);
  const old = document.getElementById("photo-" + photo.i);
  const card = el("article", { class: "card" + (e.combo === undefined ? "" : (e.combo === null ? " none" : " done")), id: "photo-" + photo.i, "data-file": photo.file });
  const left = el("div", { class: "photo" });
  left.append(el("h2", {}, `${photo.i + 1}.`, el("span", { class: "meta" }, photo.file), el("span", { class: "state" }, stateLabel(e))));
  const frame = el("div", { class: "frame" });
  frame.append(el("img", { class: "photo-img", src: IMG_SRC.get(photo.i), alt: photo.file, width: String(photo.width), height: String(photo.height) }));
  if (v.overlay && $("showMask").checked) {
    frame.append(el("img", { class: "overlay", src: "data:image/png;base64," + v.overlay, alt: "máscara " + v.label, width: String(photo.width), height: String(photo.height) }));
  }
  left.append(frame);
  if (photo.views.length > 1) {
    const views = el("div", { class: "views", title: "vista: foto completa o máscara exportada por la app" });
    for (const w of photo.views) {
      views.append(el("button", { type: "button", class: w.key === v.key ? "on" : "", onclick: () => { view.set(photo.file, w.key); renderCard(photo); } }, w.label));
    }
    left.append(views);
  }
  if (v.swatches.length) {
    const pal = el("div", { class: "palette", title: `paleta que vio el motor (${v.label}; peso por área)` });
    for (const s of v.swatches) pal.append(el("span", { style: `background:${s.hex};width:${(100 * s.weight).toFixed(1)}%` }));
    left.append(pal);
  }
  left.append(el("div", { class: "meta" }, `${photo.width}×${photo.height} px` + (v.ambiguous ? " · el motor duda entre las dos primeras" : "")));
  if (e.tags.includes("grupo")) left.append(el("div", { class: "grupo-aviso" }, "Foto de grupo: etiqueta la persona más grande (la que usa la app por defecto)."));
  const right = el("div", {});
  right.append(el("p", { class: "cands-title" }, `Candidatas del motor · ${v.label}` + (v.mask ? ` (máscara ${v.mask})` : "")));
  const cands = el("div", { class: "cands" });
  if (v.error) cands.append(el("div", { class: "error" }, "Sin candidatas: " + v.error));
  v.hits.forEach((h, k) => cands.append(candidate(photo, h, k + 1)));
  cands.append(el("button", { class: "cand nonebtn" + (e.combo === null ? " chosen" : ""), type: "button", onclick: () => choose(photo, null) }, "Ninguna de estas"));
  right.append(cands);
  if (typeof e.combo === "number" && !v.hits.some(h => h.id === e.combo)) {
    right.append(el("p", { class: "chosen-outside" }, `Elegida fuera de estas candidatas: ${comboLabel(e.combo)} (pulsa otra candidata o "Ninguna" para cambiarla).`));
  }
  // Otra combinación por número: evita que la etiqueta dependa del top-K de esta versión del motor.
  const other = el("div", { class: "other" });
  const num = el("input", { type: "number", min: "1", max: String(DICT.combinations.length), placeholder: "Nº", "aria-label": "otra combinación (número)" });
  const preview = el("span", { class: "chips" });
  const pick = el("button", { type: "button", disabled: "" }, "Elegir");
  num.addEventListener("input", () => {
    const id = Number(num.value);
    preview.innerHTML = "";
    const combo = Number.isInteger(id) ? combosById.get(id) : undefined;
    if (combo) {
      for (const k of combo.colors) { const c = colorsByIndex.get(k); preview.append(el("span", { style: "background:" + c.hex, title: `${c.name} ${c.hex}` })); }
      pick.removeAttribute("disabled"); pick.textContent = "Elegir " + comboLabel(id);
    } else { pick.setAttribute("disabled", ""); pick.textContent = "Elegir"; }
  });
  pick.addEventListener("click", () => { const id = Number(num.value); if (combosById.has(id) && e.combo !== id) choose(photo, id); });
  other.append("Otra combinación:", num, preview, pick);
  right.append(other);
  const fields = el("div", { class: "fields" });
  fields.append(el("label", { class: "t" }, "Tags"));
  const tags = el("div", { class: "tags" });
  for (const t of TAGS) {
    const cb = el("input", { type: "checkbox" });
    cb.checked = e.tags.includes(t);
    cb.addEventListener("change", () => { e.tags = TAGS.filter(x => x === t ? cb.checked : e.tags.includes(x)); saveDraft(); if (t === "grupo") renderCard(photo); });
    tags.append(el("label", {}, cb, TAG_LABELS[t] || t));
  }
  fields.append(tags);
  fields.append(el("label", { class: "t" }, "Nota"));
  const note = el("textarea", { placeholder: "opcional: por qué dudas, qué prenda, luz…" });
  note.value = e.note;
  note.addEventListener("input", () => { e.note = note.value; saveDraft(); });
  fields.append(note);
  right.append(fields);
  card.append(left, right);
  if (old) old.replaceWith(card); else $("main").append(card);
  return card;
}
function render() {
  const main = $("main");
  main.innerHTML = "";
  const only = $("onlyPending").checked;
  let shown = 0;
  for (const p of PHOTOS) {
    if (only && !isPending(state.get(p.file))) continue;
    shown++;
    main.append(renderCard(p));
  }
  if (!shown) main.append(el("p", { class: "foot" }, only ? "No quedan fotos pendientes." : "No hay fotos."));
  main.append(el("p", { class: "foot" }, `${PHOTOS.length} fotos · motor ${META.engine} · diccionario ${DICT.dict_version} · generado ${META.generated_at}`));
  updateProgress();
}
function toast(msg) { const t = $("toast"); t.textContent = msg; t.classList.add("show"); setTimeout(() => t.classList.remove("show"), 2600); }

// Descarga como data: URL (sin servidor).
function download() {
  const s = slug(judge);
  if (!s) { toast("Escribe tu nombre de juez antes de descargar"); return; }
  saveDraft();
  const pending = PHOTOS.filter(p => isPending(state.get(p.file))).length;
  if (pending && !confirm(`Quedan ${pending} fotos sin etiquetar; se descargan solo las etiquetadas. ¿Continuar?`)) return;
  const doc = { schema: 1, kind: "colorsapp-labels", judge: judge.trim(), dict_version: DICT.dict_version, engine: META.engine, top: META.top, set_hash: META.set_hash,
                generated_at: new Date().toISOString(), labels: exportLabels(false) };
  const text = JSON.stringify(doc, null, 1) + "\n";
  const a = document.createElement("a");
  a.href = "data:application/json;charset=utf-8," + encodeURIComponent(text);
  a.download = `labels-${s}.json`;
  document.body.append(a); a.click(); a.remove();
  toast(`labels-${s}.json descargado (${doc.labels.length} etiquetas): entrégalo para make labels-merge`);
}
function loadFile(file) {
  const reader = new FileReader();
  reader.onload = () => {
    try {
      const data = JSON.parse(reader.result);
      const labels = Array.isArray(data) ? data : data.labels;
      if (!Array.isArray(labels)) throw new Error("se esperaba {labels: [...]}");
      if (data.judge && !judge) { judge = String(data.judge); $("judge").value = judge; }
      seed(labels); saveDraft(); render(); toast(`Cargadas ${labels.length} etiquetas`);
    } catch (err) { toast("No se pudo leer el JSON: " + err.message); }
  };
  reader.readAsText(file);
}

$("onlyPending").addEventListener("change", render);
$("showMask").addEventListener("change", render);
$("download").addEventListener("click", download);
$("load").addEventListener("change", ev => { if (ev.target.files[0]) loadFile(ev.target.files[0]); ev.target.value = ""; });
$("reset").addEventListener("click", () => {
  if (!confirm("¿Descartar el borrador de este juez en este navegador?")) return;
  try { localStorage.removeItem(storageKey()); } catch (err) {}
  blank(); render(); toast("Borrador descartado");
});
$("judge").addEventListener("change", () => {
  judge = $("judge").value;
  if (!loadDraft()) blank();
  saveDraft(); render();
});

try { judge = localStorage.getItem(STORAGE_PREFIX + "judge") || ""; } catch (err) { judge = ""; }
$("judge").value = judge;
$("meta").textContent = `${META.golden_name} · ${PHOTOS.length} fotos · top-${META.top} del motor`;
if (!loadDraft()) blank();
render();
</script>
</body>
</html>
"""


def static_card(photo: dict[str, Any], image_b64: str, dictionary: dict[str, Any], names: dict[str, str]) -> str:
    """Bloque HTML estático de una foto (imagen + top-K de la foto completa), legible sin JavaScript."""
    esc = htmlmod.escape
    colors = {c["index"]: c for c in dictionary["colors"]}
    combos = {c["id"]: c for c in dictionary["combinations"]}
    whole = photo["views"][0]
    items: list[str] = []
    for rank, h in enumerate(whole["hits"], 1):
        chips = "".join(f'<span class="chip" style="background:{esc(colors[k]["hex"])}"></span>' for k in combos[h["id"]]["colors"])
        name = names.get(str(h["id"]))
        items.append(f'<li>{chips} Nº {h["id"]:03d}' + (f" · {esc(name)}" if name else "") + f' · score {h["score"]:.2f}</li>')
    cands = f'<ol>{"".join(items)}</ol>' if items else f'<p class="error">Sin candidatas: {esc(whole.get("error", ""))}</p>'
    variants = ", ".join(v["label"] for v in photo["views"][1:])
    return (
        f'<article class="card" id="photo-{photo["i"]}" data-file="{esc(photo["file"])}">\n'
        f'<div class="photo"><h2>{photo["i"] + 1}. <span class="meta">{esc(photo["file"])}</span></h2>'
        f'<div class="frame"><img class="photo-img" src="data:{photo["mime"]};base64,{image_b64}" alt="{esc(photo["file"])}" '
        f'width="{photo["width"]}" height="{photo["height"]}"></div></div>\n'
        f'<div class="static-cands"><p class="cands-title">Top-{len(whole["hits"])} del motor (foto completa)'
        + (f"; máscaras de la app: {esc(variants)}" if variants else "") + f"</p>{cands}</div>\n</article>"
    )


def build_html(photos: list[dict[str, Any]], images_b64: list[str], dictionary: dict[str, Any], names: list[dict[str, Any]],
               tags: list[str], meta: dict[str, Any]) -> str:
    slim = {
        "dict_version": dictionary["dict_version"],
        "colors": [{"index": c["index"], "name": c["name"], "hex": c["hex"]} for c in dictionary["colors"]],
        "combinations": [{"id": c["id"], "size": c["size"], "colors": c["colors"]} for c in dictionary["combinations"]],
    }
    curated = curated_names(names)
    cards = "\n".join(static_card(p, b64, dictionary, curated) for p, b64 in zip(photos, images_b64))
    values = {
        "STATIC_CARDS": cards,
        "TAG_LABELS": nm.embed_json({t: TAG_LABELS.get(t, t) for t in tags}),
        "TAGS": nm.embed_json(list(tags)),
        "META": nm.embed_json(meta),
        "NAMES": nm.embed_json(curated),
        "DICTIONARY": nm.embed_json(slim),
        "PHOTOS": nm.embed_json(photos),
    }
    # Una sola pasada sobre la plantilla: un "__X__" dentro de un nombre de fichero o de un nombre
    # curado no se interpreta nunca como marcador.
    return _PLACEHOLDER.sub(lambda m: values[m.group(1)], HTML_TEMPLATE)


def check_html(text: str, n_photos: int | None = None) -> list[str]:
    """Problemas de forma (vacía = bien formado): anidamiento, needles propios, sin red, bloques de foto."""
    parser = nm._WellFormedness()
    parser.feed(text)
    parser.close()
    problems = list(parser.problems)
    if not parser.doctype:
        problems.append("falta <!DOCTYPE html>")
    for open_tag, line in parser.stack:
        problems.append(f"<{open_tag}> abierto en la línea {line} sin cerrar")
    for needle in ("<title>", "</html>", "const PHOTOS = [", "const DICT = {", "const TAGS = [", "Ninguna de estas", "tres jueces",
                   "mayoría", "persona más grande", '"grupo"'):
        if needle not in text:
            problems.append(f"falta {needle!r}")
    if (re.search(r"\bfetch\s*\(", text) or "XMLHttpRequest" in text or "WebSocket" in text or "<script src" in text or "<link" in text
            or re.search(r"""(?:src|href)\s*=\s*["']?https?:|url\(\s*["']?https?:""", text)):
        problems.append("la página no debe hacer peticiones de red ni cargar recursos externos")
    if n_photos is not None:
        blocks = text.count('<article class="card" id="photo-')
        if blocks != n_photos:
            problems.append(f"{blocks} bloques de foto estáticos para {n_photos} fotos")
    return problems


def set_hash(photos: list[dict[str, Any]]) -> str:
    h = hashlib.sha256()
    for ph in photos:
        h.update(f"{ph['file']}\n{ph['sha256']}\n".encode("utf-8"))
    return h.hexdigest()[:12]


def generate(golden_dir: Path, out: Path, cli: Path | None, top: int, dictionary_path: Path, names_path: Path,
             tags: list[str], log=print, strict: bool = False, cli_reason: str = "") -> int:
    photos, problems = collect_photos(golden_dir)
    for p in problems:
        log(f"label-html: rechazada: {p}")
    if problems:
        log(f"label-html: {len(problems)} fichero(s) rechazado(s) en {golden_dir} (no entran en la página): "
            "exporta PNG o JPEG sRGB de 256 px, nunca HEIC")
        if strict:
            return 2
    if not photos:
        log(f"label-html: no hay PNG/JPEG válidos en {golden_dir}")
        return 2
    if cli is None or not l3.has_batch(cli):
        log(f"label-html: hace falta 'ce batch': {cli_reason or l3.not_implemented_reason(cli)}")
        return 2
    try:
        views = run_engine(cli, golden_dir, photos, top)
    except (l3.MatchError, RuntimeError) as exc:
        log(f"label-html: el motor falló: {exc}")
        return 2
    dictionary = nm.load_json(dictionary_path)
    names = nm.load_json(names_path) if names_path.is_file() else []
    sde = os.environ.get("SOURCE_DATE_EPOCH")
    generated_at = (dt.datetime.fromtimestamp(int(sde), dt.timezone.utc).date().isoformat() if sde
                    else dt.date.today().isoformat())
    payload: list[dict[str, Any]] = []
    images: list[str] = []
    for i, (ph, vs) in enumerate(zip(photos, views)):
        default = next((v["key"] for v in vs[1:] if "error" not in v), "none")
        payload.append({"i": i, "file": ph["file"], "sha256": ph["sha256"], "mime": MIME[ph["format"]], "width": ph["width"],
                        "height": ph["height"], "views": vs, "default_view": default})
        images.append(base64.b64encode((golden_dir / ph["file"]).read_bytes()).decode("ascii"))
    engine_version = _engine_version(cli)
    meta = {"generated_at": generated_at, "engine": engine_version, "top": top, "golden_name": golden_dir.name,
            "n": len(payload), "set_hash": set_hash(photos), "tags": list(tags)}
    html = build_html(payload, images, dictionary, names, tags, meta)
    issues = check_html(html, n_photos=len(payload))
    if issues:
        for issue in issues:
            log(f"label-html: HTML mal formado: {issue}")
        return 1
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
    errors = sum(1 for p in payload if "error" in p["views"][0])
    n_masked = sum(1 for p in payload if len(p["views"]) > 1)
    curated = len(curated_names(names))
    rel = out.relative_to(REPO_ROOT) if out.is_relative_to(REPO_ROOT) else out
    log(f"label-html: {rel} ({out.stat().st_size / 1e6:.2f} MB, {len(payload)} fotos de {golden_dir}, top-{top} de ce batch {engine_version}, "
        f"{n_masked} con máscaras de la app, {curated} nombres curados, {errors} sin candidatas, {len(problems)} rechazadas); "
        f"ábrelo en el navegador (open {out})")
    if out.is_relative_to(REPO_ROOT):
        log("label-html: AVISO: la página incrusta las fotos en base64; no la subas al repo con fotos personales "
            "(usa LABEL_HTML=$COLORSAPP_GOLDEN_DIR/index.html)")
    return 0


def _engine_version(cli: Path) -> str:
    try:
        proc = subprocess.run([str(cli), "version"], capture_output=True, text=True, check=False, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return "?"
    return proc.stdout.strip() or "?"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--golden-dir", type=Path, default=None, help=f"por defecto ${l4.GOLDEN_DIR_ENV}")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--ce", "--cli", dest="ce", type=str, default=None,
                    help="ruta al CLI ce (por defecto $COLORSAPP_CE_CLI o build/tools/ce)")
    ap.add_argument("--top", type=int, default=TOP_DEFAULT, help="candidatas por foto (1..10)")
    ap.add_argument("--strict", action="store_true", help="exit 2 si se rechaza algún fichero (HEIC, > 256 px...)")
    ap.add_argument("--dictionary", type=Path, default=DEFAULT_DICTIONARY)
    ap.add_argument("--names", type=Path, default=DEFAULT_NAMES)
    ap.add_argument("--thresholds", type=Path, default=REPO_ROOT / "harness" / "thresholds.json")
    args = ap.parse_args(argv)
    golden_dir = args.golden_dir or l4.golden_dir_from_env()
    if golden_dir is None or not golden_dir.is_dir():
        print(f"label-html: indica --golden-dir o exporta {l4.GOLDEN_DIR_ENV} (directorio con las fotos, fuera del repo)", file=sys.stderr)
        return 2
    if not 1 <= args.top <= 10:
        print("label-html: --top debe estar en 1..10", file=sys.stderr)
        return 2
    th, _ = l4.resolve_thresholds(load_thresholds(args.thresholds))
    tags, missing = ml.resolve_tags(th)
    if missing:
        print(f"label-html: aviso: harness/thresholds.json L4.tags no incluye {', '.join(missing)} (se usa igualmente)")
    cli, reason = resolve_ce(args.ce)
    return generate(golden_dir, args.out, cli, args.top, args.dictionary, args.names, tags, strict=args.strict, cli_reason=reason)


if __name__ == "__main__":
    sys.exit(main())
