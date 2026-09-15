// cli_mask_check.js — valida de extremo a extremo los subcomandos de máscaras
// y las capas de depuración del CLI `ce` (lo registra CMake como test
// `cli_mask_contract` si hay node). Uso:
//   node cli_mask_check.js <dir_fixtures> <cli...>
// <cli...> es el ejecutable nativo o `node ce.js` (WASM). Los fixtures mask_*
// los escribe test_mask.c (incluidos los resultados esperados de la API en
// mask_expected.json / mask_expected_*.pgm) y match_1.ppm test_match.c.
// Comprueba: batch con máscara por línea (sin máscara, con máscara, rutas con
// espacios entre comillas y tabulador, máscara inexistente -> error en esa
// línea y el proceso continúa; la de la línea gana a --mask), `ce regions`,
// `ce skin` y `ce cut-head` contra la API, y `--debug-dir` en palette y match
// (ficheros, dimensiones, coherencia labels/swatch_k/weights, debug.json y
// explicación con score_equals_match). Sale con 0 si todo cuadra.
'use strict';
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const [outDir, ...cli] = process.argv.slice(2);
if (!outDir || cli.length === 0) {
  console.error('uso: node cli_mask_check.js <dir_fixtures> <cli...>');
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
function readPnm(file) {
  const buf = fs.readFileSync(file);
  const header = buf.slice(0, 64).toString('latin1');
  const m = /^P([56])\n(\d+) (\d+)\n255\n/.exec(header);
  if (!m) fail('cabecera PNM inesperada en ' + file);
  const channels = m[1] === '6' ? 3 : 1;
  const w = Number(m[2]);
  const h = Number(m[3]);
  const data = buf.slice(m[0].length);
  assert(data.length === w * h * channels, 'tamaño del cuerpo de ' + file);
  return { w, h, channels, data };
}
const f = (name) => path.join(outDir, name);
const tmp = path.join(outDir, 'cli_mask_check');
fs.rmSync(tmp, { recursive: true, force: true });
fs.mkdirSync(tmp, { recursive: true });
const expected = JSON.parse(fs.readFileSync(f('mask_expected.json'), 'utf8'));

// 1. batch con máscaras por línea.
const rb = run(['batch', f('mask_batch_list.txt'), '--center-sigma', '0', '--json']);
assert(rb.status === 1, 'batch con una máscara inexistente -> exit 1 (fue ' + rb.status + ')');
const lines = rb.stdout.split('\n').filter((l) => l.length > 0).map((l) => JSON.parse(l));
assert(lines.length === 4, 'batch: 4 líneas (fueron ' + lines.length + ')');
assert(lines[0].file === f('mask_person.ppm') && lines[0].mask === null && typeof lines[0].hash === 'string', 'línea sin máscara');
assert(lines[1].file === f('mask_person.ppm') && lines[1].mask === f('mask_clothes.pgm') && typeof lines[1].hash === 'string', 'línea con máscara');
assert(lines[2].file === f('mask person copy.ppm') && lines[2].mask === f('mask clothes copy.pgm'), 'rutas con espacios entre comillas');
assert(lines[2].hash === lines[1].hash, 'misma imagen y máscara -> mismo hash');
assert(lines[0].hash !== lines[1].hash, 'la máscara cambia el resultado');
assert(JSON.stringify(Object.keys(lines[3])) === '["file","mask","error"]', 'línea de error {file, mask, error}');
assert(lines[3].mask === f('does_not_exist_mask.pgm') && /mascara/.test(lines[3].error), 'error de la máscara inexistente');
// El hash de la línea con máscara coincide con `ce match --mask`.
const single = JSON.parse(run(['match', f('mask_person.ppm'), '--mask', f('mask_clothes.pgm'), '--center-sigma', '0', '--json']).stdout);
assert(single.hash === lines[1].hash, 'hash batch con máscara == ce match --mask');
// --mask global: se aplica a las líneas sin máscara; la de la línea gana.
const listGlobal = path.join(tmp, 'list_global.txt');
fs.writeFileSync(listGlobal, f('mask_person.ppm') + '\n' + f('mask_person.ppm') + '\t' + f('mask_person.pgm') + '\n');
const rg = run(['batch', listGlobal, '--mask', f('mask_clothes.pgm'), '--center-sigma', '0', '--json']);
assert(rg.status === 0, 'batch con --mask global -> exit 0');
const lg = rg.stdout.trim().split('\n').map((l) => JSON.parse(l));
assert(lg[0].mask === f('mask_clothes.pgm') && lg[0].hash === lines[1].hash, '--mask global en la línea sin máscara');
assert(lg[1].mask === f('mask_person.pgm') && lg[1].hash !== lines[1].hash, 'la máscara de la línea gana a --mask');
// Entradas mal formadas: error en esa línea, el proceso sigue.
const listBad = path.join(tmp, 'list_bad.txt');
fs.writeFileSync(listBad, '"' + f('mask_person.ppm') + '\n' + f('mask_person.ppm') + ' a b\n' + f('mask_person.ppm') + '\n');
const rbad = run(['batch', listBad, '--center-sigma', '0', '--json']);
const lbad = rbad.stdout.trim().split('\n').map((l) => JSON.parse(l));
assert(rbad.status === 1 && lbad.length === 3, 'batch con entradas mal formadas: 3 líneas, exit 1');
assert(/comillas/.test(lbad[0].error) && /dos rutas/.test(lbad[1].error) && typeof lbad[2].hash === 'string', 'errores de sintaxis por línea');
assert(run(['batch', f('mask_batch_list.txt'), '--debug-dir', tmp]).status === 2, 'batch no admite --debug-dir');

// 2. ce regions.
const regOut = path.join(tmp, 'regions.pgm');
const rr = run(['regions', '--size', '200x400', '--mask', f('mask_person.pgm'), '--pose', f('mask_pose.txt'), '--out', regOut]);
assert(rr.status === 0, 'regions exit 0: ' + rr.stderr);
const rj = JSON.parse(rr.stdout);
assert(JSON.stringify(Object.keys(rj)) === '["pixels","mask_pixels"]', 'regions: claves');
assert(rj.pixels === expected.regions_pixels, 'regions: píxeles == API (' + rj.pixels + ' vs ' + expected.regions_pixels + ')');
assert(Buffer.compare(fs.readFileSync(regOut), fs.readFileSync(f('mask_expected_regions.pgm'))) === 0, 'regions: máscara == API byte a byte');
const noHips = path.join(tmp, 'regions_nohips.pgm');
const rn = run(['regions', '--size', '200x400', '--mask', f('mask_person.pgm'), '--pose', f('mask_pose_nohips.txt'), '--out', noHips]);
assert(rn.status === 1 && !fs.existsSync(noHips) && /CE_ERR_POSE/.test(rn.stderr), 'regions sin caderas: exit 1, sin fichero');
assert(run(['regions', '--size', '100x400', '--mask', f('mask_person.pgm'), '--pose', f('mask_pose.txt'), '--out', regOut]).status === 2, 'regions: --size distinto -> 2');
assert(run(['regions', '--size', '200x400', '--mask', f('mask_person.pgm'), '--pose', f('mask_batch_list.txt'), '--out', regOut]).status === 2, 'regions: pose mal formada -> 2');
assert(run(['regions', '--size', '200x400', '--mask', f('mask_person.pgm'), '--pose', f('mask_pose.txt'), '--out', regOut, '--legs', '2']).status === 2, 'regions: --legs 2 -> 2');
const rf = run(['regions', '--size', '200x400', '--mask', f('mask_person.pgm'), '--pose', f('mask_pose.txt'), '--out', regOut, '--forearms', '1', '--limb-width', '0.6']);
assert(rf.status === 0 && JSON.parse(rf.stdout).pixels > rj.pixels, 'regions: opciones propagadas');
assert(run(['regions', '--size', '200x400', '--mask', f('mask_person.pgm'), '--pose', f('mask_pose.txt'), '--out', regOut, '--torso-margin', '1.5']).status === 1, 'regions: opción fuera de rango -> CE_ERR_ARG (1)');

// 3. ce skin.
const skinOut = path.join(tmp, 'skin.pgm');
const rs = run(['skin', '--image', f('mask_person.ppm'), '--sample', f('mask_face.pgm'), '--mask', f('mask_clothes.pgm'), '--out', skinOut]);
assert(rs.status === 0, 'skin exit 0: ' + rs.stderr);
const sj = JSON.parse(rs.stdout);
assert(JSON.stringify(Object.keys(sj).slice(0, 3)) === '["excluded","guard","mask_pixels"]', 'skin: claves del contrato primero');
assert(sj.excluded === expected.skin_excluded && sj.guard === 0 && sj.mask_pixels === expected.skin_mask_pixels, 'skin == API');
assert(sj.candidates === sj.excluded && sj.model.n === 3600 && sj.model.cov.length === 9, 'skin: candidatos y modelo');
assert(Buffer.compare(fs.readFileSync(skinOut), fs.readFileSync(f('mask_expected_skin.pgm'))) === 0, 'skin: máscara == API byte a byte');
// Salvaguarda: con max-excluded 0.1 (4800/20800 = 23 % > 10 %) salta y la máscara sale intacta.
const rgd = run(['skin', '--image', f('mask_person.ppm'), '--sample', f('mask_face.pgm'), '--mask', f('mask_clothes.pgm'), '--out', skinOut, '--max-excluded', '0.1']);
const gj = JSON.parse(rgd.stdout);
assert(rgd.status === 0 && gj.guard === 1 && gj.excluded === 0 && gj.candidates === 4800, 'skin: salvaguarda');
assert(Buffer.compare(fs.readFileSync(skinOut), fs.readFileSync(f('mask_clothes.pgm'))) === 0, 'skin: salvaguarda deja la máscara intacta');
// Muestra vacía (la máscara de ropa no cubre la cara pero sí tiene > 50 px: usar una muestra sin píxeles).
const emptySample = path.join(tmp, 'empty.pgm');
fs.writeFileSync(emptySample, Buffer.concat([Buffer.from('P5\n200 400\n255\n'), Buffer.alloc(200 * 400)]));
const skinBad = path.join(tmp, 'skin_bad.pgm');
const re = run(['skin', '--image', f('mask_person.ppm'), '--sample', emptySample, '--mask', f('mask_clothes.pgm'), '--out', skinBad]);
assert(re.status === 1 && /CE_ERR_SKIN_SAMPLES/.test(re.stderr) && !fs.existsSync(skinBad), 'skin sin muestras: exit 1 sin fichero');
assert(run(['skin', '--image', f('mask_person.ppm'), '--sample', f('mask_face.pgm'), '--out', skinOut]).status === 2, 'skin sin --mask -> 2');

// 4. ce cut-head.
const cutOut = path.join(tmp, 'cut.pgm');
const rc = run(['cut-head', '--mask', f('mask_person.pgm'), '--fraction', '0.25', '--out', cutOut]);
assert(rc.status === 0, 'cut-head exit 0');
const cut = readPnm(cutOut);
const person = readPnm(f('mask_person.pgm'));
// bbox filas 20..299 (H = 280) -> 70 filas fuera (20..89).
let rowsZero = true;
for (let y = 0; y < 90; y++) for (let x = 0; x < 200; x++) if (cut.data[y * 200 + x] !== 0) rowsZero = false;
let kept = 0;
for (let i = 0; i < cut.data.length; i++) if (cut.data[i]) kept++;
assert(rowsZero && kept === JSON.parse(rc.stdout).pixels, 'cut-head: franja superior y recuento');
let same = true;
for (let i = 90 * 200; i < cut.data.length; i++) if (cut.data[i] !== person.data[i]) same = false;
assert(same, 'cut-head: resto intacto');
assert(run(['cut-head', '--mask', f('mask_person.pgm'), '--fraction', '0.9', '--out', cutOut]).status === 1, 'cut-head fraction 0.9 -> 1');

// 5. --debug-dir en match y palette.
function checkDebugDir(dir, withMask, withMatch, stdoutPlain, stdoutDebug) {
  assert(stdoutPlain === stdoutDebug, 'stdout idéntico con y sin --debug-dir');
  const dbg = JSON.parse(fs.readFileSync(path.join(dir, 'debug.json'), 'utf8'));
  const keys = ['engine', 'dict_version', 'file', 'mask', 'width', 'height', 'reduced_width', 'reduced_height', 'layers',
    'label_values', 'palette_debug', 'swatches', 'label_counts', 'opts', 'hits', 'ambiguous', 'explain'];
  assert(JSON.stringify(Object.keys(dbg)) === JSON.stringify(keys), 'debug.json: claves ' + Object.keys(dbg).join(','));
  const rw = dbg.reduced_width;
  const rh = dbg.reduced_height;
  const reduced = readPnm(path.join(dir, 'reduced.ppm'));
  const weights = readPnm(path.join(dir, 'weights.pgm'));
  const labels = readPnm(path.join(dir, 'labels.pgm'));
  const labelsColor = readPnm(path.join(dir, 'labels.ppm'));
  const clusters = readPnm(path.join(dir, 'clusters.pgm'));
  for (const im of [reduced, weights, labels, labelsColor, clusters]) assert(im.w === rw && im.h === rh, 'dimensiones de las capas');
  assert(reduced.channels === 3 && labelsColor.channels === 3 && weights.channels === 1, 'canales');
  const n = dbg.swatches.length;
  assert(dbg.palette_debug.n_swatches === n && dbg.layers.swatches.length === n, 'n_swatches');
  const counts = new Array(n).fill(0);
  let none = 0;
  let discarded = 0;
  let wmax = 0;
  for (let i = 0; i < rw * rh; i++) {
    const l = labels.data[i];
    wmax = Math.max(wmax, weights.data[i]);
    if (l === 255) { none++; assert(weights.data[i] === 0, 'NONE con peso 0'); continue; }
    if (l === 254) { discarded++; assert(labelsColor.data[i * 3] === 128, 'DISCARDED en gris 128'); continue; }
    assert(l < n, 'etiqueta < n');
    counts[l]++;
    const sw = dbg.swatches[l];
    assert(labelsColor.data[i * 3] === sw.rgb[0] && labelsColor.data[i * 3 + 1] === sw.rgb[1] && labelsColor.data[i * 3 + 2] === sw.rgb[2], 'labels.ppm = color del swatch');
    const c = clusters.data[i];
    assert(c < dbg.palette_debug.n_clusters && dbg.palette_debug.clusters[c].final_index === l, 'cluster -> swatch');
  }
  assert(wmax === 255, 'weights escalado al máximo');
  assert(none === dbg.label_counts.none && discarded === dbg.label_counts.discarded, 'label_counts');
  for (let k = 0; k < n; k++) {
    const plane = readPnm(path.join(dir, 'swatch_' + k + '.pgm'));
    let on = 0;
    for (let i = 0; i < rw * rh; i++) {
      assert(plane.data[i] === (labels.data[i] === k ? 255 : 0), 'swatch_' + k + '.pgm == (labels == k)');
      if (plane.data[i]) on++;
    }
    assert(on === counts[k] && dbg.swatches[k].pixels === on, 'pixels del swatch ' + k);
  }
  for (const cd of dbg.palette_debug.clusters) {
    assert(['kept', 'merged', 'discarded', 'truncated'][cd.fate] === cd.fate_name, 'fate_name');
    assert((cd.fate <= 1) === (cd.final_index !== null), 'final_index null <=> descartado/recortado');
  }
  assert(fs.existsSync(path.join(dir, 'mask.pgm')) === withMask && (dbg.layers.mask !== null) === withMask, 'mask.pgm solo con --mask');
  if (withMask) {
    const mk = readPnm(path.join(dir, 'mask.pgm'));
    assert(mk.w === rw && mk.h === rh, 'mask.pgm reducida');
  }
  if (withMatch) {
    assert(Array.isArray(dbg.explain) && dbg.explain.length === dbg.hits.length && dbg.hits.length === 3, 'explain del top-3');
    const plain = JSON.parse(stdoutPlain);
    dbg.explain.forEach((e, i) => {
      assert(e.id === plain.hits[i].id && e.score === plain.hits[i].score && e.score_equals_match === true, 'explain: score == match');
      assert(Math.abs(e.fit_term + e.coverage_term + e.hypothesis_penalty - e.score) <= 1e-12, 'explain: suma de términos');
      assert(e.per_swatch.length === n && e.per_color.length >= 2, 'explain: por swatch y por color');
    });
  } else {
    assert(dbg.explain === null && dbg.hits === null && dbg.opts.match === null, 'palette: sin match');
  }
  return dbg;
}
const dirMatch = path.join(tmp, 'dbg_match');
const mPlain = run(['match', f('mask_person.ppm'), '--mask', f('mask_clothes.pgm'), '--json']);
const mDebug = run(['match', f('mask_person.ppm'), '--mask', f('mask_clothes.pgm'), '--json', '--debug-dir', dirMatch]);
assert(mPlain.status === 0 && mDebug.status === 0, 'match --debug-dir exit 0: ' + mDebug.stderr);
const dm = checkDebugDir(dirMatch, true, true, mPlain.stdout, mDebug.stdout);
assert(dm.palette_debug.zero_weight_fraction > 0.5, 'la máscara anula la mayoría de la reducida');
const dirPalette = path.join(tmp, 'dbg_palette');
const pPlain = run(['palette', f('match_1.ppm'), '--center-sigma', '0', '--json']);
const pDebug = run(['palette', f('match_1.ppm'), '--center-sigma', '0', '--json', '--debug-dir', dirPalette]);
assert(pDebug.status === 0, 'palette --debug-dir exit 0');
const dp = checkDebugDir(dirPalette, false, false, pPlain.stdout, pDebug.stdout);
assert(dp.palette_debug.center_sigma_px === 0 && dp.palette_debug.zero_weight_fraction === 0, 'palette uniforme sin máscara');
// analyze es alias: mismas capas byte a byte que match.
const dirAnalyze = path.join(tmp, 'dbg_analyze');
assert(run(['analyze', f('mask_person.ppm'), '--mask', f('mask_clothes.pgm'), '--json', '--debug-dir', dirAnalyze]).status === 0, 'analyze --debug-dir');
for (const name of fs.readdirSync(dirMatch)) {
  if (name === 'debug.json') continue;
  assert(Buffer.compare(fs.readFileSync(path.join(dirMatch, name)), fs.readFileSync(path.join(dirAnalyze, name))) === 0, 'analyze == match: ' + name);
}
// --debug-dir sobre un fichero (no directorio) -> 2 sin stdout.
const notDir = path.join(tmp, 'not_a_dir');
fs.writeFileSync(notDir, 'x');
const rnd = run(['match', f('match_1.ppm'), '--json', '--debug-dir', notDir]);
assert(rnd.status === 2 && rnd.stdout === '', '--debug-dir inválido -> 2 sin stdout');

console.log('cli_mask_contract: ' + checks + ' comprobaciones en verde');
