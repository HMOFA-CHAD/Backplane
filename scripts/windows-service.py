#!/usr/bin/env python3
"""Produce/verify genuine Windows service resources, separately from Electron.

No command is a publication or runtime-acceptance gate. Legacy app receipts
are deliberately incompatible. Private configuration stays in native headers.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile

TOOLS_ROOT = Path(__file__).resolve().parent.parent
ROOT = TOOLS_ROOT
ENTRY = 'src/server/main.bend'
TELEMETRY_ENDPOINT = 'https://backplane.works/api/v1/events'
INPUT_ARCHIVE = 'backplane-windows-service-inputs.tar.gz'
RESOURCE_ARCHIVE = 'backplane-windows-service-resources.zip'
FONT_EXT = {'.ttf', '.otf', '.ttc', '.otc', '.woff', '.woff2', '.dfont', '.pfb', '.pfa',
            '.eot', '.bdf', '.pcf', '.psf', '.psfu', '.fon', '.fnt', '.otb'}
CONTROL_CHECKS = ('idleStopJournalExitAndFlock', 'busyAdoptedBackgroundRefused',
                  'atomicAdmissionClosed', 'parentEofAndBrokenAckSafe',
                  'invalidReplayAndInstanceBound', 'helperHandlesNotInherited',
                  'selfExecRetiresOwnership', 'unicodePathsClosedRuntime')
SYSTEM_DLLS = set(('ntdll kernel32 kernelbase user32 gdi32 gdi32full shell32 '
                  'advapi32 ole32 oleaut32 bcrypt bcryptprimitives crypt32 '
                  'ws2_32 wsock32 userenv dbghelp iphlpapi imm32 comdlg32 '
                  'comctl32 winmm version setupapi secur32 shlwapi rpcrt4 '
                  'msvcrt ucrtbase normaliz dnsapi netapi32 psapi wtsapi32 '
                  'winhttp wininet powrprof cfgmgr32 dwmapi uxtheme').split())


def need(ok, message):
    if not ok:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def unambiguous(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'duplicate JSON key')
        result[key] = value
    return result


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=unambiguous)


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n', encoding='utf-8')


def member(name):
    need(isinstance(name, str) and name and not re.search(r'[\\:<>"|?*\x00-\x1f\x7f]', name),
         'invalid member path')
    p = PurePosixPath(name)
    need(not p.is_absolute() and all(x not in ('', '.', '..') for x in name.split('/')),
         'invalid member path')
    need(all(not x.endswith(('.', ' ')) and not re.fullmatch(
        r'(?i)(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?', x) for x in p.parts),
        'Windows-ambiguous member path')
    return name


def allowed(name, data):
    member(name)
    parts = PurePosixPath(name).parts
    need(PurePosixPath(name).suffix.lower() not in FONT_EXT,
         'application font payload refused')
    need(not any(x.lower() in ('fonts', 'fontconfig', 'font-cache', 'glyph-cache',
                              '.git', '__pycache__') for x in parts),
         'cache/source directory refused')
    need(data[:4] not in (b'\x00\x01\x00\x00', b'OTTO', b'ttcf', b'wOFF', b'wOF2')
         and not data.startswith(b'STARTFONT'), 'font signature refused')
    need(not name.lower().endswith(('.h', '.c', '.env', '.pem', '.pfx', '.p12')),
         'source/private compile input refused')
    if PurePosixPath(name).suffix.lower() in ('.css', '.html', '.js'):
        need(not re.search(rb'berkeley[\s_-]*mono|@font-face', data, re.I),
             'unapproved application font selection refused')
    if name.endswith('.gz'):
        allowed(name[:-3], gzip.decompress(data))


def inventory(directory, exclude=(), portable=False):
    directory = Path(directory)
    need(directory.is_dir() and not directory.is_symlink(), 'missing regular directory')
    result, folded = {}, set()
    for path in sorted(directory.rglob('*')):
        attrs = getattr(path.lstat(), 'st_file_attributes', 0)
        need(not path.is_symlink() and not attrs & 0x400, 'symlink/reparse payload refused')
        if path.is_dir():
            continue
        need(path.is_file(), 'nonregular payload refused')
        name = member(path.relative_to(directory).as_posix())
        need(name.casefold() not in folded, 'case-colliding payload')
        folded.add(name.casefold())
        if name not in exclude:
            data = path.read_bytes()
            if not (portable and name == 'service.c.gz'):
                allowed(name, data)
            result[name] = {'sha256': digest(data), 'bytes': len(data)}
    return result


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def identity():
    need(not git('status', '--porcelain'), 'service source checkout must be clean')
    commit = git('rev-parse', 'HEAD')
    need(re.fullmatch('[0-9a-f]{40}', os.environ.get('BACKPLANE_FROZEN_COMMIT', ''))
         and os.environ['BACKPLANE_FROZEN_COMMIT'] == commit, 'full frozen commit mismatch')
    version_tag = os.environ.get('BACKPLANE_VERSION', '')
    version = version_tag.removeprefix('v')
    need(re.fullmatch(r'\d{1,4}\.\d{1,4}\.\d{1,4}(?:-nightly\.[0-9A-Za-z.]{1,24})?', version),
         'explicit stable/nightly service version required')
    stamp = os.environ.get('BACKPLANE_VERSION_STAMP', version).removeprefix('v')
    need(stamp == version, 'service version/stamp mismatch')
    channel = 'nightly' if '-nightly.' in version else 'release'
    need(os.environ.get('BACKPLANE_TELEMETRY_CHANNEL', channel) == channel,
         'service immutable channel mismatch')
    return dict(commit=commit, tree=git('rev-parse', 'HEAD^{tree}'),
                version=version, versionTag=version_tag, versionStamp=stamp,
                telemetry_channel=channel, target='windows-x64', entrypoint=ENTRY)


def check_inputs(directory):
    directory = Path(directory)
    source, web = load(directory / 'SOURCE.json'), load(directory / 'WEB.json')
    need(source.get('schema') == 3 and source.get('kind') == 'windows-service-emission',
         'genuine SOURCE3 service receipt required')
    for key, value in identity().items():
        need(source.get(key) == value, 'source identity mismatch: ' + key)
    pin = source.get('bend', {})
    need(set(pin) == {'version', 'archiveSha256', 'executableSha256'} and pin.get('version')
         and all(re.fullmatch('[0-9a-f]{64}', pin.get(n, '')) for n in ('archiveSha256', 'executableSha256')),
         'source compiler provenance missing')
    actual = inventory(directory, ('SOURCE.json',), portable=True)
    need(set(actual) == {'service.c.gz', 'WEB.json'} | {'web/' + n for n in web['members']},
         'undeclared portable input')
    need(source['inputs_sha256'] == {n: v['sha256'] for n, v in actual.items()},
         'portable input digest mismatch')
    need(source['service_c_sha256'] == digest(gzip.decompress((directory / 'service.c.gz').read_bytes())),
         'uncompressed service C mismatch')
    need(source['web_manifest_sha256'] == sha(directory / 'WEB.json'), 'web receipt mismatch')
    need(web.get('schema') == 1 and web.get('kind') == 'matching-generated-web'
         and web.get('entrypoint') == 'src/web/index.html'
         and web.get('sourceCommit') == source['commit']
         and web.get('sourceTree') == source['tree'], 'WEB1 source mismatch')
    need('index.html' in web['members'] and inventory(directory / 'web') == web['members'],
         'exact web member mismatch')
    for name in web['members']:
        if PurePosixPath(name).suffix in ('.js', '.css', '.html'):
            need(name + '.gz' in web['members'], 'missing web gzip sibling')
        if name.endswith('.gz'):
            need(name[:-3] in web['members'] and gzip.decompress((directory / 'web' / name).read_bytes())
                 == (directory / 'web' / name[:-3]).read_bytes(), 'stale or orphan web gzip')
    return source


def compiler_pin():
    archive = Path(os.environ.get('BACKPLANE_BEND_ARCHIVE', ''))
    expected = os.environ.get('BACKPLANE_BEND_ARCHIVE_SHA256', '')
    version = os.environ.get('BACKPLANE_BEND_VERSION', '')
    need(re.fullmatch('[0-9a-f]{64}', expected) and archive.is_file()
         and sha(archive) == expected and version, 'verified retained Bend archive required')
    exe = Path(shutil.which('bend') or '')
    need(exe.is_file(), 'bend executable missing')
    install = Path(os.environ.get('BACKPLANE_BEND_ROOT', str(Path.home() / '.bend')))
    checked = 0
    with tarfile.open(archive, 'r:gz') as tar:
        for info in tar:
            if info.isfile() and (info.name in ('bend/bin/bend', 'bend/bend2') or info.name.startswith('bend/bend2/')):
                relative = member(info.name[len('bend/'):])
                installed = install / relative
                need(installed.is_file() and digest(tar.extractfile(info).read()) == sha(installed),
                     'installed Bend does not match verified archive')
                if relative == 'bin/bend':
                    need(sha(exe) == sha(installed), 'active Bend launcher mismatch')
                checked += 1
    need(checked > 1, 'Bend archive compiler payload missing')
    reported = subprocess.check_output([str(exe), 'version'], text=True).strip()
    need(re.search(r'(?<![0-9.])' + re.escape(version) + r'(?![0-9.])', reported),
         'Bend compiler version mismatch')
    return {'version': version, 'archiveSha256': expected, 'executableSha256': sha(exe)}


def sidecar(path):
    Path(str(path) + '.sha256').write_text(sha(path) + '  ' + Path(path).name + '\n')


def emit(args):
    source = identity()
    pin = compiler_pin()
    out = Path(args.out).resolve()
    need(not out.exists(), 'emit output must be a fresh directory')
    out.mkdir(parents=True)
    stage = out / 'windows-service-inputs'
    stage.mkdir()
    env = dict(os.environ)
    for key in ('BACKPLANE_GOOGLE_CLIENT_ID', 'BACKPLANE_GOOGLE_CLIENT_SECRET',
                'BACKPLANE_TELEMETRY_URL', 'BACKPLANE_TELEMETRY_KID', 'BACKPLANE_TELEMETRY_KEY',
                'BACKPLANE_PREBUILT'):
        env.pop(key, None)
    env.update(BACKPLANE_GOOGLE_BAKE='0', BACKPLANE_TELEMETRY_BAKE='0',
               BACKPLANE_EMIT_ONLY='1', BACKPLANE_LOW_MEM='1',
               BACKPLANE_JOBS='1', BACKPLANE_VERSION_STAMP=source['versionStamp'])
    subprocess.run(['bash', 'scripts/build-app.sh', ENTRY, 'build/backplane-service-emission.exe'],
                   cwd=ROOT, env=env, check=True)
    c = ROOT / 'build/cc/backplane-service-emission.exe/all.c'
    with c.open('rb') as src, (stage / 'service.c.gz').open('wb') as dest:
        with gzip.GzipFile(filename='', mode='wb', fileobj=dest, mtime=0) as compressed:
            shutil.copyfileobj(src, compressed)
    subprocess.run(['bash', '-c', '. scripts/bendok.sh; bend_check src/web/app.bend'],
                   cwd=ROOT, env=env, check=True)
    subprocess.run(['bend', 'src/web/index.html', '-o', str(stage / 'web')],
                   cwd=ROOT, env=env, check=True)
    js = sorted(str(p) for p in (stage / 'web').glob('chunk-*.js'))
    need(js, 'generated web JavaScript missing')
    subprocess.run([sys.executable, 'scripts/js-unmarshal.py', '../core/client.Ui', *js], cwd=ROOT, check=True, env=env)
    subprocess.run([sys.executable, 'scripts/js-native.py', *js], cwd=ROOT, check=True, env=env)
    shutil.copyfile(ROOT / 'src/web/sw.js', stage / 'web/sw.js')
    for p in list((stage / 'web').rglob('*')):
        if p.is_file() and p.suffix in ('.js', '.css', '.html'):
            with p.open('rb') as src, Path(str(p) + '.gz').open('wb') as dest:
                with gzip.GzipFile(filename='', mode='wb', fileobj=dest, mtime=0) as gz:
                    shutil.copyfileobj(src, gz)
    write(stage / 'WEB.json', {'schema': 1, 'kind': 'matching-generated-web',
          'sourceCommit': source['commit'], 'sourceTree': source['tree'],
          'entrypoint': 'src/web/index.html', 'members': inventory(stage / 'web')})
    source.update(schema=3, kind='windows-service-emission', bend=pin,
                  inputs_sha256={n: v['sha256'] for n, v in inventory(stage, portable=True).items()},
                  service_c_sha256=sha(c), web_manifest_sha256=sha(stage / 'WEB.json'))
    write(stage / 'SOURCE.json', source)
    check_inputs(stage)
    archive = out / INPUT_ARCHIVE
    with tarfile.open(archive, 'w:gz') as tar:
        for name in ['SOURCE.json', *source['inputs_sha256']]:
            tar.add(stage / name, arcname='windows-service-inputs/' + name, recursive=False)
    sidecar(archive)
    shutil.copyfile(stage / 'SOURCE.json', out / 'SOURCE.json')
    print(archive)


def import_inputs(archive, expected, destination):
    need(re.fullmatch('[0-9a-f]{64}', expected) and sha(archive) == expected,
         'portable archive digest mismatch')
    destination = Path(destination)
    need(not destination.exists(), 'input destination must be fresh')
    destination.mkdir(parents=True)
    with tarfile.open(archive, 'r:gz') as tar:
        seen = set()
        for info in tar:
            need(info.isfile(), 'portable archive must contain regular files only')
            name = member(info.name)
            need(name.startswith('windows-service-inputs/'), 'portable archive root mismatch')
            name = member(name[len('windows-service-inputs/'):])
            need(name.casefold() not in seen, 'duplicate archive member')
            seen.add(name.casefold())
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with tar.extractfile(info) as src, target.open('xb') as dest:
                shutil.copyfileobj(src, dest)
    return check_inputs(destination)


def pe(data):
    def unpack(fmt, at):
        need(0 <= at <= len(data)-struct.calcsize(fmt), 'truncated PE data')
        return struct.unpack_from(fmt, data, at)
    need(data[:2] == b'MZ', 'expected PE')
    at, = unpack('<I', 0x3c)
    need(data[at:at+4] == b'PE\0\0', 'invalid PE signature')
    machine, count = unpack('<HH', at+4)
    length, = unpack('<H', at+20)
    opt = at + 24
    need(machine == 0x8664 and length >= 240 and 1 <= count <= 96
         and opt+length+count*40 <= len(data) and unpack('<H', opt)[0] == 0x20b,
         'AMD64 PE32+ required')
    sections = []
    for i in range(count):
        vs, va, size, raw = unpack('<IIII', opt+length+40*i+8)
        sections.append((va, size, raw))
    def off(rva):
        for va, size, raw in sections:
            if va <= rva < va+size:
                return raw+rva-va
        need(rva < unpack('<I', opt+60)[0], 'PE RVA outside file-backed data')
        return rva
    def string(rva):
        start = off(rva)
        return data[start:data.index(b'\0', start)].decode('ascii')
    result = {'machine': '0x8664', 'sha256': digest(data), 'bytes': len(data), 'imports': [], 'delayImports': []}
    for index, width, fmt, field, key in ((1, 20, '<IIIII', 3, 'imports'), (13, 32, '<IIIIIIII', 1, 'delayImports')):
        rva, size = unpack('<II', opt+112+index*8)
        if not rva:
            continue
        for n in range(min(size // width, 4096)):
            row = unpack(fmt, off(rva)+width*n)
            if not any(row):
                break
            name = row[field]
            if index == 13 and not row[0] & 1:
                name -= unpack('<Q', opt+24)[0]
            dll = string(name)
            need(re.fullmatch(r'[A-Za-z0-9_.-]+\.dll', dll, re.I), 'invalid imported DLL name')
            result[key].append(dll)
        else:
            raise ValueError('unterminated PE import directory')
    return result


def runtime_aliases(members):
    inventory_rows, packages = [], {}
    for name, item in sorted(members.items()):
        row = {k: item[k] for k in ('sha256', 'bytes', 'package', 'version', 'architecture')}
        inventory_rows.append({'path': name, **row})
        disposition = json.dumps(item['sourceDisposition'], sort_keys=True)
        key = (item['package'], item['version'], item['architecture'], disposition)
        package = packages.setdefault(key, {'name': item['package'], 'version': item['version'],
            'architecture': item['architecture'], 'sourceDisposition': disposition, 'licenses': []})
        for notice in item['notices']:
            entry = {'path': notice, 'sha256': members[notice]['sha256']}
            if entry not in package['licenses']:
                package['licenses'].append(entry)
    return inventory_rows, list(packages.values())


def record_runtime(args):
    directory = Path(args.payload)
    need(not (directory / 'RUNTIME.json').exists(), 'runtime manifest already exists')
    description = load(args.description)
    actual = inventory(directory)
    need(set(actual) == set(description['members']), 'runtime description must explicitly list every member')
    for name, value in actual.items():
        item = description['members'][name]
        for field, data in value.items():
            need(field not in item or item[field] == data, 'runtime description digest mismatch')
        item.update(value)
    rows, packages = runtime_aliases(description['members'])
    description.update(schema=1, target='windows-x64', inventory=rows, packages=packages)
    partial = directory / '.RUNTIME.partial.json'
    need(not partial.exists(), 'partial runtime manifest already exists')
    write(partial, description)
    # This records bytes, never supplies root approval. Native producer still
    # requires the separately approved exact manifest SHA and complete policy.
    runtime_payload(directory, sha(partial), manifest_name=partial.name)
    partial.rename(directory / 'RUNTIME.json')
    print('RUNTIME_MANIFEST_RECORDED_ROOT_APPROVAL_AND_NATIVE_ACCEPTANCE_REQUIRED', sha(directory / 'RUNTIME.json'))


def runtime_payload(directory, expected, manifest_name='RUNTIME.json'):
    directory = Path(directory)
    path = directory / manifest_name
    need(re.fullmatch('[0-9a-f]{64}', expected) and sha(path) == expected,
         'approved runtime manifest digest mismatch')
    receipt = load(path)
    actual = inventory(directory, (manifest_name,))
    return check_runtime(receipt, actual)


def check_runtime(receipt, actual):
    need(receipt.get('schema') == 1 and receipt.get('target') == 'windows-x64'
         and receipt.get('dynamicInventoryComplete') is True, 'approved complete runtime inventory required')
    need(isinstance(receipt.get('helpers'), dict) and all(
        isinstance(n, str) and '/' not in n and n.lower().endswith('.exe')
        and n.lower() != 'backplane-serve.exe' for n in receipt['helpers'].values()),
        'explicit sibling helper roles required')
    need(set(actual) == set(receipt['members']), 'runtime inventory member mismatch')
    for name, value in actual.items():
        item = receipt['members'][name]
        need(item.get('sha256') == value['sha256'] and item.get('bytes') == value['bytes'],
             'runtime member digest mismatch')
        need(all(item.get(k) for k in ('package', 'version', 'license', 'sourceDisposition'))
             and item.get('architecture') == 'x64',
             'runtime package/license/source disposition missing')
        disposition = item['sourceDisposition']
        need(isinstance(disposition, dict) and disposition.get('mode') in ('none-required', 'corresponding-source'),
             'explicit runtime source obligation required')
        if disposition['mode'] == 'corresponding-source':
            need(isinstance(disposition.get('url'), str) and disposition['url'].startswith('https://')
                 and re.fullmatch('[0-9a-f]{64}', disposition.get('sha256', '')),
                 'corresponding source archive identity missing')
        need(item.get('notices') and all(n in actual for n in item['notices']),
             'runtime notice member missing')
        need(name.startswith(('runtime/', 'licenses/')) or name in receipt.get('helpers', {}).values(),
             'undeclared runtime/helper role')
    need(all(n in actual for n in ('runtime/bin/cygwin1.dll', 'runtime/bin/cygpath.exe', 'runtime/bin/sh.exe')),
         'private Cygwin runtime/path/shell tools missing')
    need(isinstance(receipt.get('dynamicDependencies'), list), 'dynamic dependency inventory missing')
    rows, packages = runtime_aliases(receipt['members'])
    need(receipt.get('inventory') == rows and receipt.get('packages') == packages,
         'runtime inventory/notices aliases disagree with member records')
    return receipt


def closure(files, runtime):
    binaries = {n: pe(data) for n, data in files.items()
                if data[:2] == b'MZ' or n.lower().endswith(('.exe', '.dll'))}
    dlls = {}
    for name in binaries:
        if name.lower().endswith('.dll'):
            need(str(PurePosixPath(name).parent) == 'runtime/bin', 'DLL outside closed runtime/bin')
            base = PurePosixPath(name).name.lower()
            need(base not in dlls, 'ambiguous DLL basename')
            dlls[base] = name
    system = set(runtime.get('systemDlls', []))
    need(all(n == n.lower() and (n.removesuffix('.dll') in SYSTEM_DLLS
         or re.fullmatch(r'(api|ext)-ms-win-[a-z0-9.-]+\.dll', n)) for n in system),
         'unapproved system DLL classification')
    edges = []
    for name, binary in binaries.items():
        for mode in ('imports', 'delayImports'):
            for dep in binary[mode]:
                target = dlls.get(dep.lower())
                need(target is not None or dep.lower() in system, 'unresolved DLL import: ' + dep)
                edges.append({'from': name, 'import': dep, 'mode': mode,
                              'kind': 'normal' if mode == 'imports' else 'delay', 'name': dep,
                              'to': target, 'resolved': target, 'system': target is None,
                              'classification': 'approved-system' if target is None else 'resolved'})
    for item in runtime['dynamicDependencies']:
        need(item.get('reason') and (item.get('member') in files or
             item.get('optionalExternal') is True), 'unresolved dynamic dependency')
        if item.get('optionalExternal') is not True:
            need(item.get('from') in files and isinstance(item.get('name'), str)
                 and item['name'], 'dynamic dependency source/name missing')
            edges.append({'from': item['from'], 'name': item['name'], 'kind': 'dynamic',
                          'resolved': item['member'], 'system': False, 'classification': 'resolved',
                          'evidence': 'approved-runtime-declaration'})
    return {'schema': 1, 'kind': 'windows-service-static-dependency-closure',
            'target': 'windows-x64', 'staticStatus': 'complete', 'status': 'PASS', 'measured': True,
            'scope': 'static-import-resolution-only-approved-dynamic-inventory',
            'unresolvedMandatory': [],
            'runtimeAcceptance': 'pending', 'binaries': binaries, 'edges': edges,
            'dynamicDependencies': runtime['dynamicDependencies']}


def bake_inputs():
    result = {}
    for label, names in (('google', ('BACKPLANE_GOOGLE_CLIENT_ID', 'BACKPLANE_GOOGLE_CLIENT_SECRET')),
                         ('telemetry', ('BACKPLANE_TELEMETRY_URL', 'BACKPLANE_TELEMETRY_KID', 'BACKPLANE_TELEMETRY_KEY'))):
        need(os.environ.get('BACKPLANE_' + label.upper() + '_BAKE') == '1',
             'protected native bake must explicitly be enabled: ' + label)
        need(all(os.environ.get(n, '').strip() == os.environ.get(n, '') and os.environ.get(n)
                 and not re.search(r'\s', os.environ[n]) for n in names),
             'protected native bake inputs missing/invalid: ' + label)
        result[label] = {'requested': True, 'requiredInputsPresent': True}
    need(os.environ['BACKPLANE_TELEMETRY_URL'] == TELEMETRY_ENDPOINT,
         'approved public telemetry endpoint required')
    result['telemetry']['endpoint'] = os.environ['BACKPLANE_TELEMETRY_URL']
    # Validate with the same header generators used by the actual compiler.
    # The private directory and headers are removed on both success and error.
    with tempfile.TemporaryDirectory(prefix='bp-service-private-') as temp:
        os.chmod(temp, 0o700)
        for name in ('google', 'telemetry'):
            subprocess.run([sys.executable, str(ROOT / 'scripts' / (name + '-header.py')),
                            str(Path(temp) / (name + '.h'))], check=True)
    return result


def execution_tools_identity():
    # Product identity is checked independently by identity(). The metadata
    # checkout must also be clean, and its actual tools are named explicitly.
    def tool_git(*args):
        return subprocess.check_output(['git', *args], cwd=TOOLS_ROOT, text=True).strip()
    need(not tool_git('status', '--porcelain'), 'execution tool checkout must be clean')
    return {'schema': 1, 'metadataCommit': tool_git('rev-parse', 'HEAD'),
            'metadataTree': tool_git('rev-parse', 'HEAD^{tree}'),
            'toolsSha256': {name: sha(TOOLS_ROOT / name) for name in (
                'scripts/release-bootstrap.py', 'scripts/windows-release-request.py',
                'scripts/windows-service.py', 'scripts/build-windows.sh', 'scripts/windows-runtime.py')},
            'productToolsSha256': {name: sha(ROOT / name) for name in (
                'scripts/google-header.py', 'scripts/telemetry-header.py', 'scripts/cc-split.py')}}


def native(args):
    need(sys.platform == 'cygwin', 'native service compile requires Windows Cygwin')
    identity()
    execution = execution_tools_identity()
    need(not Path(args.out).exists(), 'native output directory must be fresh')
    runtime_payload(args.runtime_payload, args.runtime_manifest_sha256)
    bakes = bake_inputs()
    compiler = Path(shutil.which(os.environ.get('CC', 'clang')) or '').resolve()
    need(compiler.is_file(), 'native compiler missing')
    target = subprocess.check_output([str(compiler), '-dumpmachine'], text=True).strip()
    reported = subprocess.check_output([str(compiler), '--version'], text=True).strip()
    clang = re.search(r'\bclang version (\d+)\.', reported)
    need(target.startswith('x86_64-') and ('cygwin' in target or 'cygnus' in target)
         and clang and int(clang.group(1)) >= 19, 'AMD64 Cygwin clang19+ required')
    flags = os.environ.get('BACKPLANE_CFLAGS') or '-O2'
    need(all(x in ('-O0', '-O1', '-O2', '-O3', '-Os', '-Oz', '-g',
                   '-gline-tables-only', '-fno-omit-frame-pointer') for x in flags.split()),
         'native flags outside nonsecret service allowlist')
    out = Path(args.out).resolve()
    source = import_inputs(args.inputs, args.sha256, out / 'inputs')
    with gzip.open(out / 'inputs/service.c.gz', 'rb') as src, (out / 'service.c').open('wb') as dest:
        shutil.copyfileobj(src, dest)
    env = dict(os.environ, BACKPLANE_VERSION_STAMP=source['versionStamp'], BACKPLANE_CFLAGS=flags,
               BP_WIN_SOURCE_ROOT=str(ROOT))
    subprocess.run(['bash', str(TOOLS_ROOT / 'scripts/build-windows.sh'), str(out / 'service.c'),
                    str(out / 'backplane-serve.exe')], cwd=ROOT, env=env, check=True)
    need(execution_tools_identity() == execution, 'execution tools changed during native compile')
    identity()
    adapted = out / 'backplane-serve.cc/runtime.c'
    adapter = load(adapted.with_name('RUNTIME-ADAPTER.json'))
    need(adapter == {'schema': 1,
         'adapterSha256': execution['toolsSha256']['scripts/windows-runtime.py'],
         'sourceCsha256': source['service_c_sha256'], 'transformedCsha256': sha(adapted)},
         'actual runtime adapter/C witness mismatch')
    execution['runtimeAdapter'] = adapter
    binary = pe((out / 'backplane-serve.exe').read_bytes())
    shutil.copyfile(out / 'backplane-serve.exe', out / 'unsigned-service.exe')
    write(out / 'COMPILE.json', {'schema': 1, 'sourceReceiptSha256': sha(out / 'inputs/SOURCE.json'),
          'unsignedServiceSha256': binary['sha256'], 'producerExecution': execution,
          'runtimeManifestSha256': args.runtime_manifest_sha256,
          'compiler': {'version': reported.splitlines()[0],
                       'target': target, 'sha256': sha(compiler), 'flags': flags},
          'compileInputs': {'version': source['version'], 'versionStamp': source['versionStamp'],
                            'telemetryChannel': source['telemetry_channel'], **bakes}})
    print(out / 'COMPILE.json')


def signing(service, payload, compile_receipt, policy, thumbprint):
    unsigned = service.with_name('unsigned-service.exe')
    need(sha(unsigned) == compile_receipt['unsignedServiceSha256'], 'unsigned service receipt mismatch')
    if policy in ('unsigned-internal', 'unsigned-portable-allowed'):
        need(sha(service) == compile_receipt['unsignedServiceSha256'], 'compiled service changed')
        return {'policy': policy, 'signed': False, 'publicEligible': False,
                'validation': ('root-portable-policy-runtime-gates-pending'
                               if policy == 'unsigned-portable-allowed' else 'not-signed')}
    need(sys.platform == 'cygwin' and re.fullmatch('[0-9A-Fa-f]{40}', thumbprint or ''),
         'Authenticode requires Windows and approved certificate thumbprint')
    original, signed = bytearray(unsigned.read_bytes()), bytearray(service.read_bytes())
    opt = struct.unpack_from('<I', original, 0x3c)[0] + 24
    need(struct.unpack_from('<II', original, opt+112+4*8) == (0, 0),
         'unsigned reference contains a certificate')
    cert_at, cert_size = struct.unpack_from('<II', signed, opt+112+4*8)
    need(cert_size > 0 and cert_at + cert_size == len(signed)
         and len(original) <= cert_at <= len(original)+7,
         'signed service layout differs from compiled service')
    for start, size in ((opt+64, 4), (opt+112+4*8, 8)):
        original[start:start+size] = bytes(size)
        signed[start:start+size] = bytes(size)
    need(signed[:len(original)] == original and not any(signed[len(original):cert_at]),
         'signed service content differs from compiled service')
    results = {}
    command = ('$s=Get-AuthenticodeSignature -LiteralPath $env:BP_SERVICE_SIGN_FILE;'
               '@{status=[string]$s.Status;thumbprint=[string]$s.SignerCertificate.Thumbprint}'
               '|ConvertTo-Json -Compress')
    for name, path in [('backplane-serve.exe', service), *payload]:
        cygpath = Path(sys.executable).resolve().parent / 'cygpath.exe'
        need(cygpath.is_file(), 'compiler-runtime cygpath unavailable for signature observation')
        native_path = subprocess.check_output([str(cygpath), '-w', str(path)], text=True).strip()
        raw = subprocess.check_output(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', command],
                                      env={**os.environ, 'BP_SERVICE_SIGN_FILE': native_path}, text=True)
        info = json.loads(raw)
        need(info.get('status') == 'Valid' and info.get('thumbprint', '').lower() == thumbprint.lower(),
             'Authenticode verification failed')
        results[name] = {'sha256': sha(path), 'status': 'Valid', 'certificateThumbprint': thumbprint.upper()}
    return {'policy': policy, 'publicEligible': False, 'validation': 'signature-only-product-gates-pending', 'files': results}


def managed_control(data, source, service_sha, runtime_sha):
    if data is None:
        return {'status': 'UNSUPPORTED', 'protocol': None, 'validationReceipt': None,
                'validationReceiptSha256': None}
    receipt = json.loads(data, object_pairs_hook=unambiguous)
    need(receipt.get('schema') == 1 and receipt.get('kind') == 'backplane-managed-service-control-acceptance'
         and receipt.get('status') == 'PASS' and receipt.get('target') == 'windows-x64'
         and receipt.get('protocol') == 1, 'actual Windows managed-control acceptance required')
    for key, value in {'commit': source['commit'], 'tree': source['tree'],
                       'version': source['version'], 'serviceSha256': service_sha,
                       'runtimeManifestSha256': runtime_sha}.items():
        need(receipt.get(key) == value, 'managed-control artifact identity mismatch')
    need(set(receipt.get('checks', {})) == set(CONTROL_CHECKS)
         and all(receipt['checks'][n] is True for n in CONTROL_CHECKS),
         'managed-control criteria incomplete')
    return {'status': 'IMPLEMENTED', 'protocol': 1, 'validationReceipt': 'MANAGED-CONTROL.json',
            'validationReceiptSha256': digest(data)}


def package(args):
    native_dir = Path(args.native_dir)
    source = check_inputs(native_dir / 'inputs')
    compile_info = load(native_dir / 'COMPILE.json')
    need(compile_info.get('schema') == 1, 'native compile receipt required')
    need(compile_info['sourceReceiptSha256'] == sha(native_dir / 'inputs/SOURCE.json'),
         'compile/source mismatch')
    need(compile_info['runtimeManifestSha256'] == args.runtime_manifest_sha256,
         'compile/runtime manifest mismatch')
    need(compile_info['compileInputs'] == {
        'version': source['version'], 'versionStamp': source['versionStamp'],
        'telemetryChannel': source['telemetry_channel'],
        'google': {'requested': True, 'requiredInputsPresent': True},
        'telemetry': {'requested': True, 'requiredInputsPresent': True, 'endpoint': TELEMETRY_ENDPOINT}},
        'protected compile/source tuple mismatch')
    runtime = runtime_payload(args.runtime_payload, args.runtime_manifest_sha256)
    payload = Path(args.runtime_payload)
    service = native_dir / 'backplane-serve.exe'
    signed = signing(service, [(n, payload / n) for n in runtime.get('helpers', {}).values()],
                     compile_info, args.signing_policy, args.signing_thumbprint)
    files = {'backplane-serve.exe': service.read_bytes(),
             'SOURCE.json': (native_dir / 'inputs/SOURCE.json').read_bytes(),
             'WEB.json': (native_dir / 'inputs/WEB.json').read_bytes(),
             'LICENSE.Backplane': (ROOT / 'LICENSE').read_bytes(),
             'RUNTIME.json': (payload / 'RUNTIME.json').read_bytes()}
    for name in load(native_dir / 'inputs/WEB.json')['members']:
        files['web/' + name] = (native_dir / 'inputs/web' / name).read_bytes()
    for name in runtime['members']:
        need(name not in files, 'runtime collides with service resource')
        files[name] = (payload / name).read_bytes()
    control_data = None
    if args.managed_control_receipt or args.managed_control_sha256:
        need(args.managed_control_receipt and re.fullmatch('[0-9a-f]{64}', args.managed_control_sha256 or ''),
             'managed-control receipt and trusted digest must be supplied together')
        control_data = Path(args.managed_control_receipt).read_bytes()
        need(digest(control_data) == args.managed_control_sha256, 'managed-control receipt digest mismatch')
        files['MANAGED-CONTROL.json'] = control_data
    control = managed_control(control_data, source, digest(files['backplane-serve.exe']), args.runtime_manifest_sha256)
    closed = closure(files, runtime)
    files['CLOSURE.json'] = (json.dumps(closed, sort_keys=True, indent=2) + '\n').encode()
    for name, data in files.items():
        allowed(name, data)
    build = {'schema': 3, 'kind': 'windows-service-resources',
             'commit': source['commit'], 'tree': source['tree'], 'entrypoint': ENTRY,
             'target': 'windows-x64', 'serviceVersion': source['version'],
             'versionStamp': source['versionStamp'], 'telemetryChannel': source['telemetry_channel'],
             'sourceReceiptSha256': digest(files['SOURCE.json']),
             'webManifestSha256': digest(files['WEB.json']),
             'runtimeManifestSha256': digest(files['RUNTIME.json']),
             'closureSha256': digest(files['CLOSURE.json']),
             'roles': {'service': 'backplane-serve.exe', 'runtimeBin': 'runtime/bin',
                       'web': 'web', 'helpers': runtime.get('helpers', {})},
             'sha256': {n: digest(b) for n, b in files.items()},
             'sizes': {n: len(b) for n, b in files.items()}, 'pe': closed['binaries'],
             'compiler': compile_info['compiler'], 'compileInputs': compile_info['compileInputs'],
             'unsignedServiceSha256': compile_info['unsignedServiceSha256'],
             'producerExecution': compile_info['producerExecution'],
             'signing': signed, 'managedControl': control,
             'validation': {'staticClosure': 'complete', 'cleanWindowsProduct': 'pending',
                            'bakedIngestion': 'pending', 'lifecycle': 'pending', 'publication': 'not-authorized'}}
    files['BUILD.json'] = (json.dumps(build, sort_keys=True, indent=2) + '\n').encode()
    out = Path(args.out)
    need(not out.exists(), 'resource output directory must be fresh')
    out.mkdir(parents=True)
    archive = out / RESOURCE_ARCHIVE
    partial = out / '.resources.partial.zip'
    with zipfile.ZipFile(partial, 'x', zipfile.ZIP_DEFLATED) as z:
        for name, data in sorted(files.items()):
            z.writestr('backplane-service/' + name, data)
    verify_resources(partial, sha(partial))
    partial.rename(archive)
    sidecar(archive)
    (out / 'SOURCE.json').write_bytes(files['SOURCE.json'])
    (out / 'BUILD.json').write_bytes(files['BUILD.json'])
    print(archive)


def verify_resources(archive, expected):
    need(re.fullmatch('[0-9a-f]{64}', expected) and sha(archive) == expected,
         'resource ZIP digest mismatch')
    with zipfile.ZipFile(archive) as z:
        files, seen = {}, set()
        for info in z.infolist():
            name = member(info.filename)
            need(name.startswith('backplane-service/') and not info.is_dir(), 'resource archive root/type mismatch')
            name = member(name[len('backplane-service/'):])
            mode = info.external_attr >> 16
            need(stat.S_IFMT(mode) in (0, stat.S_IFREG) and not info.external_attr & 0x400
                 and name.casefold() not in seen, 'archive alias/nonregular/duplicate refused')
            seen.add(name.casefold())
            files[name] = z.read(info)
            allowed(name, files[name])
    def decoded(name):
        return json.loads(files[name], object_pairs_hook=unambiguous)
    build, source, web, runtime = (decoded(n) for n in ('BUILD.json', 'SOURCE.json', 'WEB.json', 'RUNTIME.json'))
    need(build.get('schema') == 3 and build.get('kind') == 'windows-service-resources'
         and source.get('schema') == 3 and source.get('kind') == 'windows-service-emission', 'service receipt schemas required')
    need(runtime.get('schema') == 1 and runtime.get('target') == 'windows-x64'
         and runtime.get('dynamicInventoryComplete') is True,
         'resource runtime inventory incomplete')
    check_runtime(runtime, {n: {'sha256': digest(files[n]), 'bytes': len(files[n])}
                            for n in runtime['members']})
    for key, value in identity().items():
        need(source.get(key) == value, 'resource source mismatch: ' + key)
    need(build['commit'] == source['commit'] and build['tree'] == source['tree']
         and build['entrypoint'] == ENTRY and build['target'] == 'windows-x64'
         and build['serviceVersion'] == source['version']
         and build['versionStamp'] == source['versionStamp']
         and build['telemetryChannel'] == source['telemetry_channel'], 'BUILD/SOURCE identity mismatch')
    need(build['compileInputs'] == {
        'version': source['version'], 'versionStamp': source['versionStamp'],
        'telemetryChannel': source['telemetry_channel'],
        'google': {'requested': True, 'requiredInputsPresent': True},
        'telemetry': {'requested': True, 'requiredInputsPresent': True, 'endpoint': TELEMETRY_ENDPOINT}},
        'resource protected compile/source tuple mismatch')
    execution = build.get('producerExecution', {})
    adapter = execution.get('runtimeAdapter', {})
    need(execution.get('schema') == 1 and all(re.fullmatch('[0-9a-f]{40}', execution.get(n, ''))
         for n in ('metadataCommit', 'metadataTree')) and adapter.get('schema') == 1
         and adapter.get('sourceCsha256') == source['service_c_sha256']
         and re.fullmatch('[0-9a-f]{64}', adapter.get('transformedCsha256', ''))
         and adapter.get('adapterSha256') == execution.get('toolsSha256', {}).get('scripts/windows-runtime.py'),
         'resource execution tools/adapter provenance missing')
    other = {n: b for n, b in files.items() if n != 'BUILD.json'}
    need(build['sha256'] == {n: digest(b) for n, b in other.items()}
         and build['sizes'] == {n: len(b) for n, b in other.items()}, 'resource member manifest mismatch')
    need(build['sourceReceiptSha256'] == digest(files['SOURCE.json'])
         and build['webManifestSha256'] == digest(files['WEB.json']) == source['web_manifest_sha256']
         and build['runtimeManifestSha256'] == digest(files['RUNTIME.json'])
         and build['closureSha256'] == digest(files['CLOSURE.json']), 'resource receipt hash mismatch')
    need(web.get('schema') == 1 and web.get('sourceCommit') == source['commit']
         and web.get('sourceTree') == source['tree'] and 'index.html' in web['members'], 'web source mismatch')
    required = {'BUILD.json', 'SOURCE.json', 'WEB.json', 'RUNTIME.json', 'CLOSURE.json',
                'LICENSE.Backplane', 'backplane-serve.exe'}
    if 'MANAGED-CONTROL.json' in files:
        required.add('MANAGED-CONTROL.json')
    need(set(files) == required | set(runtime['members']) | {'web/' + n for n in web['members']},
         'undeclared resource member')
    need(build['roles'] == {'service': 'backplane-serve.exe', 'runtimeBin': 'runtime/bin',
                           'web': 'web', 'helpers': runtime.get('helpers', {})}, 'resource role mismatch')
    for name, item in runtime['members'].items():
        need(digest(files[name]) == item['sha256'] and len(files[name]) == item['bytes'],
             'runtime resource identity mismatch')
    need(build['managedControl'] == managed_control(files.get('MANAGED-CONTROL.json'), source,
         digest(files['backplane-serve.exe']), digest(files['RUNTIME.json'])),
         'managed-control receipt/advertisement mismatch')
    need({n[4:]: {'sha256': digest(b), 'bytes': len(b)} for n, b in files.items()
          if n.startswith('web/')} == web['members'], 'resource web membership mismatch')
    for name in web['members']:
        if PurePosixPath(name).suffix in ('.js', '.css', '.html'):
            need(name + '.gz' in web['members'], 'resource missing web gzip sibling')
        if name.endswith('.gz'):
            need(name[:-3] in web['members'] and gzip.decompress(files['web/' + name])
                 == files['web/' + name[:-3]], 'resource gzip mismatch')
    need(closure(files, runtime) == decoded('CLOSURE.json') and build['pe'] == decoded('CLOSURE.json')['binaries'],
         'PE/closure mismatch')
    print('WINDOWS_SERVICE_RESOURCE_STATIC_IDENTITY_PASS_RUNTIME_ACCEPTANCE_PENDING')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('emit'); p.add_argument('--out', required=True)
    p = sub.add_parser('record-runtime')
    p.add_argument('--payload', required=True); p.add_argument('--description', required=True)
    p = sub.add_parser('check-inputs'); p.add_argument('--directory', required=True)
    p = sub.add_parser('native')
    p.add_argument('--inputs', required=True); p.add_argument('--sha256', required=True)
    p.add_argument('--runtime-payload', required=True); p.add_argument('--runtime-manifest-sha256', required=True)
    p.add_argument('--out', required=True)
    p = sub.add_parser('package')
    p.add_argument('--native-dir', required=True); p.add_argument('--runtime-payload', required=True)
    p.add_argument('--runtime-manifest-sha256', required=True); p.add_argument('--out', required=True)
    p.add_argument('--signing-policy', required=True, choices=('unsigned-internal', 'unsigned-portable-allowed', 'authenticode'))
    p.add_argument('--signing-thumbprint')
    p.add_argument('--managed-control-receipt'); p.add_argument('--managed-control-sha256')
    p = sub.add_parser('verify-resources')
    p.add_argument('--archive', required=True); p.add_argument('--sha256', required=True)
    args = parser.parse_args(argv)
    if args.command == 'emit': emit(args)
    elif args.command == 'record-runtime': record_runtime(args)
    elif args.command == 'check-inputs':
        check_inputs(args.directory); print('WINDOWS_SERVICE_SOURCE3_WEB1_INPUTS_MATCH')
    elif args.command == 'native': native(args)
    elif args.command == 'package': package(args)
    elif args.command == 'verify-resources': verify_resources(args.archive, args.sha256)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, EOFError, struct.error, subprocess.SubprocessError) as error:
        # No configuration values or captured child output in failure messages.
        sys.exit('windows-service: ' + (str(error) if isinstance(error, ValueError) else type(error).__name__))
