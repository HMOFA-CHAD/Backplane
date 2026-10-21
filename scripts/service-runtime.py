#!/usr/bin/env python3
"""Measure a matching Unix host's system ABI, then assemble an existing native BUILD."""
import argparse
import ctypes
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import sys


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def target_host():
    return {('Linux', 'x86_64'): 'linux-x64', ('Linux', 'aarch64'): 'linux-arm64',
            ('Darwin', 'arm64'): 'darwin-arm64'}.get((platform.system(), platform.machine()))


class Capture:
    def __init__(self, root):
        self.root, self.calls = root, []

    def __call__(self, argv):
        # No inherited loader injection, protected bake variables or user tool config.
        env = {k: v for k, v in os.environ.items() if not k.startswith(
            ('LD_', 'DYLD_', 'BACKPLANE_GOOGLE_', 'BACKPLANE_TELEMETRY_'))}
        env.update(LC_ALL='C', LANG='C')
        p = Path(argv[0]).resolve(strict=True)
        result = subprocess.run([str(x) for x in argv], stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, timeout=30, close_fds=True)
        text = result.stdout.decode('utf-8', errors='strict')
        name = 'operation-' + str(len(self.calls)) + '.log'
        (self.root/name).write_text(text)
        self.calls.append({'argv': [str(x) for x in argv], 'exit': result.returncode,
            'tool': {'path': str(p), 'sha256': sha(p), 'bytes': p.stat().st_size}, 'log': name})
        require(result.returncode == 0, 'Dependency measurement failed: ' + name)
        return text


def elf_needed(text):
    require(not re.search(r'\((?:RPATH|RUNPATH|AUDIT|DEPAUDIT|FILTER|AUXILIARY)\)', text),
            'ELF search paths or injected loader dependencies unsupported')
    return re.findall(r'\(NEEDED\).*?\[([^\]]+)\]', text)


def elf_resolved(text):
    result = {}
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        if re.fullmatch(r'linux-vdso\.so\.1 \(0x[0-9a-f]+\)', line):
            continue  # kernel virtual mapping; not a library file
        m = re.fullmatch(r'([^ ]+) => (/[^ ]+) \(0x[0-9a-f]+\)', line)
        if m:
            require(m[1] not in result, 'Duplicate loader resolution')
            result[m[1]] = m[2]
            continue
        m = re.fullmatch(r'(/[^ ]+) \(0x[0-9a-f]+\)', line)
        require(m is not None, 'Unresolved or unexpected ELF loader output')
        result[Path(m[1]).name] = m[1]
    return result


def no_loader_imports(symbols):
    require(not re.search(r'\b_?(?:dlopen|dlmopen|dlsym|dlvsym|__libc_dlopen_mode)(?:@|\b)', symbols),
            'Runtime loading API requires a separately measured dynamic closure')


def linux_measure(binary, target, capture):
    loader_name = 'ld-linux-x86-64.so.2' if target == 'linux-x64' else 'ld-linux-aarch64.so.1'
    program = capture(['/usr/bin/readelf', '--program-headers', '--wide', binary])
    interpreters = re.findall(r'Requesting program interpreter: ([^\]]+)\]', program)
    require(len(interpreters) == 1 and Path(interpreters[0]).name == loader_name, 'Unexpected ELF interpreter')
    loader = Path(interpreters[0])
    require(loader.is_absolute() and str(loader.resolve()).startswith(('/usr/lib/', '/lib/')), 'Foreign ELF interpreter')
    resolved = elf_resolved(capture([loader, '--list', binary]))
    loader_version = capture([loader, '--version'])
    approved = {'libc.so.6', 'libm.so.6', 'libpthread.so.0', 'libdl.so.2', 'librt.so.1', loader_name}
    require(resolved and set(resolved) <= approved and loader_name in resolved, 'Non-system dependency requires supplied runtime qualification')
    for name, path in resolved.items():
        require(Path(path).name == name and str(Path(path).resolve()).startswith(('/usr/lib/', '/lib/')),
                'Dependency resolved outside approved system library directories')
    nodes, edges = [], []
    queue = [('backplane-serve', binary)] + [(name, Path(path)) for name, path in sorted(resolved.items())]
    for name, path in queue:
        dynamic = capture(['/usr/bin/readelf', '--dynamic', '--wide', path])
        needed = elf_needed(dynamic)
        require(all(n in resolved for n in needed), 'Mandatory transitive ELF dependency unresolved')
        no_loader_imports(capture(['/usr/bin/readelf', '--dyn-syms', '--wide', path]) if name == 'backplane-serve' else '')
        if name != 'backplane-serve':
            with path.open('rb') as stream:
                header = stream.read(20)
            require(header[:6] == b'\x7fELF\x02\x01' and len(header) == 20
                and struct.unpack_from('<H', header, 18)[0] == (62 if target == 'linux-x64' else 183),
                'System library architecture mismatch')
            nodes.append({'name': name, 'path': str(path), 'realPath': str(path.resolve()),
                'sha256': sha(path), 'bytes': path.stat().st_size, 'architecture': target,
                'classification': 'approved-system', 'redistributed': False})
        edges.extend({'from': name, 'name': dep, 'resolvedSystemPath': resolved[dep]} for dep in needed)
    edges.append({'from': 'backplane-serve', 'name': loader_name, 'resolvedSystemPath': str(loader), 'interpreter': True})
    os_release = Path('/etc/os-release').read_text()
    return {'platform': 'Linux', 'release': platform.release(), 'osRelease': os_release, 'loaderVersion': loader_version,
        'systemLibraries': nodes, 'dependencyGraph': edges, 'runtimeLoaderImports': [],
        'kernelVirtualDso': 'OS-owned linux-vdso.so.1; no redistributable file',
        'sourceDisposition': 'Host distribution C-library package; system libraries are not copied or redistributed.'}


