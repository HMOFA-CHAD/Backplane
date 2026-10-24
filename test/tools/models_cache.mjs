import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// test.sh raises the checker's stack allowance. Run the emitted code with a
// bounded runtime stack so a recursive walker cannot pass by using that space.
if (!process.argv[3]) {
  let failed = false;
  for (const name of ['format', 'json', 'text', 'one', 'roundtrip']) {
    const result = spawnSync(process.execPath, [import.meta.filename, resolve(process.argv[2]), name], {
      env: { ...process.env, BUN_JSC_maxPerThreadStackUsage: '524288' },
      encoding: 'utf8',
      timeout: 30000,
    });
    process.stdout.write(result.stdout ?? '');
    process.stderr.write(result.stderr ?? '');
    if (result.error) throw result.error;
    if (result.status !== 0) {
      console.log(`FAIL models cache ${name} child exited ${result.status} (${result.signal ?? 'no signal'})`);
      failed = true;
    }
  }
  assert.equal(failed, false, 'all cache regressions must finish successfully');
} else {
  const lib = (await import(pathToFileURL(resolve(process.argv[2])).href)).default;
  const long = 'x'.repeat(100000);
  const prompt = `${long}\n🦋\n${long}`;
  switch (process.argv[3]) {
    case 'format':
      for (const input of ['', '\n', 'abc', '\n\n', 'a\nb\nc', 'a\r\nb\n', '🦋\n漢字\n⚡']) {
        const at = input.indexOf('\n');
        assert.equal(lib.one(input), input.replaceAll('\n', ''));
        assert.equal(lib.json(input), at < 0 ? input : input.slice(0, at));
        assert.equal(lib.text(input), at < 0 ? '' : input.slice(at + 1));
      }
      break;
    case 'json':
      // A tiny first line must not make the reader walk the whole prompt.
      assert.equal(lib.json(`{}\n${prompt}`), '{}');
      assert.equal(lib.json(long), long);
      break;
    case 'text':
      assert.equal(lib.text(`{}\n${prompt}`), prompt);
      assert.equal(lib.text(long), '');
      break;
    case 'one':
      assert.equal(lib.one(`${long}\n${long}\n`), long + long);
      break;
    case 'roundtrip': {
      const models = `{"models":["${long}"]}`;
      const cached = lib.cache(models, prompt);
      assert.equal(cached, `${models}\n${prompt}`);
      assert.equal(lib.json(cached), models);
      assert.equal(lib.text(cached), prompt);
      assert.equal(lib.cache('a\nb\n', 'c\nd\n'), 'ab\nc\nd\n');
      break;
    }
    default:
      throw new Error(`unknown cache regression: ${process.argv[3]}`);
  }
  console.log(`ok models cache ${process.argv[3]}`);
}
