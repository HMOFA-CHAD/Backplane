#!/usr/bin/env python3
"""Workflow adapter for the Windows owner's service producer; never publishes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def local(root, value, directory=False):
    if not isinstance(value, str) or not value or '\\' in value or ':' in value or any(x in ('', '.', '..') for x in value.split('/')):
        raise ValueError('request paths must be canonical relative paths')
    path = root
    for part in value.split('/'):
        path /= part
        if path.is_symlink() or getattr(path.lstat(), 'st_file_attributes', 0) & 0x400:
            raise ValueError('indirect request path refused')
    if not (path.is_dir() if directory else path.is_file()):
        raise ValueError('request input is missing')
    return str(path)


def plan(root, request, operation, source, version):
    if (request.get('schema'), request.get('sourceCommit'), request.get('version'),
            request.get('channel'), request.get('operation')) != (1, source, version, 'release', operation):
        raise ValueError('Windows workflow request identity mismatch')
    if not re.fullmatch('[0-9a-f]{40}', source) or version != '0.12.0':
        raise ValueError('frozen 0.12.0 source required')
    runtime = local(root, request.get('runtimePayload'), directory=True)
    runtime_sha = request.get('runtimeManifestSha256', '')
    if not re.fullmatch('[0-9a-f]{64}', runtime_sha):
        raise ValueError('root-reviewed runtime manifest digest required')
    common = ['--runtime-payload', runtime, '--runtime-manifest-sha256', runtime_sha]
    if operation == 'native':
        archive = local(root, request.get('inputArchive'))
        sha = request.get('inputSha256', '')
        if not re.fullmatch('[0-9a-f]{64}', sha) or hashlib.sha256(Path(archive).read_bytes()).hexdigest() != sha:
            raise ValueError('emitted input archive changed')
        return ['native', '--inputs', archive, '--sha256', sha, *common, '--out', 'build/windows-service-native']
    policy = request.get('signingPolicy')
    if operation != 'package' or policy not in ('authenticode', 'unsigned-portable-allowed'):
        raise ValueError('explicit root public signing policy required')
    native = local(root, request.get('nativeDirectory'), directory=True)
    result = ['package', '--native-dir', native, *common, '--out', 'build/windows-service-resources',
              '--signing-policy', policy]
    if policy == 'authenticode':
        thumb = request.get('signingThumbprint', '')
        if not re.fullmatch('[0-9A-Fa-f]{40}', thumb):
            raise ValueError('approved signing certificate identity required')
        result += ['--signing-thumbprint', thumb]
    resident = {'mode': 'resident-service', 'managedStop': False, 'managedUpdate': False}
    if request.get('lifecyclePolicy') == resident:
        return result
    control = request.get('managedControlReceipt', {})
    control_path = local(root, control.get('path'))
    control_sha = control.get('sha256', '')
    if not re.fullmatch('[0-9a-f]{64}', control_sha) or hashlib.sha256(Path(control_path).read_bytes()).hexdigest() != control_sha:
        raise ValueError('actual managed-control receipt digest required')
    return [*result, '--managed-control-receipt', control_path, '--managed-control-sha256', control_sha]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('operation', choices=('native', 'package'))
    p.add_argument('request', type=Path)
    a = p.parse_args()
    source = os.environ.get('BACKPLANE_FROZEN_COMMIT', '')
    version = os.environ.get('BACKPLANE_VERSION', '').removeprefix('v')
    request = a.request.resolve()
    command = plan(request.parent, json.loads(request.read_text()), a.operation, source, version)
    # Cygwin/native platform, clean source, configured headers, recursive PE
    # closure and raw SOURCE3/BUILD3 acceptance belong to windows-service.py.
    producer = (['bash', 'scripts/ci-windows.sh', '--service'] if a.operation == 'native' else
                [sys.executable, 'scripts/package-windows.py', '--service'])
    subprocess.run([*producer, *command[1:]], check=True)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError):
        sys.exit('windows-release-request: request or producer failed (no private inputs logged)')
