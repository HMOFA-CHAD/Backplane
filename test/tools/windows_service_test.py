#!/usr/bin/env python3
"""Bounded offline source/receipt regressions, no native program or compiler.

These tests use generated metadata/PE headers only. They do not qualify a
service emission, a signed application or an actual Windows runtime.
"""
import gzip
import importlib.util
import json
from pathlib import Path
import struct
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

sys.dont_write_bytecode = True

path = Path(__file__).resolve().parents[2] / 'scripts/windows-service.py'
spec = importlib.util.spec_from_file_location('windows_service', path)
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)


def fixture_pe(dependency=None):
    data = bytearray(1024)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 0x3c, 128)
    data[128:132] = b'PE\0\0'
    struct.pack_into('<HH', data, 132, 0x8664, 1)
    struct.pack_into('<H', data, 148, 240)
    struct.pack_into('<H', data, 152, 0x20b)
    struct.pack_into('<I', data, 212, 512)
    struct.pack_into('<IIII', data, 400, 512, 0x1000, 512, 512)
    if dependency:
        struct.pack_into('<II', data, 272, 0x1000, 40)
        struct.pack_into('<IIIII', data, 512, 0, 0, 0, 0x1040, 0)
        name = dependency.encode() + b'\0'
        data[576:576+len(name)] = name
    return bytes(data)


