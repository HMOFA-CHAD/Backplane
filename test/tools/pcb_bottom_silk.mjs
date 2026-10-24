import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const lib = (await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const array = r => { const a = []; for (; r.$ === 'Con'; r = r.tail) a.push(r.head); return a; };
const prims = s => array(lib.text(s)).map(x => x.prim);
const close = (a, b) => {
  if (typeof a === 'number') assert.ok(Math.abs(a - b) < 0.0001, `${a} != ${b}`);
  else if (a && typeof a === 'object') {
    assert.deepEqual(Object.keys(a), Object.keys(b));
    for (const k of Object.keys(a)) close(a[k], b[k]);
  } else assert.equal(a, b);
};
const effects = mirror => `(effects (font (size 1.5 1.2) (thickness 0.2)) (justify left top${mirror ? ' mirror' : ''}))`;
const boardText = (angle, side, mirror) => `(kicad_pcb (gr_text "R37" (at 13 18 ${angle}) (layer "${side}.SilkS") ${effects(mirror)}))`;
const footprintText = (angle, side, mirror, unlocked, property = true, modern = false) =>
  `(kicad_pcb (footprint Test (layer "${side}.Cu") ${modern ? '(transform (translate 10 20) (rotate 90) (scale 1 1))' : '(at 10 20 90)'}
   (${property ? 'property "Reference"' : 'fp_text user'} "R37" (at 2 3 ${angle}${unlocked === 'legacy' ? ' unlocked' : ''}) ${unlocked === 'legacy' ? '' : unlocked} (layer "${side}.SilkS") ${effects(mirror)})))`;

// KiCad serializes footprint text angles in board coordinates. Disabling
// keep-upright must produce the same strokes as independent board text,
// including asymmetric anchors, a rotated/offset footprint and mirror flags.
for (const side of ['F', 'B']) for (const mirror of [false, true]) {
  for (const angle of [-90, 120, 180, 270]) for (const property of [false, true]) {
    for (const modern of [false, true]) {
      close(prims(footprintText(angle, side, mirror, '(unlocked yes)', property, modern)), prims(boardText(angle, side, mirror)));
    }
  }
  close(prims(footprintText(180, side, mirror, 'legacy')), prims(boardText(180, side, mirror)));
  close(prims(footprintText(0, side, mirror, '(unlocked no)')), prims(boardText(0, side, mirror)));
  close(prims(footprintText(0, side, mirror, '')), prims(boardText(0, side, mirror)));
  close(prims(footprintText(180, side, mirror, '(unlocked no)')), prims(footprintText(180, side, mirror, '')));
  assert.notDeepEqual(prims(footprintText(180, side, mirror, '(unlocked yes)')), prims(footprintText(180, side, mirror, '')));
}
console.log('ok authored footprint rotations/anchors/mirroring match board text on both sides (legacy and TRS)');

const fixture = readFileSync('test/fixtures/pcb-bottom-silk/asymmetric.kicad_pcb', 'utf8');
const target = / \(footprint "Test:BackLockedRotation"[\s\S]*?\n \(segment/;
assert.ok(target.test(fixture));
// Replace only the bottom label with board text at the exact same pose.
const expected = fixture.replace(target,
  ' (gr_text "BACK180" (at 40 29 180) (layer "B.SilkS") (effects (font (size 1.5 1.5) (thickness 0.25)) (justify mirror)))\n (segment');
const out = process.env.PCB_SILK_OUT || 'build/pcb-bottom-silk';
mkdirSync(out, { recursive: true });
for (const bottom of [false, true]) {
  const got = Buffer.from(array(lib.board(fixture, bottom)));
  const want = Buffer.from(array(lib.board(expected, bottom)));
  assert.ok(got.equals(want), `${bottom ? 'bottom' : 'top'} pixels differ from board-space text reference`);
  writeFileSync(`${out}/after-face-${bottom ? 'bottom' : 'top'}.ppm`, got);
}
console.log('ok native 3D bottom pixels match independent authored reference; top unchanged by bottom text representation');
