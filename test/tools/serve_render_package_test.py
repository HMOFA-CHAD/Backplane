#!/usr/bin/env python3
"""The package without a window binary: backplane-serve, backplane-render and
the `backplane` launcher, through the launcher itself, install-release.sh
(the installer's and the updater's swap), package.sh and dev.sh stage. Every
binary is a stub that records how it was called; nothing is built."""
import os, shutil, subprocess, sys, tempfile, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCH = ROOT / 'deploy/backplane-launch.sh'
fails = []


def check(name, ok):
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok:
        fails.append(name)


def stub(path, tag, log):
    path.write_text(f'#!/bin/sh\necho "{tag} $*" >> "{log}"\n')
    path.chmod(0o755)


def run(cmd, env=None, cwd=None):
    e = {k: v for k, v in os.environ.items() if k not in ('DISPLAY', 'WAYLAND_DISPLAY', 'BACKPLANE_DESKTOP')}
    e.update(env or {})
    return subprocess.run(cmd, env=e, cwd=cwd, capture_output=True, text=True, timeout=60)


def launcher(t):
    d = t / 'launch'
    d.mkdir()
    log = d / 'calls.log'
    shutil.copy(LAUNCH, d / 'backplane')
    stub(d / 'backplane-serve', 'serve', log)
    stub(d / 'backplane-render', 'render', log)
    bin_ = t / 'bin'
    bin_.mkdir()
    (bin_ / 'backplane').symlink_to(d / 'backplane')
    home = t / 'home'

    def calls():
        return log.read_text().splitlines() if log.exists() else []

    run([str(bin_ / 'backplane'), '--render', 'a.step', '--size', '8x8'])
    check('launcher: --render goes to backplane-render (through a link)', calls() == ['render --render a.step --size 8x8'])
    log.unlink()
    run([str(d / 'backplane'), '--home', str(home), '--port', '9'], {'DISPLAY': ':9'})
    check('launcher: no desktop app runs the hub in the foreground', calls() == [f'serve --home {home} --port 9'])
    log.unlink()
    r = run([str(d / 'backplane'), '--headless', '--home', str(home)])
    for _ in range(50):
        if log.exists():
            break
        time.sleep(0.05)
    check('launcher: --headless detaches the hub with --foreground', calls() == [f'serve --headless --home {home} --foreground'])
    check('launcher: --headless says where the log is', 'headless.log' in r.stdout and (home / 'headless.log').exists())
    log.unlink()
    run([str(d / 'backplane'), '--headless', '--foreground'])
    check('launcher: --headless --foreground stays in front', calls() == ['serve --headless --foreground'])
    log.unlink()
    (d / 'desktop').mkdir()
    desk = d / 'desktop/backplane-open'
    desk.write_text(f'#!/bin/sh\necho "desktop home=$BACKPLANE_HOME $*" >> "{log}"\n')
    desk.chmod(0o755)
    run([str(d / 'backplane'), '--home', str(home)], {'DISPLAY': ':9'})
    check('launcher: desktop app with a display, --home as BACKPLANE_HOME', calls() == [f'desktop home={home} '])
    log.unlink()
    run([str(d / 'backplane'), '--home', str(home)])
    check('launcher: desktop app but no display runs the hub', calls() == [f'serve --home {home}'])
    log.unlink()
    run([str(d / 'backplane'), '--headless', '--foreground'], {'DISPLAY': ':9'})
    check('launcher: --headless never opens the desktop app', calls() == ['serve --headless --foreground'])


def pkg(t, name, with_launcher):
    src = t / name
    (src / 'web').mkdir(parents=True)
    (src / 'web/index.html').write_text('new')
    for f in ('backplane-serve', 'backplane-render'):
        (src / f).write_text('#!/bin/sh\necho new\n')
        (src / f).chmod(0o755)
    if with_launcher:
        shutil.copy(LAUNCH, src / 'backplane')
    return src


def old_install(t, name):
    prefix = t / name
    (prefix / 'web').mkdir(parents=True)
    (prefix / 'web/index.html').write_text('old')
    for f in ('backplane', 'backplane-serve'):
        (prefix / f).write_text('OLD WINDOW BINARY')
    bin_ = t / (name + '-bin')
    bin_.mkdir()
    (bin_ / 'backplane').symlink_to(prefix / 'backplane')
    return prefix, bin_


