from pathlib import Path
import difflib, hashlib, json, tarfile, shutil, subprocess
root = Path.cwd()
base = root / 'build/phone-cache/handoff/source'
out = root / 'build/phone-cache/final'
out.mkdir(parents=True, exist_ok=True)
h = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
original = json.JSONDecoder().raw_decode((root / 'build/phone-cache/handoff/native-manifest.json').read_text())[0]
changes = {}
chunks = []
for p in sorted(root.glob('mobile/**/*')):
    rel = p.relative_to(root)
    if not p.is_file() or '/build/' in str(rel) or p.suffix not in ('.kt', '.swift'): continue
    old = (base / rel).read_text() if (base / rel).exists() else ''
    new = p.read_text()
    if old == new: continue
    if old: assert h(base / rel) == original[str(rel)], str(rel)
    changes[str(rel)] = {'before': h(base / rel) if old else None, 'after': h(p)}
    dest = out / 'source' / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(p, dest)
    chunks.extend(difflib.unified_diff(old.splitlines(True), new.splitlines(True), fromfile='a/' + str(rel) if old else '/dev/null', tofile='b/' + str(rel)))
(out / 'native-incremental.patch').write_text(''.join(chunks))
(out / 'native-pins.json').write_text(json.dumps(changes, indent=2) + '\n')
subprocess.run(['git', 'apply', '--check', '--reverse', str(out / 'native-incremental.patch')], check=True)
for file in ['red.log', 'ios-helper-runtime.log', 'android-compile-final.log', 'ios-compile-final.log', 'compile-result.json', 'mac-inventory.txt']:
    shutil.copyfile(root / 'build/phone-cache' / file, out / file)
with tarfile.open(out / 'native-source-tests.tar.gz', 'w:gz') as archive:
    for file in sorted((out / 'source').rglob('*')):
        if file.is_file(): archive.add(file, arcname=str(file.relative_to(out / 'source')), recursive=False)
    for file in sorted((root / 'test/phone-cache').glob('*')):
        if file.is_file(): archive.add(file, arcname=str(file.relative_to(root)), recursive=False)
receipt = {
  'status': 'PASS_NATIVE_COMPILATION_AND_HELPER_RUNTIME_ONLY',
  'baseline_manifest_sha256': h(root / 'build/phone-cache/handoff/native-manifest.json'),
  'baseline_archive_sha256': h(root / 'build/phone-cache/handoff/native-source.tar.gz'),
  'source_changes': changes,
  'patch_sha256': h(out / 'native-incremental.patch'),
  'archive_sha256': h(out / 'native-source-tests.tar.gz'),
  'native_pins_sha256': h(out / 'native-pins.json'),
  'checks': {'red': 'Old native cache drops 7MB screen; FAIL expected', 'ios_helper': 'PASS actual macOS Swift production ScreenCache and PresentationReadiness methods', 'android_compile': 0, 'ios_generic_simulator_compile': 0, 'patch_reverse_check': 'PASS'},
  'behavior': ['512KiB and at most 40 recent entries; oversized reply text bounded; in-progress text preserved', 'iOS selected stack restored; Android picture before lazy engine/full state', 'canonical credential+install profile identity; sanitized cache miss diagnostics', 'generation invalidation rejects old writes; local drafts isolated from cache and preserved', 'freshness requires presented/live on current hub/epoch plus expected navigation; history does not unlock', 'cache never feeds replay/cursors/commands/pending sends; canonical FIFO remains shared owner code'],
  'limits': ['No app installed or booted by this lane', 'No actual phone UI first-useful/current-text timing acceptance yet', 'No Android device available; native Kotlin compiled, runtime helper still pending', 'No final emitted bridge combined acceptance yet; shared owner composes and builds it', 'No PR/merge/live service/device rollout from this lane; root retains sole rollout'],
  'logs': {name: h(out / name) for name in ['red.log', 'ios-helper-runtime.log', 'android-compile-final.log', 'ios-compile-final.log', 'compile-result.json']},
}
(out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'path': str(out), 'changed_native_paths': len(changes), 'receipt_sha256': h(out / 'receipt.json'), 'patch_sha256': receipt['patch_sha256'], 'archive_sha256': receipt['archive_sha256']}, indent=2))