class Metadata(unittest.TestCase):
    def test_explicit_unsigned_portable_preserves_compiled_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            service = Path(temporary) / 'backplane-serve.exe'
            unsigned = service.with_name('unsigned-service.exe')
            service.write_bytes(fixture_pe());unsigned.write_bytes(service.read_bytes())
            receipt = {'unsignedServiceSha256': api.sha(unsigned)}
            result = api.signing(service, [], receipt, 'unsigned-portable-allowed', None)
            self.assertFalse(result['signed'])
            self.assertFalse(result['publicEligible'])
            self.assertEqual(result['validation'], 'root-portable-policy-runtime-gates-pending')
            service.write_bytes(service.read_bytes() + b'changed')
            with self.assertRaises(ValueError):
                api.signing(service, [], receipt, 'unsigned-portable-allowed', None)

    def test_native_builds_exact_both_roots_and_refuses_partial_compile(self):
        for failure in ('none', 'compile', 'version'):
            fail_render = failure == 'compile'
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary);out = root/'native';calls = []
                source = {'versionStamp':'0.12.0', 'version':'0.12.0', 'telemetry_channel':'release',
                          'service_c_sha256':api.digest(b'service fixture'),
                          'render_c_sha256':api.digest(b'render fixture')}
                execution = {'schema':1, 'metadataCommit':'1'*40, 'metadataTree':'2'*40,
                             'toolsSha256':{'scripts/windows-runtime.py':'3'*64}}
                def inputs(archive, expected, destination):
                    destination.mkdir(parents=True)
                    for name in ('service','render'):
                        (destination/(name+'.c.gz')).write_bytes(gzip.compress((name+' fixture').encode()))
                    api.write(destination/'SOURCE.json', source)
                    return source
                def run(command, **kwargs):
                    c,exe = map(Path,command[-2:]);name = c.stem;calls.append(name)
                    self.assertEqual(c.read_bytes(), (name+' fixture').encode())
                    self.assertEqual(command[1],str(api.TOOLS_ROOT/'scripts/build-windows.sh'))
                    if fail_render and name=='render':raise api.subprocess.CalledProcessError(1,command)
                    exe.write_bytes(fixture_pe() + name.encode())
                    adapted=exe.with_suffix('.cc')/'runtime.c';adapted.parent.mkdir()
                    adapted.write_bytes(b'adapted '+c.read_bytes())
                    api.write(adapted.with_name('RUNTIME-ADAPTER.json'),{'schema':1,
                        'adapterSha256':'3'*64,'sourceCsha256':source[name+'_c_sha256'],
                        'transformedCsha256':api.sha(adapted)})
                args=SimpleNamespace(out=out,runtime_payload=root/'runtime',runtime_manifest_sha256='4'*64,
                                     inputs=root/'inputs.tar.gz',sha256='5'*64)
                with patch.object(api.sys,'platform','cygwin'),patch.object(api,'identity'),\
                     patch.object(api,'runtime_payload'),patch.object(api,'bake_inputs',return_value={}),\
                     patch.object(api,'execution_tools_identity',side_effect=lambda:json.loads(json.dumps(execution))),\
                     patch.object(api,'import_inputs',side_effect=inputs),\
                     patch.dict(api.os.environ,{'CC':sys.executable,'BACKPLANE_CFLAGS':'-O2'}),\
                     patch.object(api.subprocess,'run',side_effect=run),\
                     patch.object(api.subprocess,'check_output',side_effect=['x86_64-pc-cygwin','clang version 22.1.8','backplane-render '+('wrong' if failure == 'version' else '0.12.0')]):
                    if fail_render:
                        with self.assertRaises(api.subprocess.CalledProcessError):api.native(args)
                        self.assertFalse((out/'COMPILE.json').exists())
                    elif failure == 'version':
                        with self.assertRaisesRegex(ValueError, 'renderer version'):api.native(args)
                        self.assertFalse((out/'COMPILE.json').exists())
                    else:
                        api.native(args);receipt=api.load(out/'COMPILE.json')
                        self.assertEqual(receipt['renderCsha256'],source['render_c_sha256'])
                        self.assertEqual(receipt['renderEntrypoint'],api.RENDER_ENTRY)
                        self.assertEqual(receipt['renderVersion'],'backplane-render 0.12.0')
                        self.assertEqual(receipt['unsignedRenderSha256'],api.sha(out/'backplane-render.exe'))
                        self.assertEqual(api.sha(out/'unsigned-render.exe'),api.sha(out/'backplane-render.exe'))
                        self.assertEqual(receipt['producerExecution']['renderRuntimeAdapter']['sourceCsha256'],source['render_c_sha256'])
                        self.assertNotEqual(receipt['unsignedRenderSha256'],receipt['unsignedServiceSha256'])
                self.assertEqual(calls,['service','render'])

    def test_emit_binds_distinct_service_and_render_entrypoints(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);(root/'src/web').mkdir(parents=True);(root/'src/web/sw.js').write_text('// fixture')
            calls=[]
            ident=dict(commit='1'*40,tree='2'*40,entrypoint=api.ENTRY,target='windows-x64',
                       version='0.12.0',versionTag='v0.12.0',versionStamp='0.12.0',telemetry_channel='release')
            def run(command, **kwargs):
                if command[:2]==['bash','scripts/build-app.sh']:
                    calls.append(command[2]);p=root/'build/cc'/Path(command[3]).name/'all.c'
                    p.parent.mkdir(parents=True);p.write_text('C fixture for '+command[2])
                elif command[:2]==['bend','src/web/index.html']:
                    web=Path(command[-1]);web.mkdir();(web/'index.html').write_text('<html>fixture</html>')
                    (web/'chunk-fixture.js').write_text('// fixture')
            with patch.object(api,'ROOT',root),patch.object(api,'identity',side_effect=lambda:dict(ident)),\
                 patch.object(api,'compiler_pin',return_value={'version':'metadata-only','archiveSha256':'3'*64,'executableSha256':'4'*64}),\
                 patch.object(api.subprocess,'run',side_effect=run):
                api.emit(SimpleNamespace(out=root/'out'))
                source=api.check_inputs(root/'out/windows-service-inputs')
                self.assertEqual(source['render_entrypoint'],api.RENDER_ENTRY)
                self.assertEqual(source['render_c_sha256'],api.digest(('C fixture for '+api.RENDER_ENTRY).encode()))
                self.assertNotEqual(source['render_c_sha256'],source['service_c_sha256'])
                with api.tarfile.open(root/'out'/api.INPUT_ARCHIVE) as tar:
                    self.assertIn('windows-service-inputs/render.c.gz',tar.getnames())
            self.assertEqual(calls,[api.ENTRY,api.RENDER_ENTRY])

    def test_renderer_authenticode_uses_own_unsigned_reference_and_filename(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);service=root/'backplane-render.exe';original=fixture_pe()
            unsigned=root/'unsigned-render.exe';unsigned.write_bytes(original)
            signed=bytearray(original)+b'fixture-certificate';struct.pack_into('<II',signed,152+112+4*8,len(original),19)
            service.write_bytes(signed);(root/'cygpath.exe').write_bytes(b'fixture only')
            with patch.object(api.sys,'platform','cygwin'),patch.object(api.sys,'executable',str(root/'python.exe')),\
                 patch.object(api.subprocess,'check_output',side_effect=['C:\\fixture\\backplane-render.exe',json.dumps({'status':'Valid','thumbprint':'A'*40})]):
                result=api.signing(service,[],{'unsignedRenderSha256':api.sha(unsigned)},'authenticode','A'*40,
                                   'unsigned-render.exe','unsignedRenderSha256')
            self.assertEqual(result['policy'],'authenticode')
            self.assertEqual(result['files']['backplane-render.exe']['sha256'],api.sha(service))

    def test_paths_and_application_fonts(self):
        for name in ('../x', 'x\\y', 'x:stream', 'a/CON.txt', 'a.', 'a\nfile'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                api.member(name)
        for name, data in (('font.ttf', b'x'), ('renamed.dat', b'OTTOxxxx'),
                           ('fonts/x', b'x'), ('private.h', b'x'),
                           ('font.dat.gz', gzip.compress(b'wOFFxxxx')),
                           ('app.css', b'font-family: BerkeleyMono'),
                           ('app.css', b'@font-face {font-family: localfont}')):
            with self.subTest(name=name), self.assertRaises(ValueError):
                api.allowed(name, data)

    def test_actual_import_edges_not_mz_only(self):
        files = {'backplane-serve.exe': fixture_pe('cygwin1.dll'),
                 'runtime/bin/cygwin1.dll': fixture_pe('KERNEL32.dll')}
        runtime = {'systemDlls': ['kernel32.dll'], 'dynamicDependencies': []}
        result = api.closure(files, runtime)
        self.assertEqual(result['edges'][0]['to'], 'runtime/bin/cygwin1.dll')
        self.assertTrue(result['edges'][1]['system'])
        with self.assertRaises(ValueError):
            api.closure({'backplane-serve.exe': fixture_pe('cygwin1.dll')}, runtime)
        with self.assertRaises(ValueError):
            api.pe(b'MZ metadata only')

    def test_source_entry_web_and_tamper(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            (directory / 'web').mkdir()
            (directory / 'web/index.html').write_text('<html>metadata fixture</html>')
            (directory / 'web/index.html.gz').write_bytes(gzip.compress(b'<html>metadata fixture</html>'))
            (directory / 'service.c.gz').write_bytes(gzip.compress(b'/* not an emitted program */'))
            (directory / 'render.c.gz').write_bytes(gzip.compress(b'/* renderer fixture */'))
            ident = dict(commit='1'*40, tree='2'*40, entrypoint=api.ENTRY,
                         target='windows-x64', version='0.11.2', versionTag='v0.11.2',
                         versionStamp='0.11.2', telemetry_channel='release')
            api.write(directory / 'WEB.json', dict(schema=1, kind='matching-generated-web',
                sourceCommit=ident['commit'], sourceTree=ident['tree'],
                entrypoint='src/web/index.html', members=api.inventory(directory / 'web')))
            source = dict(ident, schema=3, kind='windows-service-emission',
                inputs_sha256={n: x['sha256'] for n, x in api.inventory(directory, portable=True).items()},
                service_c_sha256=api.digest(b'/* not an emitted program */'),
                render_entrypoint=api.RENDER_ENTRY, render_c_sha256=api.digest(b'/* renderer fixture */'),
                web_manifest_sha256=api.sha(directory / 'WEB.json'),
                bend={'version': 'metadata-only', 'archiveSha256': '3'*64, 'executableSha256': '4'*64})
            api.write(directory / 'SOURCE.json', source)
            with patch.object(api, 'identity', return_value=ident):
                self.assertEqual(api.check_inputs(directory)['entrypoint'], api.ENTRY)
                original_render = (directory/'render.c.gz').read_bytes()
                (directory/'render.c.gz').unlink()
                with self.assertRaises(ValueError): api.check_inputs(directory)
                (directory/'render.c.gz').write_bytes(original_render)
                source['render_entrypoint'] = api.ENTRY
                api.write(directory/'SOURCE.json', source)
                with self.assertRaisesRegex(ValueError, 'render entrypoint'): api.check_inputs(directory)
                source['render_entrypoint'] = api.RENDER_ENTRY
                source['render_c_sha256'] = '0'*64
                api.write(directory/'SOURCE.json', source)
                with self.assertRaisesRegex(ValueError, 'render C'): api.check_inputs(directory)
                source['render_c_sha256'] = api.digest(b'/* renderer fixture */')
                source['entrypoint'] = 'src/app/main.bend'
                api.write(directory / 'SOURCE.json', source)
                with self.assertRaises(ValueError): api.check_inputs(directory)
                source['entrypoint'] = api.ENTRY
                api.write(directory / 'SOURCE.json', source)
                (directory / 'web/index.html').write_text('tampered')
                with self.assertRaises(ValueError): api.check_inputs(directory)
                (directory / 'web/index.html').write_text('<html>metadata fixture</html>')
                (directory / 'web/index.html.gz').write_bytes(gzip.compress(b'stale HTML'))
                web = api.load(directory / 'WEB.json')
                web['members'] = api.inventory(directory / 'web')
                api.write(directory / 'WEB.json', web)
                source['web_manifest_sha256'] = api.sha(directory / 'WEB.json')
                source['inputs_sha256'] = {n: v['sha256'] for n, v in
                    api.inventory(directory, ('SOURCE.json',), portable=True).items()}
                api.write(directory / 'SOURCE.json', source)
                with self.assertRaises(ValueError): api.check_inputs(directory)

    def test_duplicate_json_keys(self):
        with self.assertRaises(ValueError):
            api.unambiguous([('schema', 3), ('schema', 2)])

    def test_missing_protected_inputs_refused_before_compiler(self):
        with patch.dict(api.os.environ, {}, clear=True), patch.object(api.subprocess, 'run') as run:
            with self.assertRaises(ValueError): api.bake_inputs()
            run.assert_not_called()

    def test_public_endpoint_witness_requires_actual_guard(self):
        env = {'BACKPLANE_GOOGLE_BAKE': '1', 'BACKPLANE_TELEMETRY_BAKE': '1',
            'BACKPLANE_GOOGLE_CLIENT_ID': 'synthetic-id',
            'BACKPLANE_GOOGLE_CLIENT_SECRET': 'synthetic-secret',
            'BACKPLANE_TELEMETRY_URL': 'https://invalid.example/fixture',
            'BACKPLANE_TELEMETRY_KID': 'rel-fixture', 'BACKPLANE_TELEMETRY_KEY': 'a'*64}
        with patch.dict(api.os.environ, env, clear=True), patch.object(api.subprocess, 'run') as run:
            with self.assertRaises(ValueError): api.bake_inputs()
            run.assert_not_called()
            api.os.environ['BACKPLANE_TELEMETRY_URL'] = api.TELEMETRY_ENDPOINT
            witnessed = api.bake_inputs()
            self.assertEqual(witnessed['telemetry']['endpoint'], api.TELEMETRY_ENDPOINT)
            self.assertEqual(run.call_count, 2)  # Header validation only; subprocesses mocked.
            encoded = json.dumps(witnessed)
            self.assertNotIn('synthetic-secret', encoded)
            self.assertNotIn('synthetic-id', encoded)
            self.assertNotIn('a'*64, encoded)

    def test_fixture_resource_receipts_and_tamper(self):
        # All PE bytes below are synthetic headers, not executable artifacts.
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            inputs, payload = root/'native/inputs', root/'payload'
            (inputs/'web').mkdir(parents=True)
            (payload/'runtime/bin').mkdir(parents=True)
            (payload/'licenses').mkdir()
            (inputs/'web/index.html').write_text('metadata fixture')
            (inputs/'web/index.html.gz').write_bytes(gzip.compress(b'metadata fixture'))
            (inputs/'service.c.gz').write_bytes(gzip.compress(b'fixture, not emitted C'))
            (inputs/'render.c.gz').write_bytes(gzip.compress(b'render fixture, not emitted C'))
            ident = dict(commit='1'*40, tree='2'*40, entrypoint=api.ENTRY,
                         target='windows-x64', version='0.11.2', versionTag='v0.11.2',
                         versionStamp='0.11.2', telemetry_channel='release')
            api.write(inputs/'WEB.json', dict(schema=1, kind='matching-generated-web',
                sourceCommit=ident['commit'], sourceTree=ident['tree'],
                entrypoint='src/web/index.html', members=api.inventory(inputs/'web')))
            source = dict(ident, schema=3, kind='windows-service-emission',
                inputs_sha256={n: x['sha256'] for n, x in api.inventory(inputs, portable=True).items()},
                service_c_sha256=api.digest(b'fixture, not emitted C'),
                render_entrypoint=api.RENDER_ENTRY, render_c_sha256=api.digest(b'render fixture, not emitted C'),
                web_manifest_sha256=api.sha(inputs/'WEB.json'),
                bend={'version': 'metadata-only', 'archiveSha256': '3'*64, 'executableSha256': '4'*64})
            api.write(inputs/'SOURCE.json', source)
            for name in ('cygwin1.dll', 'cygpath.exe', 'sh.exe'):
                (payload/'runtime/bin'/name).write_bytes(fixture_pe('KERNEL32.dll'))
            (payload/'licenses/fixture.txt').write_text('fixture, no distribution')
            members = {n: {**v, 'package': 'metadata', 'version': '0', 'architecture': 'x64', 'license': 'fixture-only',
                       'notices': ['licenses/fixture.txt'], 'sourceDisposition': {'mode': 'none-required'}}
                       for n, v in api.inventory(payload).items()}
            rows, packages = api.runtime_aliases(members)
            api.write(payload/'RUNTIME.json', dict(schema=1, target='windows-x64', members=members,
                inventory=rows, packages=packages, helpers={}, systemDlls=['kernel32.dll'],
                dynamicInventoryComplete=True, dynamicDependencies=[]))
            service = root/'native/backplane-serve.exe'
            service.write_bytes(fixture_pe('cygwin1.dll'))
            (root/'native/unsigned-service.exe').write_bytes(service.read_bytes())
            renderer = root/'native/backplane-render.exe'
            renderer.write_bytes(fixture_pe('cygwin1.dll') + b'render')
            (root/'native/unsigned-render.exe').write_bytes(renderer.read_bytes())
            execution = {'schema': 1, 'metadataCommit': '5'*40, 'metadataTree': '6'*40,
                'toolsSha256': {'scripts/windows-runtime.py': '7'*64},
                'runtimeAdapter': {'schema': 1, 'adapterSha256': '7'*64,
                    'sourceCsha256': source['service_c_sha256'], 'transformedCsha256': '8'*64},
                'renderRuntimeAdapter': {'schema': 1, 'adapterSha256': '7'*64,
                    'sourceCsha256': source['render_c_sha256'], 'transformedCsha256': '9'*64}}
            api.write(root/'native/COMPILE.json', dict(schema=1,
                sourceReceiptSha256=api.sha(inputs/'SOURCE.json'), unsignedServiceSha256=api.sha(service),
                unsignedRenderSha256=api.sha(renderer), renderEntrypoint=api.RENDER_ENTRY,
                renderCsha256=source['render_c_sha256'], renderVersion='backplane-render '+source['version'],
                producerExecution=execution,
                runtimeManifestSha256=api.sha(payload/'RUNTIME.json'), compiler={'fixture': True},
                compileInputs={'version': '0.11.2', 'versionStamp': '0.11.2', 'telemetryChannel': 'release',
                    'google': {'requested': True, 'requiredInputsPresent': True},
                    'telemetry': {'requested': True, 'requiredInputsPresent': True,
                                  'endpoint': api.TELEMETRY_ENDPOINT}}))
            args = SimpleNamespace(native_dir=root/'native', runtime_payload=payload,
                runtime_manifest_sha256=api.sha(payload/'RUNTIME.json'),
                signing_policy='unsigned-internal', signing_thumbprint=None,
                managed_control_receipt=None, managed_control_sha256=None, out=root/'out')
            with patch.object(api, 'identity', return_value=ident):
                api.package(args)
                archive = root/'out'/api.RESOURCE_ARCHIVE
                with zipfile.ZipFile(archive) as z:
                    build = json.loads(z.read('backplane-service/BUILD.json'))
                    self.assertEqual(build['producerExecution'], execution)
                    self.assertEqual(build['roles']['render'], 'backplane-render.exe')
                    self.assertEqual(build['renderSha256'], api.sha(renderer))
                    self.assertIn('backplane-render.exe', build['pe'])
                    self.assertFalse(build['signing']['publicEligible'])
                    self.assertEqual(build['managedControl']['status'], 'UNSUPPORTED')
                    entries = {n: z.read(n) for n in z.namelist()}
                with self.assertRaises(ValueError): api.verify_resources(archive, '0'*64)
                render_entries = dict(entries)
                render_entries['backplane-service/backplane-render.exe'] += b'substituted'
                changed_build = dict(build)
                changed_build['sha256'] = dict(build['sha256'])
                changed_build['sizes'] = dict(build['sizes'])
                changed_build['sha256']['backplane-render.exe'] = api.digest(render_entries['backplane-service/backplane-render.exe'])
                changed_build['sizes']['backplane-render.exe'] = len(render_entries['backplane-service/backplane-render.exe'])
                render_entries['backplane-service/BUILD.json'] = json.dumps(changed_build).encode()
                with zipfile.ZipFile(root/'bad-render.zip', 'w') as z:
                    for n, b in render_entries.items(): z.writestr(n, b)
                with self.assertRaisesRegex(ValueError, 'renderer digest'):
                    api.verify_resources(root/'bad-render.zip', api.sha(root/'bad-render.zip'))
                entries['backplane-service/web/index.html'] = b'tampered'
                bad = root/'bad.zip'
                with zipfile.ZipFile(bad, 'w') as z:
                    for n, b in entries.items(): z.writestr(n, b)
                with self.assertRaises(ValueError): api.verify_resources(bad, api.sha(bad))
            self.assertEqual(api.sha(payload/'RUNTIME.json'), args.runtime_manifest_sha256)

    def test_managed_control_requires_real_bound_acceptance(self):
        source = {'commit': '1'*40, 'tree': '2'*40, 'version': '0.12.0'}
        self.assertEqual(api.managed_control(None, source, '3'*64, '4'*64)['status'], 'UNSUPPORTED')
        receipt = {'schema': 1, 'kind': 'backplane-managed-service-control-acceptance',
            'status': 'PASS', 'target': 'windows-x64', 'protocol': 1,
            **source, 'serviceSha256': '3'*64, 'runtimeManifestSha256': '4'*64,
            'checks': {n: True for n in api.CONTROL_CHECKS}}
        data = json.dumps(receipt).encode()
        self.assertEqual(api.managed_control(data, source, '3'*64, '4'*64)['status'], 'IMPLEMENTED')
        with self.assertRaises(ValueError): api.managed_control(data, source, '5'*64, '4'*64)
        receipt['checks']['atomicAdmissionClosed'] = False
        with self.assertRaises(ValueError):
            api.managed_control(json.dumps(receipt).encode(), source, '3'*64, '4'*64)

    def test_record_runtime_aliases_and_byte_tamper(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            payload = root/'payload'
            (payload/'runtime/bin').mkdir(parents=True)
            (payload/'licenses').mkdir()
            for name in ('cygwin1.dll', 'cygpath.exe', 'sh.exe'):
                (payload/'runtime/bin'/name).write_bytes(fixture_pe('KERNEL32.dll'))
            (payload/'licenses/fixture.txt').write_text('metadata-only notice')
            members = {n: {'package': 'metadata-fixture', 'version': '0', 'architecture': 'x64',
                'license': 'fixture-only', 'notices': ['licenses/fixture.txt'],
                'sourceDisposition': {'mode': 'none-required'}} for n in api.inventory(payload)}
            description = root/'description.json'
            api.write(description, {'members': members, 'helpers': {}, 'systemDlls': ['kernel32.dll'],
                'dynamicInventoryComplete': True, 'dynamicDependencies': []})
            api.record_runtime(SimpleNamespace(payload=payload, description=description))
            expected = api.sha(payload/'RUNTIME.json')
            runtime = api.runtime_payload(payload, expected)
            self.assertEqual(len(runtime['inventory']), 4)
            self.assertEqual(runtime['packages'][0]['name'], 'metadata-fixture')
            (payload/'licenses/fixture.txt').write_text('tampered')
            with self.assertRaises(ValueError): api.runtime_payload(payload, expected)


if __name__ == '__main__':
    unittest.main()
