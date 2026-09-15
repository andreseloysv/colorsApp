// layers_parity.js — paridad nativo/WASM de las capas de depuración y de las
// máscaras (lo ejecuta `make parity` después de harness/wasm/run_parity.js).
//
//   node engine/tests/layers_parity.js --native build/tools/ce --wasm build-wasm/tools/ce.js
//        --fixtures harness/wasm/fixtures --out build/parity-layers
//
// Para cada fixture del manifest ejecuta `ce match <ppm> --json --debug-dir DIR`
// (con los `args` del manifest) en nativo y con `node ce.js` y exige que TODOS
// los ficheros de DIR (reduced.ppm, weights.pgm, labels.pgm/.ppm, clusters.pgm/.ppm,
// swatch_<k>.pgm, debug.json con la explicación del top-K) sean byte a byte
// idénticos, y que stdout también lo sea. Además genera entradas sintéticas
// deterministas (máscara de persona, pose, muestra de piel) y compara
// `ce regions`, `ce skin`, `ce cut-head` y `ce match --mask --debug-dir` entre
// las dos plataformas. Salida: 0 todo idéntico, 1 alguna diferencia, 2 uso.
'use strict';
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}
const native = arg('--native');
const wasm = arg('--wasm');
const fixtures = arg('--fixtures');
const out = arg('--out');
if (!native || !wasm || !fixtures || !out) {
  console.error('uso: node layers_parity.js --native <ce> --wasm <ce.js> --fixtures <dir> --out <dir>');
  process.exit(2);
}
for (const p of [native, wasm, path.join(fixtures, 'manifest.json')]) {
  if (!fs.existsSync(p)) {
    console.error('no existe: ' + p);
    process.exit(2);
  }
}

let failures = 0;
let compared = 0;
function run(side, args) {
  const cmd = side === 'native' ? native : process.execPath;
  const full = side === 'native' ? args : [wasm].concat(args);
  const r = spawnSync(cmd, full, { encoding: 'buffer', maxBuffer: 1 << 26 });
  if (r.error) {
    console.error('no puedo ejecutar ' + side + ': ' + r.error.message);
    process.exit(2);
  }
  return r;
}
function sameDir(a, b, label) {
  const fa = fs.readdirSync(a).sort();
  const fb = fs.readdirSync(b).sort();
  if (JSON.stringify(fa) !== JSON.stringify(fb)) {
    console.error('DIFIERE ' + label + ': ficheros ' + fa.join(',') + ' vs ' + fb.join(','));
    failures++;
    return;
  }
  for (const name of fa) {
    compared++;
    if (Buffer.compare(fs.readFileSync(path.join(a, name)), fs.readFileSync(path.join(b, name))) !== 0) {
      console.error('DIFIERE ' + label + ': ' + name);
      failures++;
    }
  }
}
function both(label, argsFor) {
  const rn = run('native', argsFor('native'));
  const rw = run('wasm', argsFor('wasm'));
  compared++;
  if (rn.status !== rw.status || Buffer.compare(rn.stdout, rw.stdout) !== 0) {
    console.error('DIFIERE ' + label + ': exit ' + rn.status + '/' + rw.status + ' o stdout');
    failures++;
  }
  return [rn, rw];
}

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(path.join(out, 'native'), { recursive: true });
fs.mkdirSync(path.join(out, 'wasm'), { recursive: true });
const manifest = JSON.parse(fs.readFileSync(path.join(fixtures, 'manifest.json'), 'utf8'));
let nLayers = 0;
for (const e of manifest.entries) {
  const ppm = path.join(fixtures, e.file);
  const base = path.basename(e.file, '.ppm');
  const dir = (side) => path.join(out, side, base);
  const [rn] = both(e.file, (side) => ['match', ppm, '--json', '--top', '3', '--debug-dir', dir(side)].concat(e.args || []));
  if (rn.status !== 0) {
    console.error('ce match falló en ' + e.file + ': ' + rn.stderr.toString());
    failures++;
    continue;
  }
  sameDir(dir('native'), dir('wasm'), e.file);
  nLayers++;
}

// Entradas sintéticas de máscaras sobre la primera fixture no uniforme.
const entry = manifest.entries.find((e) => e.width >= 64 && e.height >= 64 && !/uniform/.test(e.file)) || manifest.entries[0];
const img = path.join(fixtures, entry.file);
const W = entry.width;
const H = entry.height;
const syn = path.join(out, 'synthetic');
fs.mkdirSync(syn, { recursive: true });
function pgm(name, fn) {
  const body = Buffer.alloc(W * H);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) body[y * W + x] = fn(x, y);
  const p = path.join(syn, name);
  fs.writeFileSync(p, Buffer.concat([Buffer.from('P5\n' + W + ' ' + H + '\n255\n'), body]));
  return p;
}
const person = pgm('person.pgm', (x, y) => ((x * 7 + y * 13) % 11 === 0 ? 0 : 128 + ((x + y) % 128)));
const sample = pgm('sample.pgm', (x, y) => (Math.abs(x - W / 2) < 8 && Math.abs(y - H / 2) < 8 ? 255 : 0));
const full = pgm('full.pgm', () => 255);
// Pose de frente escalada a la imagen, con coordenadas no diádicas (tercios).
const s = Math.min(W / 200, H / 400) * 1.0;
const J = [[100, 50], [100, 90], [140, 90], [60, 90], [152.3, 150.1], [47.7, 150.1], [158.6, 205.2], [41.4, 205.2],
  [124, 210], [76, 210], [126.3, 290.7], [73.7, 290.7], [128.5, 370.5], [71.5, 370.5], [100, 210]];
const poseTxt = J.map(([x, y], i) => (x * s + W / 3).toString() + ' ' + (y * s / 1.1).toString() + ' ' + (0.35 + 0.04 * i)).join('\n') + '\n';
const pose = path.join(syn, 'pose.txt');
fs.writeFileSync(pose, poseTxt);
const o = (side, name) => path.join(syn, side + '_' + name);
both('regions', (side) => ['regions', '--size', W + 'x' + H, '--mask', person, '--pose', pose, '--out', o(side, 'regions.pgm'), '--forearms', '1']);
both('skin', (side) => ['skin', '--image', img, '--sample', sample, '--mask', full, '--out', o(side, 'skin.pgm'), '--max-excluded', '1', '--max-mahalanobis', '3']);
both('cut-head', (side) => ['cut-head', '--mask', person, '--fraction', '0.3', '--out', o(side, 'cut.pgm')]);
both('match --mask --debug-dir', (side) => ['match', img, '--mask', person, '--json', '--debug-dir', o(side, 'dbg')]);
for (const name of ['regions.pgm', 'skin.pgm', 'cut.pgm']) {
  compared++;
  const a = o('native', name);
  const b = o('wasm', name);
  if (!fs.existsSync(a) || !fs.existsSync(b) || Buffer.compare(fs.readFileSync(a), fs.readFileSync(b)) !== 0) {
    console.error('DIFIERE sintético: ' + name);
    failures++;
  }
}
sameDir(o('native', 'dbg'), o('wasm', 'dbg'), 'match --mask --debug-dir');

if (failures > 0) {
  console.error('layers_parity: ' + failures + ' diferencias (' + compared + ' comparaciones)');
  process.exit(1);
}
console.log('layers_parity OK: ' + nLayers + ' fixtures con capas + regions/skin/cut-head/match --mask sintéticos, ' +
  compared + ' ficheros/salidas byte a byte idénticos nativo vs WASM');
