"""Curación de nombres de las 348 combinaciones de Wada (``data/wada/names.es.json``).

    uv run --project oracle python -m oracle.names todo [--names RUTA]
    uv run --project oracle python -m oracle.names html [--out harness/label/names.html]

``todo`` imprime cuántas combinaciones siguen ``pending`` (sin nombre) y sus ids.

``html`` genera una página estática AUTOCONTENIDA (``dictionary.json`` y ``names.es.json``
incrustados, sin ``fetch``) con lotes de 20 combinaciones: swatches grandes, número,
tamaño, nombres de color en inglés, campos de nombre (español o alemán), idioma, estado
y notas, y un botón que descarga ``names.es.json`` actualizado como ``data:`` URL. El
borrador se guarda en ``localStorage`` del navegador. El usuario sustituye
``data/wada/names.es.json`` por el archivo descargado; ``make dict-check`` lo valida.

Los nombres son obra propia del curador (el libro solo numera las láminas) y van en
español o alemán; el HTML lo recuerda en su texto de ayuda.
"""

from __future__ import annotations

import argparse
import json
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

from oracle import build_dictionary as bd

REPO_ROOT = bd.REPO_ROOT
DEFAULT_DICTIONARY = bd.DEFAULT_OUT_DIR / bd.DICTIONARY_NAME
DEFAULT_NAMES = bd.DEFAULT_OUT_DIR / bd.NAMES_NAME
DEFAULT_HTML = REPO_ROOT / "harness" / "label" / "names.html"
BATCH_SIZE = 20
LANGS = ("es", "de")
STATUSES = ("pending", "done", "review")


# --------------------------------------------------------------------------------------
# Datos
# --------------------------------------------------------------------------------------


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def is_pending(entry: dict[str, Any]) -> bool:
    return entry.get("status", "pending") == "pending" or not str(entry.get("name", "")).strip()


def pending_ids(names: list[dict[str, Any]]) -> list[int]:
    return sorted(int(e["id"]) for e in names if is_pending(e))


def compress_ranges(ids: list[int]) -> str:
    """[1,2,3,7,9,10] -> '1-3, 7, 9-10'."""
    if not ids:
        return ""
    parts: list[str] = []
    start = prev = ids[0]
    for value in ids[1:]:
        if value == prev + 1:
            prev = value
            continue
        parts.append(f"{start}-{prev}" if start != prev else str(start))
        start = prev = value
    parts.append(f"{start}-{prev}" if start != prev else str(start))
    return ", ".join(parts)


def cmd_todo(names_path: Path) -> int:
    problems = bd.validate_names_file(names_path)
    if problems:
        for p in problems:
            print(f"error: {p}", file=sys.stderr)
        return 2
    names = load_json(names_path)
    todo = pending_ids(names)
    total = len(names)
    by_status: dict[str, int] = {}
    for e in names:
        by_status[e.get("status", "?")] = by_status.get(e.get("status", "?"), 0) + 1
    print(f"names-todo: {len(todo)} de {total} combinaciones pendientes de nombre ({names_path.relative_to(REPO_ROOT)})")
    print("estados: " + ", ".join(f"{k}={v}" for k, v in sorted(by_status.items())))
    print(f"ids pendientes: {compress_ranges(todo) or '(ninguno)'}")
    if todo:
        print(f"siguiente lote de {BATCH_SIZE}: {', '.join(str(i) for i in todo[:BATCH_SIZE])}")
        print("curar con: make names-html && open harness/label/names.html")
    return 0


# --------------------------------------------------------------------------------------
# HTML
# --------------------------------------------------------------------------------------


def embed_json(obj: Any) -> str:
    """JSON apto para incrustar dentro de <script>: escapa '</' y separadores de línea U+2028/9."""
    text = json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    return text.replace("</", "<\\/").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")


HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nombres de las combinaciones de Wada</title>
<style>
  :root { --bg:#f7f6f3; --card:#fff; --ink:#1d1d1b; --muted:#6b6b66; --line:#dcdad3; --accent:#1f5fa8; --warn:#b3261e; }
  * { box-sizing:border-box; }
  body { margin:0; font:15px/1.45 -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif; color:var(--ink); background:var(--bg); }
  header { position:sticky; top:0; z-index:5; background:var(--card); border-bottom:1px solid var(--line); padding:12px 20px; }
  header h1 { font-size:18px; margin:0 0 6px; }
  .help { font-size:13px; color:var(--muted); margin:0 0 10px; max-width:1100px; }
  .help strong { color:var(--ink); }
  .toolbar { display:flex; flex-wrap:wrap; gap:10px; align-items:center; }
  .toolbar button, .toolbar label.btn { font:inherit; padding:6px 12px; border:1px solid var(--line); border-radius:6px; background:#fafaf8; cursor:pointer; }
  .toolbar button.primary { background:var(--accent); color:#fff; border-color:var(--accent); }
  .toolbar button:disabled { opacity:.45; cursor:default; }
  .toolbar .spacer { flex:1; }
  .toolbar .progress { font-variant-numeric:tabular-nums; color:var(--muted); }
  .toolbar select { font:inherit; padding:5px 8px; }
  main { padding:16px 20px 60px; max-width:1400px; margin:0 auto; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:14px 16px 16px; margin:0 0 16px; display:grid; grid-template-columns: minmax(360px, 1.4fr) minmax(300px, 1fr); gap:16px; }
  @media (max-width: 860px) { .card { grid-template-columns: 1fr; } }
  .card.done { border-left:5px solid #2e7d32; }
  .card.review { border-left:5px solid #ef6c00; }
  .card.pending { border-left:5px solid #c7c5bd; }
  .card h2 { margin:0 0 8px; font-size:17px; display:flex; gap:10px; align-items:baseline; }
  .card h2 .meta { font-weight:normal; color:var(--muted); font-size:13px; }
  .swatches { display:flex; gap:8px; }
  .swatch { flex:1; min-width:0; }
  .swatch .chip { height:140px; border-radius:8px; border:1px solid rgba(0,0,0,.12); }
  .swatch .label { font-size:12px; margin-top:6px; line-height:1.3; }
  .swatch .label b { display:block; font-weight:600; }
  .swatch .label code { color:var(--muted); }
  .neighbors { font-size:12px; color:var(--muted); margin-top:10px; }
  .neighbors a { color:var(--accent); text-decoration:none; }
  .fields label { display:block; font-size:12px; color:var(--muted); margin:6px 0 2px; }
  .fields input[type=text], .fields textarea, .fields select { width:100%; font:inherit; padding:7px 9px; border:1px solid var(--line); border-radius:6px; background:#fff; }
  .fields textarea { min-height:56px; resize:vertical; }
  .fields .row { display:flex; gap:10px; }
  .fields .row > div { flex:1; }
  .foot { text-align:center; color:var(--muted); font-size:13px; margin-top:20px; }
  .toast { position:fixed; bottom:16px; left:50%; transform:translateX(-50%); background:#333; color:#fff; padding:8px 14px; border-radius:6px; font-size:13px; opacity:0; transition:opacity .2s; pointer-events:none; }
  .toast.show { opacity:1; }
</style>
</head>
<body>
<header>
  <h1>Nombres de las combinaciones de Wada <span class="meta" id="meta"></span></h1>
  <p class="help">
    El libro solo numera las láminas: ponerles nombre es obra tuya. <strong>Escribe los nombres en español o en alemán</strong>
    (elige el idioma en cada tarjeta); los nombres de color en inglés son solo referencia. Rellena el nombre, deja notas si quieres y pulsa
    <strong>Descargar names.es.json</strong>: sustituye <code>data/wada/names.es.json</code> del repo por el archivo descargado
    (<code>make dict-check</code> lo valida y <code>make names-todo</code> te dice qué falta). El borrador se guarda solo en este navegador
    (localStorage); <strong>Cargar</strong> retoma un <code>names.es.json</code> descargado antes.
  </p>
  <div class="toolbar">
    <button id="prev">&larr; Anterior</button>
    <select id="batch"></select>
    <button id="next">Siguiente &rarr;</button>
    <label class="btn"><input type="checkbox" id="onlyPending"> solo pendientes</label>
    <span class="spacer"></span>
    <span class="progress" id="progress"></span>
    <label class="btn">Cargar names.es.json <input type="file" id="load" accept="application/json,.json" hidden></label>
    <button id="reset">Descartar borrador</button>
    <button class="primary" id="download">Descargar names.es.json</button>
  </div>
</header>
<main id="main"></main>
<div class="toast" id="toast"></div>
<script>
// Datos incrustados por oracle.names (sin fetch): dictionary.json (recortado) y names.es.json.
const DICT = __DICTIONARY__;
const NAMES_ORIGINAL = __NAMES__;
const META = __META__;
const BATCH = META.batch_size;
const LANGS = META.langs;
const STATUSES = META.statuses;
const STORAGE_KEY = "colorsapp.names." + DICT.dict_version;

const colorsByIndex = new Map(DICT.colors.map(c => [c.index, c]));
const combosById = new Map(DICT.combinations.map(c => [c.id, c]));
const ids = DICT.combinations.map(c => c.id);

// Vecinos: combinaciones que comparten colores (ordenadas por número de colores compartidos).
const combosByColor = new Map();
for (const c of DICT.combinations) for (const k of c.colors) {
  if (!combosByColor.has(k)) combosByColor.set(k, []);
  combosByColor.get(k).push(c.id);
}
function neighbors(combo) {
  const shared = new Map();
  for (const k of combo.colors) for (const other of combosByColor.get(k)) {
    if (other !== combo.id) shared.set(other, (shared.get(other) || 0) + 1);
  }
  return [...shared.entries()].sort((a, b) => b[1] - a[1] || a[0] - b[0]).slice(0, 6);
}

// Estado: mapa id -> entrada {id, lang, name, notes, status}.
let state = new Map();
function seed(entries) {
  state = new Map();
  for (const e of entries) state.set(e.id, { id: e.id, lang: e.lang || "es", name: e.name || "", notes: e.notes || "", status: e.status || "pending" });
  for (const id of ids) if (!state.has(id)) state.set(id, { id, lang: "es", name: "", notes: "", status: "pending" });
}
function loadDraft() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) { seed(JSON.parse(raw)); return true; }
  } catch (e) { /* sin localStorage: se trabaja en memoria */ }
  return false;
}
function saveDraft() {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(exportEntries())); } catch (e) { /* ignorar */ }
}
function exportEntries() {
  // Claves en orden alfabético, como dump_json (sort_keys) del generador.
  return ids.map(id => { const e = state.get(id); return { id: e.id, lang: e.lang, name: e.name, notes: e.notes, status: e.status }; });
}
function isPending(e) { return e.status === "pending" || !e.name.trim(); }

// Lotes
const nBatches = Math.ceil(ids.length / BATCH);
let batch = 0;
const $ = id => document.getElementById(id);
function batchIds(b) { return ids.slice(b * BATCH, (b + 1) * BATCH); }
function batchLabel(b) {
  const bids = batchIds(b);
  const pend = bids.filter(id => isPending(state.get(id))).length;
  return `Lote ${b + 1} de ${nBatches} · Nº ${bids[0]}–${bids[bids.length - 1]} · ${pend} pendientes`;
}
function fillBatchSelect() {
  const sel = $("batch");
  sel.innerHTML = "";
  for (let b = 0; b < nBatches; b++) {
    const o = document.createElement("option");
    o.value = b; o.textContent = batchLabel(b);
    sel.appendChild(o);
  }
  sel.value = batch;
}
function updateProgress() {
  const named = ids.filter(id => !isPending(state.get(id))).length;
  $("progress").textContent = `${named} / ${ids.length} con nombre`;
  const opts = $("batch").options;
  for (let b = 0; b < nBatches; b++) opts[b].textContent = batchLabel(b);
  $("prev").disabled = batch === 0;
  $("next").disabled = batch === nBatches - 1;
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
function render() {
  const main = $("main");
  main.innerHTML = "";
  const only = $("onlyPending").checked;
  let shown = 0;
  for (const id of batchIds(batch)) {
    const e = state.get(id);
    if (only && !isPending(e)) continue;
    shown++;
    const combo = combosById.get(id);
    const card = el("article", { class: "card " + e.status, id: "combo-" + id });
    const left = el("div", {});
    left.append(el("h2", {}, `Nº ${pad3(id)}`, el("span", { class: "meta" }, `${combo.size} colores`)));
    const sw = el("div", { class: "swatches" });
    for (const k of combo.colors) {
      const c = colorsByIndex.get(k);
      sw.append(el("div", { class: "swatch" },
        el("div", { class: "chip", style: `background:${c.hex}`, title: `${c.name} ${c.hex}` }),
        el("div", { class: "label" }, el("b", {}, c.name), el("code", {}, `${c.hex} · #${k}`))));
    }
    left.append(sw);
    const nb = neighbors(combo);
    if (nb.length) {
      const p = el("div", { class: "neighbors" }, "Comparte colores con: ");
      nb.forEach(([other, n], i) => {
        const oe = state.get(other);
        const text = `Nº ${pad3(other)}` + (oe.name.trim() ? ` «${oe.name}»` : "") + ` (${n})`;
        p.append(el("a", { href: "#", onclick: ev => { ev.preventDefault(); goTo(other); } }, text));
        if (i < nb.length - 1) p.append(", ");
      });
      left.append(p);
    }
    const right = el("div", { class: "fields" });
    const name = el("input", { type: "text", value: e.name, placeholder: "Nombre propio (español o alemán)", autocomplete: "off",
      oninput: ev => { e.name = ev.target.value; if (e.name.trim() && e.status === "pending") { e.status = "done"; status.value = "done"; } card.className = "card " + e.status; touch(); } });
    const lang = el("select", { onchange: ev => { e.lang = ev.target.value; touch(); } });
    for (const l of LANGS) lang.append(el("option", { value: l }, l === "es" ? "es · español" : "de · Deutsch"));
    lang.value = LANGS.includes(e.lang) ? e.lang : "es";
    const status = el("select", { onchange: ev => { e.status = ev.target.value; card.className = "card " + e.status; touch(); } });
    for (const s of STATUSES) status.append(el("option", { value: s }, s));
    status.value = STATUSES.includes(e.status) ? e.status : "pending";
    const notes = el("textarea", { placeholder: "Notas (referencias, dudas, alternativas)", oninput: ev => { e.notes = ev.target.value; touch(); } });
    notes.value = e.notes;
    right.append(el("label", {}, "Nombre"), name,
      el("div", { class: "row" }, el("div", {}, el("label", {}, "Idioma"), lang), el("div", {}, el("label", {}, "Estado"), status)),
      el("label", {}, "Notas"), notes);
    card.append(left, right);
    main.append(card);
  }
  if (!shown) main.append(el("p", { class: "foot" }, "Nada pendiente en este lote."));
  main.append(el("p", { class: "foot" }, `dict_version ${DICT.dict_version} · ${META.generated_at} · ${ids.length} combinaciones · ${DICT.colors.length} colores`));
  updateProgress();
  location.hash = "lote=" + (batch + 1);
}
let touchTimer = null;
function touch() { updateProgress(); clearTimeout(touchTimer); touchTimer = setTimeout(saveDraft, 300); }
function goTo(id) {
  batch = Math.floor(ids.indexOf(id) / BATCH);
  $("batch").value = batch; $("onlyPending").checked = false; render();
  const node = $("combo-" + id); if (node) node.scrollIntoView({ behavior: "smooth", block: "center" });
}
function toast(msg) { const t = $("toast"); t.textContent = msg; t.classList.add("show"); setTimeout(() => t.classList.remove("show"), 2200); }

// Descarga como data: URL (sin servidor).
function download() {
  saveDraft();
  const text = JSON.stringify(exportEntries(), null, 2) + "\n";
  const a = document.createElement("a");
  a.href = "data:application/json;charset=utf-8," + encodeURIComponent(text);
  a.download = "names.es.json";
  document.body.append(a); a.click(); a.remove();
  toast("names.es.json descargado: cópialo a data/wada/names.es.json");
}
function loadFile(file) {
  const reader = new FileReader();
  reader.onload = () => {
    try {
      const data = JSON.parse(reader.result);
      if (!Array.isArray(data)) throw new Error("se esperaba una lista");
      seed(data); saveDraft(); fillBatchSelect(); render(); toast(`Cargadas ${data.length} entradas`);
    } catch (err) { toast("No se pudo leer el JSON: " + err.message); }
  };
  reader.readAsText(file);
}

$("prev").addEventListener("click", () => { batch = Math.max(0, batch - 1); $("batch").value = batch; render(); window.scrollTo(0, 0); });
$("next").addEventListener("click", () => { batch = Math.min(nBatches - 1, batch + 1); $("batch").value = batch; render(); window.scrollTo(0, 0); });
$("batch").addEventListener("change", ev => { batch = Number(ev.target.value); render(); });
$("onlyPending").addEventListener("change", render);
$("download").addEventListener("click", download);
$("load").addEventListener("change", ev => { if (ev.target.files[0]) loadFile(ev.target.files[0]); ev.target.value = ""; });
$("reset").addEventListener("click", () => {
  if (!confirm("¿Descartar el borrador de este navegador y volver al names.es.json incrustado?")) return;
  try { localStorage.removeItem(STORAGE_KEY); } catch (e) {}
  seed(NAMES_ORIGINAL); fillBatchSelect(); render(); toast("Borrador descartado");
});

const fromDraft = loadDraft();
if (!fromDraft) seed(NAMES_ORIGINAL);
const m = location.hash.match(/lote=(\d+)/);
if (m) batch = Math.min(nBatches - 1, Math.max(0, Number(m[1]) - 1));
else { const first = ids.findIndex(id => isPending(state.get(id))); batch = first < 0 ? 0 : Math.floor(first / BATCH); }
$("meta").textContent = `· dict_version ${DICT.dict_version} · lotes de ${BATCH}`;
fillBatchSelect();
render();
if (fromDraft) toast("Borrador restaurado de este navegador");
</script>
</body>
</html>
"""


def build_html(dictionary: dict[str, Any], names: list[dict[str, Any]], generated_at: str) -> str:
    """HTML autocontenido. Se incrusta solo lo que la página necesita del diccionario."""
    slim = {
        "dict_version": dictionary["dict_version"],
        "status": dictionary.get("status"),
        "colors": [{"index": c["index"], "name": c["name"], "hex": c["hex"]} for c in dictionary["colors"]],
        "combinations": [{"id": c["id"], "size": c["size"], "colors": c["colors"]} for c in dictionary["combinations"]],
    }
    meta = {
        "batch_size": BATCH_SIZE,
        "langs": list(LANGS),
        "statuses": list(STATUSES),
        "generated_at": generated_at,
        "names_file": bd.NAMES_NAME,
    }
    return (
        HTML_TEMPLATE.replace("__DICTIONARY__", embed_json(slim))
        .replace("__NAMES__", embed_json(names))
        .replace("__META__", embed_json(meta))
    )


class _WellFormedness(HTMLParser):
    """Comprueba el anidamiento de etiquetas no vacías (suficiente para nuestro HTML)."""

    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[tuple[str, int]] = []
        self.problems: list[str] = []
        self.doctype = False

    def handle_decl(self, decl: str) -> None:
        if decl.lower().startswith("doctype html"):
            self.doctype = True

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag not in self.VOID:
            self.stack.append((tag, self.getpos()[0]))

    def handle_startendtag(self, tag: str, attrs) -> None:
        pass

    def handle_endtag(self, tag: str) -> None:
        if tag in self.VOID:
            return
        if not self.stack:
            self.problems.append(f"línea {self.getpos()[0]}: </{tag}> sin apertura")
            return
        open_tag, line = self.stack.pop()
        if open_tag != tag:
            self.problems.append(f"línea {self.getpos()[0]}: </{tag}> cierra <{open_tag}> abierto en la línea {line}")


def check_html(text: str) -> list[str]:
    """Lista de problemas de forma (vacía = bien formado)."""
    parser = _WellFormedness()
    parser.feed(text)
    parser.close()
    problems = list(parser.problems)
    if not parser.doctype:
        problems.append("falta <!DOCTYPE html>")
    for open_tag, line in parser.stack:
        problems.append(f"<{open_tag}> abierto en la línea {line} sin cerrar")
    for needle in ("<title>", "</html>", "const DICT = {", "const NAMES_ORIGINAL = [", "Descargar names.es.json"):
        if needle not in text:
            problems.append(f"falta {needle!r}")
    if "fetch(" in text or "XMLHttpRequest" in text:
        problems.append("la página no debe hacer peticiones de red")
    return problems


def cmd_html(dictionary_path: Path, names_path: Path, out: Path) -> int:
    problems = bd.validate_names_file(names_path)
    if problems:
        for p in problems:
            print(f"error: {p}", file=sys.stderr)
        return 2
    dictionary = load_json(dictionary_path)
    names = load_json(names_path)
    import datetime as dt
    import os

    # Salida reproducible (el fichero está en una ruta protegida con hash): la fecha
    # solo se incrusta si se fija SOURCE_DATE_EPOCH; si no, se usa dict_version.
    sde = os.environ.get("SOURCE_DATE_EPOCH")
    generated_at = (dt.datetime.fromtimestamp(int(sde), dt.timezone.utc).date().isoformat()
                    if sde else f"dict {dictionary.get('dict_version', '?')}")
    html = build_html(dictionary, names, generated_at)
    issues = check_html(html)
    if issues:
        for issue in issues:
            print(f"error: HTML mal formado: {issue}", file=sys.stderr)
        return 1
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
    size = out.stat().st_size
    todo = len(pending_ids(names))
    print(
        f"names-html: {out.relative_to(REPO_ROOT) if out.is_relative_to(REPO_ROOT) else out} "
        f"({size} bytes, {len(names)} combinaciones en lotes de {BATCH_SIZE}, {todo} pendientes, "
        f"dict_version {dictionary['dict_version']}); ábrelo en el navegador (open {out.name})"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m oracle.names", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    todo = sub.add_parser("todo", help="cuántas combinaciones siguen pendientes y sus ids")
    todo.add_argument("--names", type=Path, default=DEFAULT_NAMES)
    html = sub.add_parser("html", help="genera la página de curación autocontenida")
    html.add_argument("--names", type=Path, default=DEFAULT_NAMES)
    html.add_argument("--dictionary", type=Path, default=DEFAULT_DICTIONARY)
    html.add_argument("--out", type=Path, default=DEFAULT_HTML)
    args = ap.parse_args(argv)
    if args.command == "todo":
        return cmd_todo(args.names)
    return cmd_html(args.dictionary, args.names, args.out)


if __name__ == "__main__":
    sys.exit(main())
