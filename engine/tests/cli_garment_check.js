// cli_garment_check.js — valida de extremo a extremo la paleta por prenda del
// CLI `ce` (lo registra CMake como test `cli_garment_contract` si hay node).
//   node cli_garment_check.js <dir_fixtures> <cli...>
// <cli...> es el ejecutable nativo o `node ce.js` (WASM). Los fixtures garment_*
// los escribe test_garment.c, con los hashes esperados de la API en
// garment_expected.json. Comprueba: `ce garments` (claves y orden del JSON,
// hash == ce_garment_hash de la API, 2 swatches del pantalón rosa, --match con
// result_hash == API y top-1), opciones de prenda propagadas y errores de uso,
// `ce batch --garments` (máscara "-", regiones por línea, error por línea),
// `ce garment-regions` == API byte a byte y --debug-dir con las capas de prenda
// coherentes con labels.pgm y debug.json. Sale con 0 si todo cuadra.
'use strict';
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const [outDir, ...cli] = process.argv.slice(2);
if (!outDir || cli.length === 0) {
  console.error('uso: node cli_garment_check.js <dir_fixtures> <cli...>');
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
const tmp = path.join(outDir, 'cli_garment_check');
fs.rmSync(tmp, { recursive: true, force: true });
fs.mkdirSync(tmp, { recursive: true });
const expected = JSON.parse(fs.readFileSync(f('garment_expected.json'), 'utf8'));

// 1. ce garments --json.
const keys = ['engine', 'dict_version', 'file', 'mask', 'regions', 'width', 'height', 'reduced_width', 'reduced_height',
  'n_regions', 'opts', 'garments', 'hash'];
const rg = run(['garments', f('garment_pants.ppm'), '--regions', f('garment_regions.pgm'), '--json']);
assert(rg.status === 0, 'garments exit 0: ' + rg.stderr);
const g = JSON.parse(rg.stdout);
assert(JSON.stringify(Object.keys(g)) === JSON.stringify(keys), 'garments: claves ' + Object.keys(g).join(','));
assert(g.hash === expected.pants_hash, 'garments: hash == API (' + g.hash + ' vs ' + expected.pants_hash + ')');
assert(g.n_regions === 2 && g.mask === null && g.regions === f('garment_regions.pgm'), 'garments: n_regions, mask, regions');
assert(g.opts.match === null && JSON.stringify(Object.keys(g.opts)) === '["palette","garment","match"]', 'garments: opts');
assert(JSON.stringify(Object.keys(g.opts.garment)) === JSON.stringify(['shade_kL', 'shade_merge_de', 'lit_low_pct',
  'lit_high_pct', 'secondary_min_share', 'max_colors_per_region']), 'garments: opts.garment');
// Los valores por defecto que publica el JSON son los DOCUMENTADOS en ce.h (el comentario de
// ce_garment_opts_default y el de ce_garment_opts). Si alguien recalibra el motor y no toca la
// cabecera, este test lo caza: el contrato que lee quien integra (SubjectKit, app, web) no puede
// mentir. Los valores viven también en oracle/oracle/garments.py (ENGINE_DEFAULT_GARMENT_OPTS).
const DEFAULT_GARMENT_OPTS = {
  shade_kL: 3.0, shade_merge_de: 6.5, lit_low_pct: 0.75, lit_high_pct: 0.95,
  secondary_min_share: 0.25, max_colors_per_region: 2,
};
const ceh = fs.readFileSync(path.join(__dirname, '..', 'Sources', 'CColorEngine', 'include', 'ce', 'ce.h'), 'utf8');
Object.entries(DEFAULT_GARMENT_OPTS).forEach(([k, v]) => {
  assert(g.opts.garment[k] === v, 'garments: opts.garment.' + k + ' por defecto ' + v + ' (es ' + g.opts.garment[k] + ')');
});
// ce.h documenta los mismos números dos veces (ce_garment_opts y ce_garment_opts_default), con coma
// decimal en la prosa y con punto en la lista corta.
[/shade_kL 3,\s*\n?\s*\*\s*shade_merge_de 6,5, lit_low_pct 0,75, lit_high_pct 0,95/,
  /shade_kL 3\.0, shade_merge_de 6\.5, lit_low_pct 0\.75, lit_high_pct 0\.95/].forEach((txt) => {
  assert(txt.test(ceh), 'ce.h documenta los valores por defecto reales: ' + txt);
});
assert(g.garments.length === 2, 'pantalón rosa: 2 swatches de prenda');
const regionsSeen = g.garments.map((s) => s.region).sort();
assert(JSON.stringify(regionsSeen) === '[1,2]', 'una prenda arriba y otra abajo');
let wsum = 0;
g.garments.forEach((s, i) => {
  assert(JSON.stringify(Object.keys(s)) === JSON.stringify(['region', 'region_name', 'region_share', 'n_merged_clusters',
    'rgb', 'hex', 'lab', 'weight']), 'swatch de prenda: claves');
  assert(s.region_name === ['none', 'upper', 'lower', 'whole'][s.region], 'region_name');
  assert(s.hex === '#' + s.rgb.map((v) => v.toString(16).padStart(2, '0')).join(''), 'hex = rgb');
  assert(i === 0 || g.garments[i - 1].weight >= s.weight, 'orden por peso');
  wsum += s.weight;
});
assert(Math.abs(wsum - 1) <= 1e-12, 'suma de pesos 1');
const lower = g.garments.find((s) => s.region === 2);
assert(lower.lab[0] > 75 && lower.n_merged_clusters >= 2, 'el pantalón agrupa varios clusters en su tono iluminado');
// Sin regiones: una sola región (0).
const rn = JSON.parse(run(['garments', f('garment_pants.ppm'), '--json']).stdout);
assert(rn.n_regions === 0 && rn.regions === null && rn.garments.every((s) => s.region === 0), 'sin --regions: región 0');
// Texto sin --json.
const rt = run(['garments', f('garment_pants.ppm'), '--regions', f('garment_regions.pgm')]);
assert(rt.status === 0 && /2 swatches de prenda/.test(rt.stdout) && /lower/.test(rt.stdout), 'salida de texto');

// 2. --match.
const rm = run(['garments', f('garment_pants.ppm'), '--regions', f('garment_regions.pgm'), '--match', '--top', '3', '--json']);
assert(rm.status === 0, 'garments --match exit 0');
const gm = JSON.parse(rm.stdout);
assert(JSON.stringify(Object.keys(gm)) === JSON.stringify(keys.concat(['swatches', 'hits', 'ambiguous', 'result_hash'])),
  'garments --match: claves ' + Object.keys(gm).join(','));
assert(gm.hash === g.hash, '--match no cambia los swatches de prenda');
assert(gm.result_hash === expected.pants_match_result_hash, 'result_hash == ce_analyze_garments de la API');
assert(gm.hits.length === 3 && gm.hits[0].id === expected.pants_top1, 'top-1 == API');
assert(gm.swatches.length === gm.garments.length && gm.swatches.every((s, i) => s.hex === gm.garments[i].hex &&
  s.weight === gm.garments[i].weight), 'swatches del match == swatches de prenda');
assert(gm.opts.match !== null && gm.opts.match.top === 3, 'opts.match');

// 3. Opciones de prenda y errores de uso.
const ro = JSON.parse(run(['garments', f('garment_stripes.ppm'), '--regions', f('garment_regions.pgm'), '--json']).stdout);
assert(ro.hash === expected.stripes_hash && ro.garments.filter((s) => s.region === 1).length === 2, 'rayas: 2 colores arriba');
const r1 = JSON.parse(run(['garments', f('garment_stripes.ppm'), '--regions', f('garment_regions.pgm'),
  '--max-colors-per-region', '1', '--json']).stdout);
assert(r1.opts.garment.max_colors_per_region === 1 && r1.garments.filter((s) => s.region === 1).length === 1,
  '--max-colors-per-region 1 propagado');
const rk = JSON.parse(run(['garments', f('garment_pants.ppm'), '--regions', f('garment_regions.pgm'), '--shade-kl', '1.5',
  '--shade-merge-de', '2', '--lit-low', '0.1', '--lit-high', '0.2', '--secondary-min-share', '0.5', '--json']).stdout);
assert(rk.opts.garment.shade_kL === 1.5 && rk.opts.garment.shade_merge_de === 2 && rk.opts.garment.lit_low_pct === 0.1 &&
  rk.opts.garment.lit_high_pct === 0.2 && rk.opts.garment.secondary_min_share === 0.5, 'opciones de prenda en opts');
assert(rk.hash !== g.hash, 'las opciones cambian el resultado');
assert(run(['garments', f('garment_pants.ppm'), '--lit-low', '0.9', '--lit-high', '0.1', '--json']).status === 1,
  'percentiles cruzados -> CE_ERR_OPTS (1)');
assert(run(['garments', f('garment_pants.ppm'), '--n-regions', '3', '--json']).status === 2, '--n-regions 3 -> uso (2)');
// Mapa con valor 3 sin --n-regions -> 2; con --n-regions 2 se ignora ese valor.
const reg3 = path.join(tmp, 'regions3.pgm');
const base = readPnm(f('garment_regions.pgm'));
const body3 = Buffer.from(base.data);
body3[0] = 3;
fs.writeFileSync(reg3, Buffer.concat([Buffer.from('P5\n' + base.w + ' ' + base.h + '\n255\n'), body3]));
const r3 = run(['garments', f('garment_pants.ppm'), '--regions', reg3, '--json']);
assert(r3.status === 2 && /fuera de 0..2/.test(r3.stderr), 'mapa con 3 sin --n-regions -> 2');
assert(run(['garments', f('garment_pants.ppm'), '--regions', reg3, '--n-regions', '2', '--json']).status === 0,
  'mapa con 3 y --n-regions 2 -> 0');
const small = path.join(tmp, 'small.pgm');
fs.writeFileSync(small, Buffer.concat([Buffer.from('P5\n10 10\n255\n'), Buffer.alloc(100, 1)]));
assert(run(['garments', f('garment_pants.ppm'), '--regions', small, '--json']).status === 2,
  'regiones de otras dimensiones -> 2');
assert(run(['garments', f('garment_pants.ppm'), '--regions', f('does_not_exist.pgm'), '--json']).status === 2,
  'regiones inexistentes -> 2');
assert(run(['match', f('garment_pants.ppm'), '--shade-kl', '2', '--json']).status === 2, 'match no admite opciones de prenda');
assert(run(['batch', f('garment_batch_list.txt'), '--regions', f('garment_regions.pgm')]).status === 2,
  'batch sin --garments no admite --regions');

// 4. batch --garments.
const rb = run(['batch', f('garment_batch_list.txt'), '--garments', '--json']);
assert(rb.status === 1, 'batch --garments con unas regiones inexistentes -> exit 1 (fue ' + rb.status + ')');
const lines = rb.stdout.split('\n').filter((l) => l.length > 0).map((l) => JSON.parse(l));
assert(lines.length === 4, 'batch --garments: 4 líneas');
assert(lines[0].file === f('garment_pants.ppm') && lines[0].mask === null && lines[0].regions === f('garment_regions.pgm'),
  'línea 1: máscara "-" y regiones');
assert(lines[0].hash === g.hash && lines[0].result_hash === expected.pants_match_result_hash, 'línea 1 == ce garments --match');
assert(lines[1].hash === expected.stripes_hash, 'línea 2 (tabuladores): rayas');
assert(lines[2].regions === null && lines[2].n_regions === 0 && lines[2].hash === rn.hash, 'línea 3 sin regiones');
assert(JSON.stringify(Object.keys(lines[3])) === '["file","mask","error"]' && /regiones/.test(lines[3].error),
  'línea 4: error de regiones');
const bad = path.join(tmp, 'bad_list.txt');
fs.writeFileSync(bad, f('garment_pants.ppm') + ' - ' + f('garment_regions.pgm') + ' extra\n');
const rbad = run(['batch', bad, '--garments', '--json']);
assert(rbad.status === 1 && /tres rutas/.test(JSON.parse(rbad.stdout.trim()).error), 'más de tres rutas -> error de línea');

// 5. ce garment-regions.
const grOut = path.join(tmp, 'garment_regions.pgm');
const rr = run(['garment-regions', '--size', '200x400', '--mask', f('garment_person.pgm'), '--pose', f('garment_pose.txt'),
  '--out', grOut]);
assert(rr.status === 0, 'garment-regions exit 0: ' + rr.stderr);
const rj = JSON.parse(rr.stdout);
assert(JSON.stringify(Object.keys(rj)) === '["pixels","upper","lower","mask_pixels"]', 'garment-regions: claves');
assert(rj.pixels === expected.garment_regions_pixels && rj.upper + rj.lower === rj.pixels && rj.mask_pixels === 80000,
  'garment-regions: recuentos');
assert(Buffer.compare(fs.readFileSync(grOut), fs.readFileSync(f('garment_expected_regions.pgm'))) === 0,
  'garment-regions == API byte a byte');
const noHips = path.join(tmp, 'nohips.pgm');
const rnh = run(['garment-regions', '--size', '200x400', '--mask', f('garment_person.pgm'), '--pose', f('mask_pose_nohips.txt'),
  '--out', noHips]);
assert(rnh.status === 1 && !fs.existsSync(noHips) && /CE_ERR_POSE/.test(rnh.stderr), 'sin caderas: exit 1 sin fichero');

// 6. --debug-dir con capas de prenda.
const dir = path.join(tmp, 'dbg');
const plain = run(['garments', f('garment_stripes.ppm'), '--regions', f('garment_regions.pgm'), '--match', '--json']);
const dbgRun = run(['garments', f('garment_stripes.ppm'), '--regions', f('garment_regions.pgm'), '--match', '--json',
  '--debug-dir', dir]);
assert(dbgRun.status === 0 && dbgRun.stdout === plain.stdout, '--debug-dir: exit 0 y stdout idéntico');
const dbg = JSON.parse(fs.readFileSync(path.join(dir, 'debug.json'), 'utf8'));
const out = JSON.parse(plain.stdout);
for (const name of ['reduced.ppm', 'weights.pgm', 'labels.pgm', 'labels.ppm', 'clusters.pgm', 'clusters.ppm', 'garments.pgm',
  'garments.ppm', 'regions.pgm', 'regions.ppm', 'debug.json']) {
  assert(fs.existsSync(path.join(dir, name)), 'capa ' + name);
}
assert(dbg.layers.garments === 'garments.pgm' && dbg.layers.regions === 'regions.pgm', 'debug.json: layers de prenda');
assert(dbg.n_regions === 2 && dbg.regions_file === f('garment_regions.pgm'), 'debug.json: n_regions y regions_file');
assert(dbg.garments.length === out.garments.length && dbg.opts.garment.shade_kL === out.opts.garment.shade_kL,
  'debug.json: garments y opts.garment');
assert(dbg.cluster_regions.length === dbg.palette_debug.n_clusters, 'debug.json: región por cluster');
const gl = readPnm(path.join(dir, 'garments.pgm'));
const rl = readPnm(path.join(dir, 'regions.pgm'));
const ll = readPnm(path.join(dir, 'labels.pgm'));
const cl = readPnm(path.join(dir, 'clusters.pgm'));
assert(gl.w === dbg.reduced_width && gl.h === dbg.reduced_height && rl.w === gl.w, 'dimensiones de las capas de prenda');
const px = new Array(out.garments.length).fill(0);
for (let i = 0; i < gl.data.length; i++) {
  const gi = gl.data[i];
  const row = Math.floor(i / gl.w);
  assert(rl.data[i] === (row * 2 < 160 ? 1 : 2), 'regions.pgm por fila');
  assert(ll.data[i] === gi || (ll.data[i] === 254 && gi === 255), 'labels.pgm == garments.pgm salvo DISCARDED');
  if (gi !== 255) {
    assert(gi < out.garments.length && out.garments[gi].region === rl.data[i], 'swatch de prenda en su región');
    assert(dbg.palette_debug.clusters[cl.data[i]].final_index === gi, 'cluster -> swatch de prenda');
    px[gi]++;
  }
}
dbg.garments.forEach((s, k) => assert(s.pixels === px[k] && px[k] > 0, 'pixels del swatch de prenda ' + k));
assert(dbg.explain.length === 3 && dbg.explain.every((e) => e.score_equals_match === true), 'explain con los swatches de prenda');

console.log('cli_garment_contract: ' + checks + ' comprobaciones en verde');
