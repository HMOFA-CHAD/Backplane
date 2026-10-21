#!/usr/bin/env python3
"""Transport source-bound public build inputs into configured native producers.

No emission, publication, secret fetching, target acceptance or automatic install.
Only the checked-out producers execute; packet files are data, never scripts.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request

VERSION = '0.12.0'
OPERATIONS = ('unix-native', 'windows-native', 'android')
MAX_BYTES = 4 * 1024**3


def need(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def relative(name):
    need(isinstance(name, str) and name and '\\' not in name and ':' not in name, 'noncanonical input path')
    p = PurePosixPath(name)
    need(not p.is_absolute() and str(p) == name and all(x not in ('', '.', '..') for x in name.split('/')), 'unsafe input path')
    return p


def source_identity(source, checkout):
    need(re.fullmatch('[0-9a-f]{40}', source), 'full source commit required')
    def git(*args):
        return subprocess.check_output(['git', '-C', str(checkout), *args], text=True).strip()
    need(git('rev-parse', 'HEAD') == source, 'checkout differs from frozen source')
    need(not git('status', '--porcelain', '--untracked-files=no'), 'tracked source changed')
    return git('rev-parse', 'HEAD^{tree}')


def record_execution(checkout, source, tree):
    metadata = Path(__file__).resolve().parents[1]
    workflow = subprocess.check_output(['git', '-C', str(metadata), 'rev-parse', 'HEAD'], text=True).strip()
    expected = os.environ.get('GITHUB_SHA')
    need(not expected or expected == workflow, 'workflow tool checkout differs from actual workflow SHA')
    record = {'schema': 1, 'kind': 'backplane-bootstrap-execution', 'productSourceCommit': source,
              'productSourceTree': tree, 'workflowSourceCommit': workflow,
              'helperSha256': sha(Path(__file__).resolve()), 'version': VERSION,
              'channel': 'release', 'configuredBuildAccepted': False}
    p = checkout / 'build/bootstrap-execution.json'
    p.parent.mkdir(parents=True, exist_ok=True)
    if p.exists():
        need(json.loads(p.read_text()) == record, 'bootstrap execution provenance changed')
    else:
        p.write_text(json.dumps(record, indent=2) + '\n')
    return record


def inventory(directory):
    result = {}
    folded = set()
    for p in sorted(directory.rglob('*')):
        name = p.relative_to(directory).as_posix()
        relative(name)
        need(not p.is_symlink(), 'packet symlinks are refused')
        need(name.casefold() not in folded, 'case-colliding packet member')
        folded.add(name.casefold())
        if p.is_dir():
            continue
        need(p.is_file(), 'packet special file refused')
        need(not name.lower().endswith(('.pem', '.key', '.p12', '.pfx', '.keystore', '.jks', '.mobileprovision')),
             'private signing material is not a bootstrap input')
        result[name] = {'sha256': sha(p), 'bytes': p.stat().st_size}
    return result


def verify(directory, source, tree, operation):
    manifest = json.loads((directory / 'BOOTSTRAP.json').read_text())
    need((manifest.get('schema'), manifest.get('kind'), manifest.get('sourceCommit'), manifest.get('sourceTree'),
          manifest.get('version'), manifest.get('channel'), manifest.get('operation')) ==
         (1, 'backplane-public-build-inputs', source, tree, VERSION, 'release', operation), 'bootstrap identity mismatch')
    actual = inventory(directory)
    actual.pop('BOOTSTRAP.json', None)
    need(actual and actual == manifest.get('files'), 'bootstrap input bytes differ')
    if operation == 'unix-native':
        p = directory / 'emission/EMISSION.json'
        e = json.loads(p.read_text())
        need(e.get('kind') == 'backplane-service-c-emission' and
             e.get('status') == 'VERIFIED_PORTABLE_C_EMISSION_ONLY' and
             (e.get('sourceCommit'), e.get('sourceTree'), e.get('version')) == (source, tree, VERSION),
             'actual source-bound portable C emission required')
    else:
        name = 'windows-service-request.json' if operation == 'windows-native' else 'android-release-inputs.json'
        r = json.loads((directory / name).read_text())
        need((r.get('sourceCommit'), r.get('sourceTree', tree)) == (source, tree), 'producer request source mismatch')
    return manifest


def pack(directory, output, source, tree, operation):
    need(directory.is_dir() and not output.exists(), 'fresh packet output required')
    need(not (directory / 'BOOTSTRAP.json').exists(), 'input directory must not contain generated manifest')
    files = inventory(directory)
    need(files, 'empty packet refused')
    manifest = {'schema': 1, 'kind': 'backplane-public-build-inputs', 'sourceCommit': source,
                'sourceTree': tree, 'version': VERSION, 'channel': 'release', 'operation': operation, 'files': files}
    with tempfile.TemporaryDirectory(prefix='bp-bootstrap-pack-') as tmp:
        meta = Path(tmp) / 'BOOTSTRAP.json'
        meta.write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
        output.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(output, 'w:gz') as tar:
            tar.add(meta, arcname='BOOTSTRAP.json', recursive=False)
            for name in files:
                tar.add(directory / name, arcname=name, recursive=False)
    return {'archiveSha256': sha(output), 'archiveBytes': output.stat().st_size, **{k: manifest[k] for k in ('sourceCommit', 'sourceTree', 'operation')}}


def extract(archive, output):
    need(not output.exists(), 'fresh extraction directory required')
    with tarfile.open(archive, 'r:gz') as tar:
        members = tar.getmembers()
        names = set()
        total = 0
        for m in members:
            relative(m.name)
            need(m.isfile() and not m.issparse(), 'only regular packet files are allowed')
            need(not m.mode & 0o7002, 'privileged or world-writable packet mode refused')
            need(m.name.casefold() not in names, 'duplicate packet member')
            names.add(m.name.casefold())
            total += m.size
            need(0 <= m.size <= MAX_BYTES and total <= MAX_BYTES, 'packet size limit exceeded')
        output.mkdir(parents=True)
        for m in members:
            p = output / m.name
            p.parent.mkdir(parents=True, exist_ok=True)
            with tar.extractfile(m) as src, p.open('xb') as dst:
                shutil.copyfileobj(src, dst)
            # Producer receipts bind modes as well as bytes (local emits use 0664).
            p.chmod(m.mode & 0o777)


def fetch(url, expected, output, source, tree, operation):
    u = urllib.parse.urlsplit(url)
    need(u.scheme == 'https' and u.hostname and not u.username and not u.password and not u.fragment and
         u.port in (None, 443), 'HTTPS artifact URL without credentials required')
    need(re.fullmatch('[0-9a-f]{64}', expected), 'trusted packet digest required')
    with tempfile.TemporaryDirectory(prefix='bp-bootstrap-fetch-') as tmp:
        archive = Path(tmp) / 'inputs.tar.gz'
        # No account headers, cookies, config or secret environment is forwarded.
        with urllib.request.urlopen(urllib.request.Request(url), timeout=120) as response, archive.open('wb') as f:
            need(urllib.parse.urlsplit(response.url).scheme == 'https', 'insecure download redirect refused')
            count = 0
            for chunk in iter(lambda: response.read(1024 * 1024), b''):
                count += len(chunk)
                need(count <= MAX_BYTES, 'download size limit exceeded')
                f.write(chunk)
        need(sha(archive) == expected, 'download differs from trusted packet digest')
        extract(archive, output)
    return verify(output, source, tree, operation)


def tool(path):
    p = Path(path).resolve(strict=True)
    v = subprocess.check_output([str(p), '--version'], text=True).strip()
    need(re.search(r'clang version (?:19|[2-9][0-9])\.', v), 'clang 19+ required')
    return {'path': str(p), 'bytes': p.stat().st_size, 'sha256': sha(p), 'version': v}


def run(directory, operation, target, source, checkout, compiler=None):
    tree = source_identity(source, checkout)
    verify(directory, source, tree, operation)
    if operation == 'unix-native':
        need(target in ('linux-x64', 'linux-arm64', 'darwin-arm64'), 'actual Unix target required')
        receipt = directory / 'emission/EMISSION.json'
        r = {'schema': 1, 'kind': 'backplane-service-native-inputs', 'target': target,
             'release': {'version': VERSION, 'tag': 'v' + VERSION, 'channel': 'release', 'commit': source, 'tree': tree},
             'toolchain': {'clang': tool(compiler)}, 'emissionReceipt': {'path': str(receipt), 'sha256': sha(receipt), 'bytes': receipt.stat().st_size},
             'emissionDirectory': str(receipt.parent)}
        request = directory.parent / ('native-' + target + '.json')
        need(not request.exists(), 'inspect existing native request before retry')
        request.write_text(json.dumps(r, indent=2) + '\n')
        command = [sys.executable, str(Path(__file__).resolve().with_name('service-release.py')), 'native', '--source-root', str(checkout), '--request', str(request), '--out', str(checkout / 'build/bootstrap-native')]
    elif operation == 'windows-native':
        command = [sys.executable, str(Path(__file__).resolve().with_name('windows-release-request.py')), 'native', str(directory / 'windows-service-request.json')]
    else:
        helper = Path(__file__).resolve().with_name('build-android-artifacts.py')
        command = [sys.executable, str(helper), '--execution-helper-sha256', sha(helper), '--inputs', str(directory / 'android-release-inputs.json'), '--source', str(checkout), '--output', str(checkout / 'build/bootstrap-android')]
    subprocess.run(command, cwd=checkout, check=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='command', required=True)
    for name in ('pack', 'fetch', 'run'):
        a = sub.add_parser(name)
        a.add_argument('--directory', type=Path, required=True)
        a.add_argument('--source', required=True)
        a.add_argument('--operation', choices=OPERATIONS, required=True)
        a.add_argument('--checkout', type=Path, default=Path.cwd())
        if name == 'pack': a.add_argument('--out', type=Path, required=True)
        if name == 'fetch':
            a.add_argument('--url', required=True)
            a.add_argument('--sha256', required=True)
        if name == 'run':
            a.add_argument('--target')
            a.add_argument('--clang')
    a = p.parse_args()
    a.checkout = a.checkout.resolve()
    a.directory = a.directory.resolve()
    tree = source_identity(a.source, a.checkout)
    if a.command != 'pack': record_execution(a.checkout, a.source, tree)
    if a.command == 'pack': print(json.dumps(pack(a.directory, a.out.resolve(), a.source, tree, a.operation)))
    elif a.command == 'fetch':
        fetch(a.url, a.sha256, a.directory, a.source, tree, a.operation)
        print('PASS source-bound public input packet; configured build not yet run')
    else: run(a.directory, a.operation, a.target, a.source, a.checkout, a.clang)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError, tarfile.TarError):
        sys.exit('release-bootstrap: input or producer failed; inspect scoped producer receipts (no private inputs logged)')
