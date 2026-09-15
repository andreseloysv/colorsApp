// cli_match_check.js — valida el contrato JSON de `ce match | analyze | batch`
// de extremo a extremo (lo registra CMake como test `cli_match_contract` si
// hay node). Uso:
//   node cli_match_check.js <dir_fixtures> <cli...>
// donde <cli...> es el ejecutable `ce` nativo o `node ce.js` en WASM. Los
// fixtures (match_1.ppm, match_100.ppm, match_348.ppm, batch_list.txt) los
// escribe test_match.c. Sale con 0 si todo cuadra; imprime la primera
// discrepancia y sale con 1 si no.
'use strict';
const { spawnSync } = require('child_process');
const path = require('path');

const [outDir, ...cli] = process.argv.slice(2);
if (!outDir || cli.length === 0) {
  console.error('uso: node cli_match_check.js <dir_fixtures> <cli...>');
  process.exit(2);
}

let checks = 0;
function fail(msg) {
  console.error('FALLO: ' + msg);
  process.exit(1);
}
function assert(cond, msg) {
  checks++;
  if (!cond) fail(msg);
}
function run(args) {
  const r = spawnSync(cli[0], cli.slice(1).concat(args), { encoding: 'utf8', maxBuffer: 1 << 26 });
  if (r.error) fail('no puedo ejecutar el CLI: ' + r.error.message);
  return r;
}
const isInt = (v) => Number.isInteger(v);
const isNum = (v) => typeof v === 'number' && Number.isFinite(v);

const PALETTE_KEYS = ['k_init', 'max_iters', 'max_colors', 'max_side', 'center_sigma', 'merge_de', 'min_weight', 'skin_rule'];
const MATCH_KEYS = ['kL', 'kC', 'kH', 'coverage_lambda', 'ambiguous_gap', 'exposure_ev_max', 'exposure_penalty',
  'illuminant_search', 'illuminant_penalty', 'top'];
const RESULT_KEYS = ['engine', 'dict_version', 'file', 'width', 'height', 'reduced_width', 'reduced_height',
  'opts', 'swatches', 'hits', 'ambiguous', 'hash'];