def install(t):
    sh = ROOT / 'scripts/install-release.sh'
    prefix, bin_ = old_install(t, 'p1')
    r = run(['sh', str(sh), str(pkg(t, 'r1', True)), str(prefix)])
    check('install: package with launcher installs', r.returncode == 0)
    check('install: backplane is the launcher', (prefix / 'backplane').read_text() == LAUNCH.read_text())
    check('install: backplane-render installed', (prefix / 'backplane-render').exists())
    check('install: web swapped, old kept', (prefix / 'web/index.html').read_text() == 'new' and (prefix / 'web.old').is_dir())
    check('install: ~/.local/bin/backplane resolves', (bin_ / 'backplane').resolve().exists())

    prefix, bin_ = old_install(t, 'p2')
    r = run(['sh', str(sh), str(pkg(t, 'r2', False)), str(prefix)])
    check('install: package without backplane installs', r.returncode == 0)
    b = prefix / 'backplane'
    check('install: old window binary replaced by a link to backplane-serve',
          b.is_symlink() and os.readlink(b) == 'backplane-serve')
    check('install: no dangling ~/.local/bin/backplane', (bin_ / 'backplane').resolve().exists())

    prefix, _ = old_install(t, 'p3')
    src = pkg(t, 'r3', True)
    (src / 'backplane-render').unlink()
    r = run(['sh', str(sh), str(src), str(prefix)])
    check('install: package without backplane-render refused, nothing replaced',
          r.returncode != 0 and 'backplane-render' in r.stderr and (prefix / 'web/index.html').read_text() == 'old')


def package(t):
    tree = t / 'tree'
    (tree / 'scripts').mkdir(parents=True)
    for f in ('scripts/package.sh', 'scripts/install-release.sh', 'deploy/backplane.desktop', 'assets/icon/backplane.svg',
              'assets/icon/backplane-256.png', 'assets/icon/backplane-desktop.svg', 'assets/icon/backplane-desktop-256.png', 'LICENSE'):
        (tree / f).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / f, tree / f)
    dist = tree / 'dist'
    (dist / 'web').mkdir(parents=True)
    (dist / 'kistack').mkdir()
    (dist / 'web/index.html').write_text('w')
    for f in ('backplane-serve', 'backplane-render'):
        (dist / f).write_text('bin')
    r = run(['sh', 'scripts/package.sh', 'v0.12.0', 'linux-arm64'], cwd=tree)
    check('package: builds without a window binary', r.returncode == 0)
    names = subprocess.run(['tar', '-tzf', str(dist / 'backplane-v0.12.0-linux-arm64.tar.gz')], capture_output=True, text=True).stdout.split()
    check('package: serve and render, no backplane', 'backplane-linux-arm64/backplane-render' in names and 'backplane-linux-arm64/backplane' not in names)
    shutil.copy(LAUNCH, dist / 'backplane')
    r = run(['sh', 'scripts/package.sh', 'v0.12.0', 'linux-arm64'], cwd=tree)
    names = subprocess.run(['tar', '-tzf', str(dist / 'backplane-v0.12.0-linux-arm64.tar.gz')], capture_output=True, text=True).stdout.split()
    check('package: carries the launcher when built', r.returncode == 0 and 'backplane-linux-arm64/backplane' in names)


