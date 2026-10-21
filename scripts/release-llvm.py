#!/usr/bin/env python3
"""Install only official LLVM21 compiler/runtime files into a fresh user prefix."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

VERSION = '21.1.8'
# SHA256 subjects published in the corresponding official LLVM release JSONL.
ASSETS = {
    'linux-x64': ('X64', 'b3b7f2801d15d50736acea3c73982994d025b01c2f035b91ae3b49d1b575732b', 'x86_64'),
    'linux-arm64': ('ARM64', '65ce0b329514e5643407db2d02a5bd34bf33d159055dafa82825c8385bd01993', 'aarch64'),
}


def need(ok, message):
    if not ok: raise ValueError(message)


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''): h.update(block)
    return h.hexdigest()


def safe(name):
    p = PurePosixPath(name)
    need(name and not p.is_absolute() and '\\' not in name and ':' not in name and
         all(s not in ('', '.', '..') for s in name.split('/')), 'unsafe LLVM member')
    return p


def selected(name):
    p = PurePosixPath(name)
    return (name in ('bin/clang', 'bin/clang-21') or name.startswith('lib/clang/') or
            (len(p.parts) >= 2 and p.parts[0] == 'lib' and '.so' in p.name))


def unpack(archive, output):
    need(not output.exists(), 'fresh LLVM prefix required; inspect prior effect before retry')
    with tarfile.open(archive, 'r:xz') as tar:
        members = tar.getmembers()
        candidates = [m.name[:-len('bin/clang-21')] for m in members if m.name.endswith('bin/clang-21')]
        need(len(candidates) == 1, 'official compiler layout not recognized')
        prefix = candidates[0]
        chosen = {}
        for m in members:
            safe(m.name.rstrip('/'))
            if not m.name.startswith(prefix): continue
            name = m.name[len(prefix):].rstrip('/')
            if not name or not selected(name) or m.isdir(): continue
            safe(name)
            need(name not in chosen and (m.isfile() or m.issym() or m.islnk()), 'unexpected LLVM entry')
            need(not m.mode & 0o7000 and m.size <= 2 * 1024**3, 'privileged/oversized LLVM entry')
            chosen[name] = m
        need('bin/clang' in chosen and 'bin/clang-21' in chosen, 'official compiler members missing')
        output.mkdir(parents=True)
        for name, m in chosen.items():
            if not m.isfile(): continue
            target = output / name; target.parent.mkdir(parents=True, exist_ok=True)
            with tar.extractfile(m) as src, target.open('xb') as dst: shutil.copyfileobj(src, dst)
            target.chmod(0o755 if m.mode & 0o111 else 0o644)
        for name, m in chosen.items():
            if m.isfile(): continue
            need(not Path(m.linkname).is_absolute() and '\\' not in m.linkname, 'absolute LLVM link refused')
            link = m.linkname
            if m.islnk():
                need(link.startswith(prefix), 'hard link outside official prefix')
                link = os.path.relpath(output / link[len(prefix):], (output / name).parent)
            resolved = Path(os.path.normpath(str((output / name).parent / link)))
            need(output in resolved.parents, 'escaping LLVM link refused')
            target = output / name; target.parent.mkdir(parents=True, exist_ok=True); target.symlink_to(link)
        for name in chosen:
            need((output / name).resolve(strict=True).is_relative_to(output), 'dangling/escaping selected LLVM member')


def install(target, output):
    arch, expected, machine = ASSETS[target]
    need(platform.system() == 'Linux' and platform.machine() == machine, 'actual Linux target required')
    need(not output.exists(), 'fresh user compiler prefix required')
    name = f'LLVM-{VERSION}-Linux-{arch}.tar.xz'
    url = f'https://github.com/llvm/llvm-project/releases/download/llvmorg-{VERSION}/{name}'
    with tempfile.TemporaryDirectory(prefix='bp-official-llvm-') as tmp:
        archive = Path(tmp) / name
        with urllib.request.urlopen(url, timeout=180) as src, archive.open('wb') as dst:
            size = 0
            for block in iter(lambda: src.read(1024 * 1024), b''):
                size += len(block); need(size <= 3 * 1024**3, 'LLVM download unexpectedly large'); dst.write(block)
        need(digest(archive) == expected, 'official LLVM archive digest mismatch')
        unpack(archive, output)
    compiler = (output / 'bin/clang').resolve(strict=True)
    version = subprocess.check_output([str(compiler), '--version'], text=True).strip()
    need('clang version ' + VERSION in version, 'downloaded compiler version mismatch')
    receipt = {'schema': 1, 'kind': 'backplane-user-compiler-provisioning', 'target': target,
               'upstream': url, 'upstreamSha256': expected, 'version': version,
               'compiler': {'path': str(compiler), 'sha256': digest(compiler), 'bytes': compiler.stat().st_size},
               'privilegedCommands': False, 'productBuildExecuted': False}
    (output / 'LLVM-PROVENANCE.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return compiler


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--target', choices=ASSETS, required=True)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()
    try: print(install(a.target, a.out.resolve()))
    except (ValueError, KeyError, OSError, subprocess.SubprocessError, tarfile.TarError):
        raise SystemExit('release-llvm: official user-space compiler provisioning failed; no admin changes made')
