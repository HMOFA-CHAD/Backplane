import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Issue #362: the 3D viewer's GLB loader overflowed the JS hub's stack on
// model-sized lists. test.sh raises the runtime's stack allowance, so each
// case runs in a child with a small one: a walk that is not a tail call
// fails here at these sizes. The child gets Bun's own bound on an 8 MiB
// stack (no BUN_JSC_maxPerThreadStackUsage), as a v0.12.2 plot child had:
// about 40k frames.
const cases = ['empty', 'tris', 'order', 'model', 'cut', 'junk', 'solid'];
if (!process.argv[3]) {
  let failed = false;
  for (const name of cases) {
    const env = { ...process.env };
    delete env.BUN_JSC_maxPerThreadStackUsage;
    const result = spawnSync('/bin/sh', ['-c', 'ulimit -s 8192 && exec "$0" "$@"',
      process.execPath, import.meta.filename, resolve(process.argv[2]), name], {
      env,
      encoding: 'utf8',
      timeout: 120000,
    });
    process.stdout.write(result.stdout ?? '');
    process.stderr.write((result.stderr ?? '').slice(0, 2000));
    if (result.error) throw result.error;
    if (result.status !== 0) {
      console.log(`FAIL glb stack ${name} child exited ${result.status} (${result.signal ?? 'no signal'})`);
      failed = true;
    }
  }
  assert.equal(failed, false, 'every GLB case must finish on a small stack');
} else {
  const lib = (await import(pathToFileURL(resolve(process.argv[2])).href)).default;
  const n = (x) => Number(x);
  // the issue's file: an empty scene and a 250 KB BIN chunk
  const bin = 250000;
  // a board-sized mesh (the issue's boards had 36k and 47k triangles)
  const k = 40000;
  switch (process.argv[3]) {
    case 'empty':
      assert.equal(n(lib.size_empty(bin)), 12 + 8 + 96 + 8 + bin);
      assert.equal(n(lib.empty(bin)), 0);
      break;
    case 'tris':
      assert.equal(n(lib.tris(k)), k);
      break;
    case 'order':
      assert.equal(n(lib.order(k)), 1);
      break;
    case 'model':
      assert.equal(n(lib.model(k)), k);
      break;
    case 'cut': {
      // cut inside the BIN chunk and inside the JSON: bounded, no crash
      const inBin = n(lib.cut(k, 200000));
      assert.ok(inBin <= k, `a cut file gave ${inBin} triangles`);
      assert.equal(n(lib.cut(k, 100)), 0);
      break;
    }
    case 'junk':
      assert.equal(n(lib.junk(bin)), 0);
      break;
    case 'solid': {
      // spanning triangles survive thinning (an empty plot line is ~92 chars)
      const kept = n(lib.thin(k));
      assert.ok(kept > k * 0.9 && kept <= k, `thinning kept ${kept} of ${k}`);
      assert.ok(n(lib.solid(k)) > k * 10, 'the plot line carries the triangles');
      break;
    }
    default:
      throw new Error(`unknown GLB case: ${process.argv[3]}`);
  }
  console.log(`ok glb stack ${process.argv[3]}`);
}