def dev_stage(t):
    tree = t / 'dev'
    log = tree / 'calls.log'
    for f in ('scripts/dev.sh', 'scripts/bendok.sh', 'deploy/backplane-launch.sh', 'LICENSE', 'src/web/sw.js'):
        (tree / f).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / f, tree / f)
    (tree / 'tools/voice').mkdir(parents=True)
    (tree / 'tools/kipc').mkdir(parents=True)
    home = tree / 'home'
    (home / '.bend/bin').mkdir(parents=True)
    (home / '.bun/bin').mkdir(parents=True)
    (tree / 'scripts/verified.sh').write_text('#!/bin/sh\nexit 1\n')
    for f in ('js-unmarshal.py', 'js-native.py', 'cef-runtime.py'):
        (tree / 'scripts' / f).write_text(f'import sys\nopen({str(log)!r},"a").write({f!r}+" "+" ".join(sys.argv[1:])+"\\n")\n')
    (tree / 'scripts/build-app.sh').write_text(f'#!/bin/sh\necho "build-app $1 $2 stamp=${{BACKPLANE_VERSION_STAMP:-}}" >> "{log}"\necho bin > "$2"\n')
    (tree / 'scripts/build-kistack.sh').write_text(f'#!/bin/sh\necho "kistack" >> "{log}"\nmkdir -p "$1"\n')
    (tree / 'scripts/build-browser.sh').write_text('#!/bin/sh\nexit 1\n')
    (home / '.bend/bin/bend').write_text(
        f'#!/bin/sh\necho "bend $*" >> "{log}"\ncase "$*" in *--check-only*) echo "ALL PROOFS CHECK"; exit 0;; esac\n'
        'if [ "${2:-}" = -o ]; then mkdir -p "$3"; echo x > "$3/chunk-1.js"; echo y > "$3/index.html"; echo z > "$3/a.css"; fi\n')
    (home / '.bun/bin/bun').write_text(f'#!/bin/sh\necho "bun $*" >> "{log}"\n[ "${{1:-}}" = build.ts ] && echo b > "$2"\nexit 0\n')
    for p in list((tree / 'scripts').glob('*.sh')) + [home / '.bend/bin/bend', home / '.bun/bin/bun']:
        p.chmod(0o755)
    subprocess.run('git init -q && git add -A && git -c user.email=m@m -c user.name=m commit -qm m && git tag v0.11.1',
                   shell=True, cwd=tree, check=True)

    def stage(env):
        log.unlink(missing_ok=True)
        out = tree / 'out'
        r = run(['sh', 'scripts/dev.sh', 'stage', str(out)], dict(env, HOME=str(home), BACKPLANE_PREFIX=str(tree / 'prefix')), cwd=tree)
        return r, (log.read_text() if log.exists() else ''), sorted(p.name for p in out.iterdir()) if out.is_dir() else []

    r, calls, staged = stage({'BACKPLANE_VERSION_STAMP': '0.12.1-main.1'})
    check('dev stage: default builds the server and render roots, stamped',
          r.returncode == 0 and 'build-app src/server/main.bend dist/backplane-serve stamp=0.12.1-main.1' in calls
          and 'build-app src/render/main.bend dist/backplane-render stamp=0.12.1-main.1' in calls)
    check('dev stage: never checks or builds src/app/main.bend', 'src/app/main.bend' not in calls)
    check('dev stage: default still builds KiStack and helpers, looks for CEF', 'kistack' in calls and 'bun build.ts' in calls and 'cef-runtime.py discover' in calls)
    check('dev stage: default stages launcher, serve, render', {'backplane', 'backplane-serve', 'backplane-render', 'kistack', 'web'} <= set(staged))
    r, calls, staged = stage({'BACKPLANE_DEV_SERVICE_ONLY': '1', 'BACKPLANE_VERSION_STAMP': '0.12.1-main.2'})
    check('dev stage: service-only stages launcher, serve, render, web, LICENSE',
          r.returncode == 0 and staged == ['LICENSE', 'backplane', 'backplane-render', 'backplane-serve', 'web'])
    check('dev stage: service-only skips KiStack, helpers and CEF', not any(k in calls for k in ('kistack', 'bun ', 'cef-runtime')))
    r, calls, _ = stage({'BACKPLANE_DEV_SERVICE_ONLY': '1'})
    check('dev stage: no caller stamp keeps the generated dev stamp', 'stamp=0.11.2-dev.' in calls)
    r, calls, _ = stage({'BACKPLANE_DEV_SERVICE_ONLY': 'yes'})
    check('dev stage: a bad service-only value is refused before building', r.returncode != 0 and calls == '')


with tempfile.TemporaryDirectory() as d:
    t = Path(d)
    launcher(t)
    install(t)
    package(t)
    dev_stage(t)
print(f'{len(fails)} failed' if fails else 'ok')
sys.exit(1 if fails else 0)
