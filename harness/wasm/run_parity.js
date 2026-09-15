// run_parity.js — paridad nativo/WASM del motor (fase 5; `make parity`).
//
//   node harness/wasm/run_parity.js [--native build/tools/ce] [--wasm build-wasm/tools/ce.js]
//        [--fixtures harness/wasm/fixtures] [--tol 1e-9] [--top 3] [--out harness/out/parity.json]
//        [--no-determinism]
//
// Para cada fixture de `manifest.json` ejecuta `ce match <ppm> --json --top K [args]`
// con el binario nativo y con `node ce.js` (mismo cwd = raíz del repo, misma ruta
// relativa, así el campo "file" coincide) y compara:
//   - mismo número de swatches; |ΔL|, |Δa|, |Δb| y |Δweight| de cada swatch <= tol;
//   - mismo número de hits; para los top-3: mismos ids en el mismo orden y |Δscore| <= tol;
//   - mismo `ambiguous`; mismos engine/dict_version/dimensiones/opts efectivas.
// Además, desde que el motor lleva su propia libm (engine/Sources/CColorEngine/
// ce_libm.c, fase 5), exige por defecto **bit-exactitud**: la salida JSON de las dos
// plataformas debe ser byte a byte idéntica (Lab, weight, rgb, todos los hits con su
// score y el `hash` FNV-1a de los bits). `--no-bitexact` lo rebaja a informativo
// (para diagnosticar una plataforma nueva sin perder el contrato de 1e-9).
// Con determinismo activado cada lado se ejecuta dos veces y la salida debe ser
// byte a byte igual.
//
// Antes de nada comprueba el sha256 de cada PPM contra el manifest (fixtures
// corrompidas o regeneradas con otra versión => exit 2, no un falso "difiere").
//
// Imprime una tabla y un resumen con los máximos medidos; escribe el JSON de
// `--out`. Salida: 0 paridad ok, 1 alguna diferencia fuera de contrato (o no
// bit-exacta sin --no-bitexact), 2 uso, binarios o fixtures inválidos.
'use strict';
const { spawnSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..', '..');

function usage(msg) {
  if (msg) console.error('run_parity: ' + msg);
  console.error('uso: node harness/wasm/run_parity.js [--native <ce>] [--wasm <ce.js>] [--fixtures <dir>] ' +
    '[--tol 1e-9] [--top 3] [--out <parity.json>] [--no-determinism] [--no-bitexact]');
  process.exit(2);
}

function parseArgs(argv) {
  const o = {
    native: path.join(REPO_ROOT, 'build', 'tools', 'ce'),
    wasm: path.join(REPO_ROOT, 'build-wasm', 'tools', 'ce.js'),
    fixtures: path.join(__dirname, 'fixtures'),
    tol: 1e-9,
    top: 3,
    out: path.join(REPO_ROOT, 'harness', 'out', 'parity.json'),
    determinism: true,
    bitexact: true,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const v = argv[i + 1];
    if (a === '--native' && v) { o.native = path.resolve(v); i++; }
    else if (a === '--wasm' && v) { o.wasm = path.resolve(v); i++; }
    else if (a === '--fixtures' && v) { o.fixtures = path.resolve(v); i++; }
    else if (a === '--out' && v) { o.out = path.resolve(v); i++; }
    else if (a === '--tol' && v) { o.tol = Number(v); i++; }
    else if (a === '--top' && v) { o.top = Number(v); i++; }
    else if (a === '--no-determinism') o.determinism = false;
    else if (a === '--no-bitexact') o.bitexact = false;
    else if (a === '-h' || a === '--help') usage();
    else usage('argumento desconocido: ' + a);
  }
  if (!Number.isFinite(o.tol) || o.tol < 0) usage('--tol debe ser un número >= 0');
  if (!Number.isInteger(o.top) || o.top < 1 || o.top > 10) usage('--top debe estar en 1..10');
  return o;
}

const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
const absdiff = (a, b) => Math.abs(a - b);
const fmt = (x) => (x === 0 ? '0' : x.toExponential(1));
const deepEqual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// Ejecuta un CLI (nativo: [bin]; WASM: [node, ce.js]) con cwd = raíz del repo.
function runCli(cmd, args) {
  const r = spawnSync(cmd[0], cmd.slice(1).concat(args), { cwd: REPO_ROOT, encoding: 'utf8', maxBuffer: 1 << 26 });
  if (r.error) return { ok: false, status: -1, stdout: '', stderr: r.error.message, json: null };
  let json = null;
  if (r.status === 0) {
    try { json = JSON.parse(r.stdout); } catch (e) { return { ok: false, status: r.status, stdout: r.stdout, stderr: 'JSON inválido: ' + e.message, json: null }; }
  }
  return { ok: r.status === 0 && json !== null, status: r.status, stdout: r.stdout, stderr: r.stderr, json };
}

// Compara dos resultados de `ce match --json`; devuelve métricas y lista de fallos.
// `natText`/`wasText` son las salidas crudas (para la comprobación byte a byte).
function compare(nat, was, tol, topRequired, bitexact, natText, wasText) {
  const fails = [];
  const info = [];
  const m = {
    n_swatches: nat.swatches.length,
    n_hits: nat.hits.length,
    max_dL: 0, max_da: 0, max_db: 0, max_dw: 0, max_dscore_top: 0, max_dscore_rest: 0,
    lab_values: 0, lab_bit_identical: 0, rgb_diff: 0,
    top_native: nat.hits.map((h) => h.id), top_wasm: was.hits.map((h) => h.id),
    ambiguous_native: nat.ambiguous, ambiguous_wasm: was.ambiguous,
    hash_native: nat.hash, hash_wasm: was.hash, hash_equal: nat.hash === was.hash,
  };
  for (const key of ['engine', 'dict_version', 'file', 'width', 'height', 'reduced_width', 'reduced_height']) {
    if (nat[key] !== was[key]) fails.push(`${key}: ${nat[key]} != ${was[key]}`);
  }
  if (!deepEqual(nat.opts, was.opts)) fails.push('opts efectivas distintas');
  if (nat.swatches.length !== was.swatches.length) {
    fails.push(`n_swatches ${nat.swatches.length} != ${was.swatches.length}`);
  } else {
    nat.swatches.forEach((s, i) => {
      const t = was.swatches[i];
      const d = [absdiff(s.lab[0], t.lab[0]), absdiff(s.lab[1], t.lab[1]), absdiff(s.lab[2], t.lab[2])];
      m.max_dL = Math.max(m.max_dL, d[0]);
      m.max_da = Math.max(m.max_da, d[1]);
      m.max_db = Math.max(m.max_db, d[2]);
      const dw = absdiff(s.weight, t.weight);
      m.max_dw = Math.max(m.max_dw, dw);
      for (let k = 0; k < 3; k++) { m.lab_values++; if (s.lab[k] === t.lab[k]) m.lab_bit_identical++; }
      if (Math.max(...d) > tol) fails.push(`swatch ${i}: |ΔLab| = ${fmt(Math.max(...d))} > ${tol}`);
      if (dw > tol) fails.push(`swatch ${i}: |Δweight| = ${fmt(dw)} > ${tol}`);
      if (!deepEqual(s.rgb, t.rgb)) { m.rgb_diff++; info.push(`swatch ${i}: rgb ${s.rgb} vs ${t.rgb} (redondeo de Lab -> sRGB8)`); }
    });
  }
  if (nat.hits.length !== was.hits.length) {
    fails.push(`n_hits ${nat.hits.length} != ${was.hits.length}`);
  } else {
    nat.hits.forEach((h, i) => {
      const g = was.hits[i];
      const ds = absdiff(h.score, g.score);
      if (i < topRequired) {
        m.max_dscore_top = Math.max(m.max_dscore_top, ds);
        if (h.id !== g.id) fails.push(`hit ${i}: id ${h.id} != ${g.id} (top-${topRequired})`);
        else if (ds > tol) fails.push(`hit ${i} (id ${h.id}): |Δscore| = ${fmt(ds)} > ${tol}`);
      } else {
        m.max_dscore_rest = Math.max(m.max_dscore_rest, ds);
        if (h.id !== g.id) info.push(`hit ${i}: id ${h.id} != ${g.id} (fuera del top-${topRequired}, informativo)`);
        else if (ds > tol) info.push(`hit ${i}: |Δscore| = ${fmt(ds)} (fuera del top-${topRequired}, informativo)`);
      }
    });
  }
  if (nat.ambiguous !== was.ambiguous) fails.push(`ambiguous ${nat.ambiguous} != ${was.ambiguous}`);
  // Diagnóstico: CIEDE2000 no es Lipschitz en C' = 0 (ΔH' = 2·sqrt(C1'·C2')·sin(Δh'/2) y
  // el término de rotación crecen como sqrt(C'), y h' = atan2(b, a) es arbitrario cuando
  // a, b ~ 1e-14). Un swatch acromático cuyo a/b no sea 0 exacto en las dos plataformas
  // convierte 1e-14 de libm en ~1e-8 de score. Se señala para que el fallo no se
  // confunda con un error del match (ver engine/README.md, "Paridad nativo/WASM").
  m.achromatic_swatches = [];
  if (nat.swatches.length === was.swatches.length) {
    nat.swatches.forEach((s, i) => {
      const t = was.swatches[i];
      const cn = Math.hypot(s.lab[1], s.lab[2]);
      const cw = Math.hypot(t.lab[1], t.lab[2]);
      if (cn < ACHROMATIC_C && cw < ACHROMATIC_C && (cn !== cw || cn > 0)) {
        m.achromatic_swatches.push({ i, c_native: cn, c_wasm: cw });
      }
    });
  }
  m.fail_explained_by_achromatic = fails.some((f) => f.includes('Δscore')) && m.achromatic_swatches.length > 0;
  if (m.fail_explained_by_achromatic) {
    const list = m.achromatic_swatches.map((a) => `${a.i} (C' nativo ${fmt(a.c_native)}, wasm ${fmt(a.c_wasm)})`).join('; ');
    info.push(`diagnóstico: swatch acromático ${list}: ΔE00 ∝ sqrt(C') en C' -> 0, h' = atan2(b, a) mal condicionado; ` +
      '1e-14 en a/b => ~1e-8 en score (no es un error del match; ver engine/README.md "Paridad nativo/WASM")');
  }
  // Bit-exactitud (ce_libm.c): Lab, weight, rgb, todos los hits (id y score) y el
  // hash idénticos, y la salida JSON byte a byte igual. Con --no-bitexact solo informa.
  const bx = [];
  if (nat.swatches.length === was.swatches.length) {
    nat.swatches.forEach((s, i) => {
      const t = was.swatches[i];
      for (let k = 0; k < 3; k++) if (s.lab[k] !== t.lab[k]) bx.push(`swatch ${i}: lab[${k}] ${s.lab[k]} != ${t.lab[k]}`);
      if (s.weight !== t.weight) bx.push(`swatch ${i}: weight ${s.weight} != ${t.weight}`);
      if (!deepEqual(s.rgb, t.rgb)) bx.push(`swatch ${i}: rgb ${s.rgb} != ${t.rgb}`);
    });
  }
  if (nat.hits.length === was.hits.length) {
    nat.hits.forEach((h, i) => {
      const g = was.hits[i];
      if (h.id !== g.id) bx.push(`hit ${i}: id ${h.id} != ${g.id}`);
      else if (h.score !== g.score) bx.push(`hit ${i} (id ${h.id}): score ${h.score} != ${g.score}`);
    });
  }
  if (nat.hash !== was.hash) bx.push(`hash ${nat.hash} != ${was.hash}`);
  if (natText !== wasText && bx.length === 0) bx.push('la salida JSON difiere byte a byte (formato)');
  m.bitexact = bx.length === 0 && natText === wasText;
  m.bitexact_problems = bx;
  if (!m.bitexact) {
    const msg = 'no bit-exacto: ' + bx.slice(0, 3).join('; ') + (bx.length > 3 ? ` (+${bx.length - 3} más)` : '');
    if (bitexact) fails.push(msg); else info.push(msg + ' (informativo con --no-bitexact)');
  }
  return { m, fails, info };
}

// Swatch "acromático": C' = sqrt(a² + b²) por debajo de esto en ambas plataformas.
const ACHROMATIC_C = 1e-9;

function main() {
  const o = parseArgs(process.argv.slice(2));
  for (const [what, p] of [['binario nativo', o.native], ['CLI WASM', o.wasm]]) {
    if (!fs.existsSync(p)) usage(`no existe el ${what}: ${p} (make parity lo construye)`);
  }
  const manifestPath = path.join(o.fixtures, 'manifest.json');
  if (!fs.existsSync(manifestPath)) usage(`falta ${manifestPath} (make parity-fixtures)`);
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  if (!Array.isArray(manifest.entries) || manifest.entries.length === 0) usage('manifest sin entradas');

  // 1. Integridad de las fixtures.
  const badSha = [];
  for (const e of manifest.entries) {
    const p = path.join(o.fixtures, e.file);
    if (!fs.existsSync(p)) { badSha.push(e.file + ': no existe'); continue; }
    const h = sha256(fs.readFileSync(p));
    if (h !== e.sha256) badSha.push(`${e.file}: sha256 ${h.slice(0, 12)} != manifest ${e.sha256.slice(0, 12)}`);
  }
  if (badSha.length) {
    console.error('run_parity: fixtures no coinciden con manifest.json (regenera con make parity-fixtures):');
    for (const s of badSha) console.error('  ' + s);
    process.exit(2);
  }

  const nativeCmd = [o.native];
  const wasmCmd = [process.execPath, o.wasm];
  const topRequired = Math.min(3, o.top);
  const rows = [];
  let anyFail = false;
  const g = { max_dL: 0, max_da: 0, max_db: 0, max_dw: 0, max_dscore_top: 0, max_dscore_rest: 0,
    lab_values: 0, lab_bit_identical: 0, rgb_diff: 0, hash_equal: 0, swatches: 0, hits: 0, ambiguous_1: 0,
    order_equal: 0, ambiguous_equal: 0, fail_achromatic: 0, bitexact: 0 };

  console.log(`paridad nativo/WASM: ${manifest.entries.length} fixtures, tol ${o.tol}, --top ${o.top} (contrato: top-${topRequired}` +
    `; bit-exactitud ${o.bitexact ? 'exigida' : 'informativa'})`);
  console.log(`  nativo: ${path.relative(REPO_ROOT, o.native)}   wasm: ${process.execPath} ${path.relative(REPO_ROOT, o.wasm)}`);
  const header = ['fixture', 'sw', 'max|ΔLab|', 'max|Δw|', 'max|Δscore|', 'top-3 nativo', 'top-3 wasm', 'amb', 'hash=', 'bits=', 'estado'];
  const widths = [34, 2, 10, 10, 11, 14, 14, 3, 5, 5, 6];
  const line = (cells) => cells.map((c, i) => String(c).padEnd(widths[i])).join('  ');
  console.log(line(header));
  console.log(line(widths.map((w) => '-'.repeat(w))));

  for (const e of manifest.entries) {
    const rel = path.relative(REPO_ROOT, path.join(o.fixtures, e.file));
    const args = ['match', rel, '--json', '--top', String(o.top)].concat(e.args || []);
    const nat = runCli(nativeCmd, args);
    const was = runCli(wasmCmd, args);
    const row = { file: e.file, note: e.note, args: e.args || [], status: 'ok', fails: [], info: [], metrics: null,
      exit_native: nat.status, exit_wasm: was.status };
    if (!nat.ok || !was.ok) {
      row.status = 'FALLO';
      if (!nat.ok) row.fails.push(`nativo exit ${nat.status}: ${(nat.stderr || '').trim().split('\n')[0]}`);
      if (!was.ok) row.fails.push(`wasm exit ${was.status}: ${(was.stderr || '').trim().split('\n')[0]}`);
    } else {
      const { m, fails, info } = compare(nat.json, was.json, o.tol, topRequired, o.bitexact, nat.stdout, was.stdout);
      row.metrics = m;
      row.fails = fails;
      row.info = info;
      if (fails.length) row.status = 'FALLO';
      if (o.determinism) {
        const nat2 = runCli(nativeCmd, args);
        const was2 = runCli(wasmCmd, args);
        if (!nat2.ok || nat2.stdout !== nat.stdout) { row.fails.push('nativo: dos ejecuciones difieren'); row.status = 'FALLO'; }
        if (!was2.ok || was2.stdout !== was.stdout) { row.fails.push('wasm: dos ejecuciones difieren'); row.status = 'FALLO'; }
      }
      g.max_dL = Math.max(g.max_dL, m.max_dL);
      g.max_da = Math.max(g.max_da, m.max_da);
      g.max_db = Math.max(g.max_db, m.max_db);
      g.max_dw = Math.max(g.max_dw, m.max_dw);
      g.max_dscore_top = Math.max(g.max_dscore_top, m.max_dscore_top);
      g.max_dscore_rest = Math.max(g.max_dscore_rest, m.max_dscore_rest);
      g.lab_values += m.lab_values;
      g.lab_bit_identical += m.lab_bit_identical;
      g.rgb_diff += m.rgb_diff;
      g.hash_equal += m.hash_equal ? 1 : 0;
      g.swatches += m.n_swatches;
      g.hits += m.n_hits;
      g.ambiguous_1 += m.ambiguous_native === 1 ? 1 : 0;
      g.order_equal += deepEqual(m.top_native, m.top_wasm) ? 1 : 0;
      g.ambiguous_equal += m.ambiguous_native === m.ambiguous_wasm ? 1 : 0;
      g.fail_achromatic += m.fail_explained_by_achromatic ? 1 : 0;
      g.bitexact += m.bitexact ? 1 : 0;
    }
    if (row.status !== 'ok') anyFail = true;
    rows.push(row);
    const m = row.metrics;
    console.log(line([
      e.file, m ? m.n_swatches : '-',
      m ? fmt(Math.max(m.max_dL, m.max_da, m.max_db)) : '-',
      m ? fmt(m.max_dw) : '-',
      m ? fmt(m.max_dscore_top) : '-',
      m ? m.top_native.slice(0, topRequired).join(',') : '-',
      m ? m.top_wasm.slice(0, topRequired).join(',') : '-',
      m ? `${m.ambiguous_native}/${m.ambiguous_wasm}` : '-',
      m ? (m.hash_equal ? 'sí' : 'no') : '-',
      m ? (m.bitexact ? 'sí' : 'no') : '-',
      row.status,
    ]));
    for (const f of row.fails) console.log('      FALLO: ' + f);
    for (const i of row.info) console.log('      info: ' + i);
  }

  const nFail = rows.filter((r) => r.status !== 'ok').length;
  console.log('');
  console.log(`resumen: ${rows.length - nFail}/${rows.length} fixtures en paridad (tol ${o.tol}); ` +
    `${g.swatches} swatches, ${g.hits} hits, ambiguous=1 en ${g.ambiguous_1} fixtures`);
  console.log(`  mismo orden de ids (los ${o.top} hits) en ${g.order_equal}/${rows.length}; mismo ambiguous en ${g.ambiguous_equal}/${rows.length}` +
    (nFail ? `; fallos explicados por swatches acromáticos (C' < ${ACHROMATIC_C}): ${g.fail_achromatic}/${nFail}` : ''));
  console.log(`  max |ΔL| ${fmt(g.max_dL)}  max |Δa| ${fmt(g.max_da)}  max |Δb| ${fmt(g.max_db)}  max |Δweight| ${fmt(g.max_dw)}`);
  console.log(`  max |Δscore| top-${topRequired} ${fmt(g.max_dscore_top)}` +
    (o.top > topRequired ? `  (hits ${topRequired + 1}..${o.top}: ${fmt(g.max_dscore_rest)}, informativo)` : ''));
  console.log(`  Lab bit-idénticos ${g.lab_bit_identical}/${g.lab_values} valores; rgb distintos ${g.rgb_diff}; ` +
    `hash igual en ${g.hash_equal}/${rows.length} fixtures; salida JSON byte a byte idéntica (bit-exacta) en ` +
    `${g.bitexact}/${rows.length}${o.bitexact ? ' (exigido: ce_libm.c)' : ' (informativo)'}` +
    (o.determinism ? '; determinismo run-a-run: ok en ambos lados' : ''));

  const report = {
    schema: 2, kind: 'wasm_parity', generated_at: new Date().toISOString(),
    node: process.version, tol: o.tol, top: o.top, top_required: topRequired, bitexact_required: o.bitexact,
    native: path.relative(REPO_ROOT, o.native), wasm: path.relative(REPO_ROOT, o.wasm),
    fixtures: path.relative(REPO_ROOT, o.fixtures), dict_version: manifest.dict_version,
    n: rows.length, n_fail: nFail, ok: !anyFail, global: g, rows,
  };
  fs.mkdirSync(path.dirname(o.out), { recursive: true });
  fs.writeFileSync(o.out, JSON.stringify(report, null, 1) + '\n');
  console.log(`  informe: ${path.relative(REPO_ROOT, o.out)}`);
  process.exit(anyFail ? 1 : 0);
}

main();
