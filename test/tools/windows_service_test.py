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
            ident = dict(commit='1'*40, tree='2'*40, entrypoint=api.ENTRY,
                         target='windows-x64', version='0.11.2', versionTag='v0.11.2',
                         versionStamp='0.11.2', telemetry_channel='release')
            api.write(directory / 'WEB.json', dict(schema=1, kind='matching-generated-web',
                sourceCommit=ident['commit'], sourceTree=ident['tree'],
                entrypoint='src/web/index.html', members=api.inventory(directory / 'web')))
            source = dict(ident, schema=3, kind='windows-service-emission',
                inputs_sha256={n: x['sha256'] for n, x in api.inventory(directory, portable=True).items()},
                service_c_sha256=api.digest(b'/* not an emitted program */'),
                web_manifest_sha256=api.sha(directory / 'WEB.json'),
                bend={'version': 'metadata-only', 'archiveSha256': '3'*64, 'executableSha256': '4'*64})
            api.write(directory / 'SOURCE.json', source)
            with patch.object(api, 'identity', return_value=ident):
                self.assertEqual(api.check_inputs(directory)['entrypoint'], api.ENTRY)
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
            ident = dict(commit='1'*40, tree='2'*40, entrypoint=api.ENTRY,
                         target='windows-x64', version='0.11.2', versionTag='v0.11.2',
                         versionStamp='0.11.2', telemetry_channel='release')
            api.write(inputs/'WEB.json', dict(schema=1, kind='matching-generated-web',
                sourceCommit=ident['commit'], sourceTree=ident['tree'],
                entrypoint='src/web/index.html', members=api.inventory(inputs/'web')))
            source = dict(ident, schema=3, kind='windows-service-emission',
                inputs_sha256={n: x['sha256'] for n, x in api.inventory(inputs, portable=True).items()},
                service_c_sha256=api.digest(b'fixture, not emitted C'),
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
            api.write(root/'native/COMPILE.json', dict(schema=1,
                sourceReceiptSha256=api.sha(inputs/'SOURCE.json'), unsignedServiceSha256=api.sha(service),
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
                    self.assertFalse(build['signing']['publicEligible'])
                    self.assertEqual(build['managedControl']['status'], 'UNSUPPORTED')
                    entries = {n: z.read(n) for n in z.namelist()}
                with self.assertRaises(ValueError): api.verify_resources(archive, '0'*64)
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