def macho_dependencies(text):
    lines = text.splitlines()
    require(lines and lines[0].endswith(':'), 'Invalid otool dependency report')
    dependencies = []
    for line in lines[1:]:
        m = re.fullmatch(r'\s+(/[^ ]+) \(compatibility version ([0-9.]+), current version ([0-9.]+)(?:, [^)]*)?\)', line)
        require(m is not None and m[1] == '/usr/lib/libSystem.B.dylib',
                'Mach-O dependency outside approved Apple system umbrella ABI')
        dependencies.append({'name': m[1], 'compatibilityVersion': m[2], 'currentVersion': m[3]})
    require(len(dependencies) == 1, 'Actual libSystem dependency required')
    return dependencies


def darwin_measure(binary, target, capture):
    deps = macho_dependencies(capture(['/usr/bin/otool', '-L', binary]))
    commands = capture(['/usr/bin/otool', '-l', binary])
    require(not re.search(r'\bcmd LC_(?:RPATH|LOAD_WEAK_DYLIB|REEXPORT_DYLIB|LOAD_UPWARD_DYLIB|LAZY_LOAD_DYLIB|DYLD_ENVIRONMENT)\b', commands),
            'Unqualified Mach-O search path or secondary dependency command')
    require(re.search(r'name /usr/lib/dyld\b', commands), 'Expected Apple dyld interpreter')
    no_loader_imports(capture(['/usr/bin/nm', '-u', binary]))
    version = capture(['/usr/bin/sw_vers'])
    # Apple's shared-cache system ABI need not exist as a standalone disk file.
    # Resolve it through this host's real dyld, then confirm the loaded image.
    system = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
    system._dyld_image_count.restype = ctypes.c_uint32
    system._dyld_get_image_name.argtypes = [ctypes.c_uint32]
    system._dyld_get_image_name.restype = ctypes.c_char_p
    images = [system._dyld_get_image_name(i).decode() for i in range(system._dyld_image_count())]
    require('/usr/lib/libSystem.B.dylib' in images, 'Host dyld did not load required system ABI')
    system._dyld_get_image_header.argtypes = [ctypes.c_uint32]
    system._dyld_get_image_header.restype = ctypes.c_void_p
    header = ctypes.string_at(system._dyld_get_image_header(images.index('/usr/lib/libSystem.B.dylib')), 12)
    require(struct.unpack_from('<II', header) == (0xfeedfacf, 0x100000c), 'Loaded system image is not arm64 Mach-O')
    return {'platform': 'Darwin', 'release': platform.release(), 'swVers': version,
        'systemLibraries': [{**d, 'classification': 'approved-system', 'redistributed': False,
            'architecture': target, 'dyldImageObserved': True} for d in deps],
        'dependencyGraph': [{'from': 'backplane-serve', 'name': d['name'], 'resolvedSystemPath': d['name']} for d in deps],
        'runtimeLoaderImports': [], 'systemAbiBoundary': 'Apple libSystem umbrella and its OS-owned shared-cache closure',
        'sourceDisposition': 'Apple OS-provided libSystem/dyld; no system binary is copied. https://opensource.apple.com/'}