// Comprueba un objeto de resultado completo (match o línea ok del batch).
function checkResult(obj, file, top, expectedTop1) {
  assert(JSON.stringify(Object.keys(obj)) === JSON.stringify(RESULT_KEYS),
    'claves del resultado: ' + Object.keys(obj).join(','));
  assert(obj.engine === '0.1.0', 'engine');
  assert(/^[0-9a-f]{12}$/.test(obj.dict_version), 'dict_version 12 hex');
  assert(obj.file === file, 'file: ' + obj.file + ' != ' + file);
  assert(obj.width === 120 && obj.height === 120, 'width/height');
  assert(obj.reduced_width === 120 && obj.reduced_height === 120, 'reduced_*');
  assert(JSON.stringify(Object.keys(obj.opts)) === '["palette","match"]', 'opts.{palette,match}');
  assert(JSON.stringify(Object.keys(obj.opts.palette)) === JSON.stringify(PALETTE_KEYS), 'opts.palette keys');
  assert(JSON.stringify(Object.keys(obj.opts.match)) === JSON.stringify(MATCH_KEYS), 'opts.match keys');
  assert(obj.opts.palette.center_sigma === 0, 'center_sigma efectiva 0');
  assert(obj.opts.match.kL === 1 && obj.opts.match.kC === 1 && obj.opts.match.kH === 1, 'kL/kC/kH por defecto');
  assert(obj.opts.match.coverage_lambda === 1 && obj.opts.match.ambiguous_gap === 1, 'lambda/gap por defecto');
  assert(obj.opts.match.exposure_ev_max === 1 && obj.opts.match.exposure_penalty === 2, 'exposición por defecto');
  assert(obj.opts.match.illuminant_search === 1 && obj.opts.match.illuminant_penalty === 2, 'iluminante por defecto');
  assert(obj.opts.match.top === top, 'opts.match.top');
  assert(Array.isArray(obj.swatches) && obj.swatches.length >= 1 && obj.swatches.length <= 8, 'swatches 1..8');
  let sum = 0;
  let prev = Infinity;
  for (const s of obj.swatches) {
    assert(JSON.stringify(Object.keys(s)) === '["rgb","hex","lab","weight"]', 'swatch keys');
    assert(s.rgb.length === 3 && s.rgb.every((v) => isInt(v) && v >= 0 && v <= 255), 'swatch rgb');
    assert(/^#[0-9a-f]{6}$/.test(s.hex), 'swatch hex');
    assert(s.hex === '#' + s.rgb.map((v) => v.toString(16).padStart(2, '0')).join(''), 'hex == rgb');
    assert(s.lab.length === 3 && s.lab.every(isNum), 'swatch lab');
    assert(isNum(s.weight) && s.weight > 0 && s.weight <= prev, 'pesos descendentes');
    prev = s.weight;
    sum += s.weight;
  }
  assert(Math.abs(sum - 1) < 1e-9, 'suma de pesos = 1');
  assert(Array.isArray(obj.hits) && obj.hits.length === top, 'hits.length == top');
  let last = null;
  for (const h of obj.hits) {
    assert(JSON.stringify(Object.keys(h)) === '["id","score","size","colors"]', 'hit keys');
    assert(isInt(h.id) && h.id >= 1 && h.id <= 348, 'hit id');
    assert(isNum(h.score) && h.score >= 0, 'hit score >= 0');
    assert(isInt(h.size) && h.size >= 2 && h.size <= 7, 'hit size');
    assert(Array.isArray(h.colors) && h.colors.length === h.size, 'hit colors.length == size');
    assert(h.colors.every((c, i) => isInt(c) && c >= 0 && c < 159 && (i === 0 || c > h.colors[i - 1])), 'colors ascendentes');
    if (last) assert(last.score < h.score || (last.score === h.score && last.id < h.id), 'hits ordenados');
    last = h;
  }
  assert(obj.hits[0].id === expectedTop1, 'top1 ' + obj.hits[0].id + ' != ' + expectedTop1);
  // Bloques exactos: 0 exacto en ~60 % de las combinaciones; el resto queda en
  // ~1e-14 por el redondeo de la media ponderada de Lloyd ((w*L)/w != L).
  assert(obj.hits[0].score < 1e-9, 'bloques exactos -> score ~0 (fue ' + obj.hits[0].score + ')');
  assert(obj.ambiguous === 0 || obj.ambiguous === 1, 'ambiguous 0|1');
  assert(/^[0-9a-f]{16}$/.test(obj.hash), 'hash 16 hex');
}

const f1 = path.join(outDir, 'match_1.ppm');
const common = ['--center-sigma', '0', '--json'];

// 1. match: JSON completo, exit 0, contrato.
let r = run(['match', f1, '--top', '3'].concat(common));
assert(r.status === 0, 'match exit ' + r.status + ' stderr: ' + r.stderr);
let obj;
try { obj = JSON.parse(r.stdout); } catch (e) { fail('match no es JSON: ' + e.message); }
checkResult(obj, f1, 3, 1);

// 2. analyze: alias exacto (misma salida byte a byte).
const r2 = run(['analyze', f1, '--top', '3'].concat(common));
assert(r2.status === 0 && r2.stdout === r.stdout, 'analyze != match');

// 3. Determinismo run-a-run y --top 10 / --top 1.
const r3 = run(['match', f1, '--top', '3'].concat(common));
assert(r3.stdout === r.stdout, 'dos ejecuciones difieren');
const r10 = run(['match', f1, '--top', '10'].concat(common));
assert(r10.status === 0, 'top 10 exit');
const o10 = JSON.parse(r10.stdout);
checkResult(o10, f1, 10, 1);
assert(JSON.stringify(o10.hits.slice(0, 3)) === JSON.stringify(obj.hits), 'prefijo top-3 de top-10');
assert(o10.hash !== obj.hash, 'el hash cubre los K hits impresos');
const r1 = run(['match', f1, '--top', '1'].concat(common));
const o1 = JSON.parse(r1.stdout);
checkResult(o1, f1, 1, 1);
assert(o1.ambiguous === 0, 'con un hit nunca ambiguo');
// --top por defecto = 3.
const rd = run(['match', f1].concat(common));
assert(JSON.parse(rd.stdout).hits.length === 3, 'top por defecto 3');
// Opciones de match propagadas a opts.match y al motor.
const rk = run(['match', f1, '--kL', '2', '--coverage-lambda', '0.5', '--ambiguous-gap', '2.5', '--kC', '1.5', '--kH', '0.75'].concat(common));
const ok = JSON.parse(rk.stdout);
assert(ok.opts.match.kL === 2 && ok.opts.match.kC === 1.5 && ok.opts.match.kH === 0.75, 'kL/kC/kH');
assert(ok.opts.match.coverage_lambda === 0.5 && ok.opts.match.ambiguous_gap === 2.5, 'lambda/gap');
assert(ok.hits[0].id === 1, 'top1 con kL=2');
// Hipótesis de adaptación: opciones propagadas; con la búsqueda apagada (match v0) el
// score del top-1 no puede ser menor que con ella encendida (mínimo sobre un superconjunto).
const rv0 = run(['match', f1, '--exposure-ev-max', '0', '--illuminant-search', '0', '--exposure-penalty', '3',
  '--illuminant-penalty', '4'].concat(common));
assert(rv0.status === 0, 'match v0 exit 0');
const v0 = JSON.parse(rv0.stdout);
assert(v0.opts.match.exposure_ev_max === 0 && v0.opts.match.illuminant_search === 0, 'búsqueda apagada');
assert(v0.opts.match.exposure_penalty === 3 && v0.opts.match.illuminant_penalty === 4, 'penalizaciones propagadas');
assert(v0.hits[0].id === 1 && v0.hits[0].score >= obj.hits[0].score, 'v0: mismo top-1 y score >= con hipótesis');
assert(run(['match', f1, '--illuminant-search', '2', '--json']).status === 1, '--illuminant-search 2 -> CE_ERR_OPTS (1)');
assert(run(['match', f1, '--exposure-ev-max', '5', '--json']).status === 1, '--exposure-ev-max 5 -> CE_ERR_OPTS (1)');
assert(run(['match', f1, '--exposure-penalty', '-1', '--json']).status === 1, '--exposure-penalty -1 -> CE_ERR_OPTS (1)');
// Sin --json: texto, exit 0.
const rt = run(['match', f1, '--center-sigma', '0']);
assert(rt.status === 0 && /ambiguous/.test(rt.stdout) && !/^\{/.test(rt.stdout), 'salida de texto');

// 4. Códigos de salida: uso (2), fichero (2), motor (1).
assert(run(['match']).status === 2, 'match sin fichero -> 2');
assert(run(['match', f1, '--top', '11', '--json']).status === 2, '--top 11 -> 2');
assert(run(['match', f1, '--top', '0', '--json']).status === 2, '--top 0 -> 2');
assert(run(['match', f1, '--kL', 'nan', '--json']).status === 2, '--kL nan -> 2');
assert(run(['match', f1, '--bogus', '--json']).status === 2, 'opcion desconocida -> 2');
assert(run(['match', path.join(outDir, 'does_not_exist.ppm'), '--json']).status === 2, 'fichero inexistente -> 2');
assert(run(['match', path.join(outDir, 'palette_truncated.ppm'), '--json']).status === 2, 'PPM truncado -> 2');
const rl = run(['match', f1, '--coverage-lambda', '-1', '--json']);
assert(rl.status === 1 && rl.stdout === '', 'lambda negativa -> error del motor (1) sin JSON');

// 5. batch: JSONL, una línea por entrada, error en la inexistente, exit 1.
const list = path.join(outDir, 'batch_list.txt');
const rb = run(['batch', list].concat(common));
assert(rb.status === 1, 'batch con un fichero ilegible -> exit 1 (fue ' + rb.status + ')');
const lines = rb.stdout.split('\n').filter((l) => l.length > 0);
assert(lines.length === 4, 'batch: 4 lineas JSONL (fueron ' + lines.length + ')');
const expected = [
  [path.join(outDir, 'match_1.ppm'), 1],
  [path.join(outDir, 'match_100.ppm'), 100],
  [path.join(outDir, 'does_not_exist.ppm'), null],
  [path.join(outDir, 'match_348.ppm'), 348],
];
lines.forEach((line, i) => {
  let o;
  try { o = JSON.parse(line); } catch (e) { fail('batch linea ' + i + ' no es JSON: ' + line); }
  assert(!/\n/.test(line), 'JSONL: una linea por imagen');
  const [file, top1] = expected[i];
  if (top1 === null) {
    assert(JSON.stringify(Object.keys(o)) === '["file","error"]', 'linea de error: {file, error}');
    assert(o.file === file && typeof o.error === 'string' && o.error.length > 0, 'error de ' + file);
  } else {
    checkResult(o, file, 3, top1);
  }
});
// batch con lista inexistente -> 2; batch de la lista con --top 1 mantiene el orden.
assert(run(['batch', path.join(outDir, 'no_list.txt'), '--json']).status === 2, 'lista inexistente -> 2');
const rb1 = run(['batch', list, '--top', '1'].concat(common));
assert(rb1.status === 1 && rb1.stdout.split('\n').filter((l) => l.length > 0).length === 4, 'batch --top 1');
// El hash de cada línea del batch coincide con el de `ce match` de la misma imagen.
const single = JSON.parse(run(['match', path.join(outDir, 'match_100.ppm'), '--top', '3'].concat(common)).stdout);
assert(JSON.parse(lines[1]).hash === single.hash, 'hash batch == hash match');

console.log('cli_match_contract: ' + checks + ' comprobaciones en verde');
