#!/usr/bin/env python3
"""One coordinated, cached gate. No pushes, workflows, releases or installs."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
CACHE = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'backplane-bend'


def run(argv, **kwargs):
    return subprocess.run(argv, cwd=ROOT, check=True, **kwargs)


def output(argv, **kwargs):
    return subprocess.check_output(argv, cwd=ROOT, text=True, **kwargs).strip()


def key(name, roots, files):
    # The existing key covers the compiler, its libraries and transitive effects.
    # Extra runners/drivers are explicit: a changed JS test cannot reuse a pass.
    env = {**os.environ, 'BP_KEY_ROOTS': ' '.join(roots)} if roots else os.environ
    try:
        base = output(['scripts/inputs-key.sh', 'local-ci-v1:' + name,
                       'scripts/local-ci.py', *sorted(set(files))], env=env)
        tools = [output(['node','--version']), output(['bun','--revision']), sys.version, sys.platform, resource.getrlimit(resource.RLIMIT_STACK)]
        environment = {k:v for k,v in os.environ.items() if k.startswith(('BUN_','BEND_','LC_','CHECK_','TEST_')) or k in ['BENDTT','CC','NODE_OPTIONS','LANG','TZ']}
        return hashlib.sha256(json.dumps([base, tools, environment], sort_keys=True).encode()).hexdigest()
    except subprocess.CalledProcessError:
        return None  # fail closed: run, never reuse an incomplete key


def gates():
    files = output(['git', 'ls-files', '--cached', '--others', '--exclude-standard']).splitlines()
    def under(*prefixes):
        return [f for f in files if f.startswith(prefixes)]
    scripts = under('scripts/')
    tests = under('test/')
    checker = ['scripts/check.sh','scripts/bendok.sh','scripts/check-manifest.py','scripts/i18n-gen.py','scripts/inputs-key.sh','scripts/bend-closure.py'] + under('i18n/')
    test_scripts = [f for f in scripts if not f.startswith('scripts/local')]
    return [
        ('small', [], under('scripts/', 'test/tools/', 'desktop/', '.github/', 'assets/', 'deploy/') + ['desktop/package-lock.json','LICENSE'],
         [sys.executable, 'scripts/local-small.py']),
        ('check', [f for f in files if f.endswith('.bend') and f != 'PROOF.bend'], checker,
         ['scripts/check.sh', 'check']),
        ('proof', ['PROOF.bend'], checker, ['scripts/check.sh', 'proof']),
        ('build-smoke', ['src/server/main.bend', 'src/web/app.bend', 'src/mobile/app.bend', 'test/wire/wire.bend'], scripts + tests + under('src/web/', 'src/mobile/', 'mobile/', 'desktop/', 'assets/', 'deploy/') + ['LICENSE'],
         [sys.executable, 'scripts/local.py', 'build', '--smoke']),
        ('tests', [f for f in files if f.startswith('test/') and f.endswith('_test.bend')], test_scripts + tests + under('deploy/') + [f for f in under('src/', 'tools/') if not f.endswith('.bend')],
         ['scripts/test.sh']),
    ]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--full', action='store_true', help='Ignore recorded passes')
    p.add_argument('--admitted', action='store_true', help=argparse.SUPPRESS)
    a = p.parse_args()
    os.chdir(ROOT)
    os.environ.update(PYTHONDONTWRITEBYTECODE='1', BEND_NO_TELEMETRY='1', BACKPLANE_TELEMETRY='off',
                      BACKPLANE_TELEMETRY_BAKE='0', BACKPLANE_GOOGLE_BAKE='0',
                      CHECK_JOBS='1', CHECK_SHARDS='1', CHECK_FALLBACK='0', TEST_JOBS='2', TEST_SHARD_COUNT='1', BACKPLANE_MEM_GB='16', BUN_JSC_forceRAMSize='4294967296')
    CACHE.mkdir(parents=True, exist_ok=True)
    # One controller machine-wide, including across worktrees. Fail promptly;
    # never enqueue multiple admission requests or cancel another owner's work.
    with (CACHE / 'local-ci.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('A combined local CI run already owns this machine.', file=sys.stderr); return 3
        if not a.admitted and not a.dry_run:
            admit = Path(os.environ.get('BP_ADMIT', Path.home() / 'Documents/i2cjak/bp-coord/bin/bp-admit.sh'))
            if not admit.is_file():
                raise SystemExit('Set BP_ADMIT to the admission wrapper; refusing an uncapped run')
            # Keep the controller lock across exec, so there is exactly one queued job.
            os.set_inheritable(lock.fileno(), True)
            env = {**os.environ, 'BP_LOCAL_CI_LOCK_FD': str(lock.fileno())}
            cmd = [str(admit), '--priority', '--mem', '16', '--cores', '2', '--',
                   sys.executable, str(Path(__file__).resolve()), '--admitted']
            if a.full: cmd.append('--full')
            return subprocess.call(cmd, cwd=ROOT, env=env, pass_fds=(lock.fileno(),))
        return execute(a)


def execute(a):
    if a.full: os.environ['BP_LOCAL_CI_FULL'] = '1'
    folder = ROOT / 'build/local-ci' / time.strftime('%Y%m%d-%H%M%S')
    records = CACHE / 'local-ci-passes'
    rows = []
    if not a.dry_run: folder.mkdir(parents=True, exist_ok=False)
    start = time.monotonic()
    for name, roots, files, cmd in gates():
        k = key(name, roots, files)
        record = records / (str(k) + '.json')
        try: prior = json.loads(record.read_text())
        except (OSError, ValueError): prior = {}
        # Recreate and inspect a stage every time. The emit/web/runtime caches
        # reuse valid inputs underneath; a pass is not proof an artifact exists.
        reused = name != 'build-smoke' and not a.full and k and prior.get('key') == k and prior.get('gate') == name
        print(f'{name}: {"reused" if reused else "run"} ({k or "unkeyed"})', flush=True)
        if a.dry_run: continue
        t = time.monotonic()
        row = {'gate': name, 'key': k, 'state': 'reused' if reused else 'running'}
        if not reused:
            with (folder / (name + '.log')).open('w') as log:
                r = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            incomplete = r.returncode < 0 or r.returncode in (70,75,76,77,124) or r.returncode >= 128
            row.update(rc=r.returncode, state='passed' if r.returncode == 0 else 'incomplete' if incomplete else 'failed')
            if r.returncode == 0 and k and key(name, roots, files) == k:
                records.mkdir(parents=True, exist_ok=True)
                temp = record.with_suffix('.' + str(os.getpid()) + '.tmp')
                temp.write_text(json.dumps({'key': k, 'gate': name, 'commit': output(['git', 'rev-parse', 'HEAD'])}))
                temp.replace(record)
        if k and key(name, roots, files) != k: row['state'] = 'incomplete'
        row['seconds'] = round(time.monotonic() - t, 3)
        rows.append(row)
        result = {'seconds': round(time.monotonic()-start, 3), 'gates': rows,
                  'state': 'failed' if row['state'] == 'failed' else 'incomplete'}
        (folder / 'RESULT.json').write_text(json.dumps(result, indent=2) + '\n')
        if row['state'] in ('failed','incomplete'):
            print(f'{row["state"]}: {folder / (name + ".log")}'); return 1 if row['state'] == 'failed' else 3
    if not a.dry_run:
        result['state'] = 'passed'
        (folder / 'RESULT.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    # The admission child inherits the parent's lock; do not try to acquire it again.
    if os.environ.get('BP_LOCAL_CI_LOCK_FD') and '--admitted' in sys.argv:
        parser = argparse.Namespace(dry_run=False, full='--full' in sys.argv)
        sys.exit(execute(parser))
    sys.exit(main())