def prepare(args):
    producer = args.producer.resolve(strict=True)
    require(sha(producer) == args.producer_sha256, 'Component producer hash mismatch')
    spec = importlib.util.spec_from_file_location('service_component_producer', producer)
    service = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(service)
    service.ROOT = args.source_root.resolve(strict=True)
    source, out = args.build.resolve(strict=True), args.out
    raw = source/'BUILD.json'
    build = service.read(raw)
    target = build.get('target')
    require(target == target_host() and target in service.TARGETS, 'Matching actual native host required')
    require(not any(k.startswith(('LD_', 'DYLD_')) for k in os.environ), 'Ambient loader overrides refused')
    release = {'version': service.VERSION, 'tag': 'v'+service.VERSION, 'channel': 'release',
        'commit': build['source_commit'], 'tree': build['source_tree']}
    service.frozen(release)
    require(build.get('status') == 'VERIFIED_GENUINE_SERVICE_ONLY_CONFIGURED_BUILD'
        and build.get('compileInputs') == service.compile_inputs(), 'Original configured native BUILD required')
    binary = source/'backplane-serve'
    require(sha(binary) == build['binary_sha256'], 'Native binary changed')
    service.architecture(binary, target)
    require(service.read(source/'SOURCE.json')['members'] == {
        n: sha(service.ROOT/n) for n in service.git('ls-files').splitlines()}, 'Native source manifest differs from frozen checkout')
    service.new_output(out)
    out.mkdir(parents=True)
    runtime = out/'runtime'
    evidence = runtime/'runtime-evidence'
    evidence.mkdir(parents=True)
    capture = Capture(evidence)
    measurement = linux_measure(binary, target, capture) if target.startswith('linux-') else darwin_measure(binary, target, capture)
    measurement.update({'schema': 1, 'target': target, 'sourceCommit': release['commit'], 'sourceTree': release['tree'],
        'binarySha256': sha(binary), 'operations': capture.calls,
        'scope': 'Measured native dynamic ABI closure only; external CLI tools and installed UI/workflows are not qualified.'})
    write(evidence/'system-dependencies.json', measurement)
    shutil.copyfile(Path(__file__), evidence/'SERVICE-RUNTIME-PRODUCER.py')
    notice = runtime/'runtime-notices'
    notice.mkdir()
    shutil.copyfile(source/'LICENSE.Backplane', notice/'LICENSE.Backplane')
    (notice/'SYSTEM-ABI-NOTICE.txt').write_text('System libraries are host supplied and NOT redistributed.\n'
        + measurement['sourceDisposition'] + '\nSee runtime-evidence/system-dependencies.json for actual paths, '
        'versions/hashes where files exist and measurement commands. Apple shared-cache images are recorded as such; '
        'no fictitious file hashes are assigned.\nNo library, font, SDK or compiler runtime was silently bundled.\n')
    packages = [{'name': 'Backplane runtime measurement and declaration', 'version': service.VERSION,
        'sourceDisposition': 'https://github.com/i2cjak/Backplane/tree/'+release['commit']+'; actual separately pinned measurement producer retained in runtime-evidence.',
        'licenses': [{'path': 'runtime-notices/LICENSE.Backplane', 'sha256': sha(notice/'LICENSE.Backplane')},
                     {'path': 'runtime-notices/SYSTEM-ABI-NOTICE.txt', 'sha256': sha(notice/'SYSTEM-ABI-NOTICE.txt')}]}]
    write(runtime/'RUNTIME.json', {'schema': 1, 'target': target, 'inventory': [
        {'path': f.relative_to(runtime).as_posix(), 'package': packages[0]['name'], 'version': service.VERSION,
         'architecture': target, 'sha256': sha(f), 'bytes': f.stat().st_size}
        for f in sorted(evidence.iterdir())], 'packages': packages,
        'suppliedLibraries': [], 'systemDependencies': measurement['systemLibraries']})
    # Edges are rooted in the supplied service; system dependencies remain OS-owned
    # leaves. The full measured Linux transitive graph is retained in system.json.
    write(runtime/'CLOSURE.json', {'schema': 1, 'target': target, 'measured': True, 'status': 'PASS',
        'unresolvedMandatory': [], 'edges': [{'from': 'backplane-serve', 'kind': 'normal', 'name': d['name'],
          'system': True, 'classification': 'approved-system', 'resolvedSystemPath': d['resolvedSystemPath']}
          for d in measurement['dependencyGraph'] if d['from'] == 'backplane-serve'],
        'measurement': 'runtime-evidence/system-dependencies.json', 'runtimeAcceptance': 'PENDING'})
    write(out/'RUNTIME-QUALIFICATION.json', {'schema': 1, 'kind': 'backplane-service-runtime-qualification',
        'status': 'PASS', 'target': target, 'sourceCommit': release['commit'], 'sourceTree': release['tree'],
        'binarySha256': sha(binary), 'runtimeManifestSha256': sha(runtime/'RUNTIME.json'),
        'closureSha256': sha(runtime/'CLOSURE.json'), 'members': service.inventory(runtime),
        'scope': measurement['scope'], 'componentProducer': service.reference(producer)})
    request = {'schema': 1, 'kind': 'backplane-service-component-inputs', 'target': target, 'release': release,
        'buildDirectory': str(source), 'buildReceipt': service.reference(raw), 'runtimeDirectory': str(runtime),
        'runtimeQualification': service.reference(out/'RUNTIME-QUALIFICATION.json')}
    write(out/'COMPONENT-REQUEST.json', request)
    result = service.component(request, out, out/'component')
    require(sha(binary) == build['binary_sha256'] and sha(raw) == request['buildReceipt']['sha256'], 'Build changed during measurement')
    service.frozen(release)
    write(out/'RESULT.json', {**result, 'runtimeAcceptance': 'PENDING', 'published': False,
        'measurementProducer': service.reference(Path(__file__)), 'componentProducer': service.reference(producer)})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source-root', 'build', 'producer', 'out'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--producer-sha256', required=True)
    args = parser.parse_args()
    require(args.out.is_absolute(), 'New absolute output directory required')
    print(json.dumps(prepare(args), indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print('Service runtime preparation: '+str(error), file=sys.stderr)
        sys.exit(1)
