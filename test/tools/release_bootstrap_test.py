#!/usr/bin/env python3
"""Offline transfer guards; no network, emit, compiler, secret or platform job."""
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('bootstrap', ROOT / 'scripts/release-bootstrap.py')
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
SOURCE, TREE = 'a' * 40, 'b' * 40


class BootstrapTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.inputs = self.root / 'inputs'
        self.inputs.mkdir()
        (self.inputs / 'emission').mkdir()
        (self.inputs / 'emission/EMISSION.json').write_text(json.dumps({
            'kind': 'backplane-service-c-emission', 'status': 'VERIFIED_PORTABLE_C_EMISSION_ONLY',
            'sourceCommit': SOURCE, 'sourceTree': TREE, 'version': '0.12.0'}))
        (self.inputs / 'emission/all.c').write_text('public exact C')

    def packet(self):
        archive = self.root / 'packet.tar.gz'
        result = b.pack(self.inputs, archive, SOURCE, TREE, 'unix-native')
        self.assertEqual(result['archiveSha256'], b.sha(archive))
        return archive

    def unpack(self):
        dest = self.root / 'unpacked'
        b.extract(self.packet(), dest)
        return dest

    def test_round_trip_and_identity(self):
        dest = self.unpack()
        self.assertEqual(b.verify(dest, SOURCE, TREE, 'unix-native')['version'], '0.12.0')
        for args in [('c'*40, TREE, 'unix-native'), (SOURCE, 'c'*40, 'unix-native'), (SOURCE, TREE, 'android')]:
            with self.subTest(args=args), self.assertRaises(ValueError): b.verify(dest, *args)

    def test_round_trip_preserves_receipt_bound_regular_file_modes(self):
        modes = (0o600, 0o640, 0o644, 0o664, 0o700, 0o755, 0o775)
        for mode in modes:
            member = self.inputs / ('mode-' + oct(mode))
            member.write_bytes(b'public mode-bound artifact')
            member.chmod(mode)
        dest = self.unpack()
        for mode in modes:
            member = dest / ('mode-' + oct(mode))
            self.assertEqual(member.stat().st_mode & 0o777, mode)

    def test_privileged_or_world_writable_tar_mode_refused_before_extraction(self):
        for mode in (0o4755, 0o2644, 0o1644, 0o666):
            archive = self.root / (oct(mode) + '.tar.gz')
            with tarfile.open(archive, 'w:gz') as tar:
                member = tarfile.TarInfo('public'); member.mode = mode; member.size = 1
                tar.addfile(member, io.BytesIO(b'x'))
            dest = self.root / oct(mode)
            with self.subTest(mode=mode), self.assertRaises(ValueError): b.extract(archive, dest)
            self.assertFalse(dest.exists())

    def test_changed_missing_extra_bytes_refused(self):
        dest = self.unpack()
        c = dest / 'emission/all.c'
        c.write_text('changed')
        with self.assertRaises(ValueError): b.verify(dest, SOURCE, TREE, 'unix-native')
        c.unlink()
        with self.assertRaises(ValueError): b.verify(dest, SOURCE, TREE, 'unix-native')
        c.write_text('public exact C')
        (dest / 'extra').write_text('extra')
        with self.assertRaises(ValueError): b.verify(dest, SOURCE, TREE, 'unix-native')

    def test_noncanonical_paths(self):
        for path in ('../x', '/x', 'x/../y', 'x\\y', 'C:/x', 'x//y', './x', ''):
            with self.subTest(path=path), self.assertRaises(ValueError): b.relative(path)

    def test_symlink_and_private_input_refused(self):
        p = self.inputs / 'linked'
        p.symlink_to('emission/all.c')
        with self.assertRaises(ValueError): self.packet()
        p.unlink()
        (self.inputs / 'signer.p12').write_text('not a real key')
        with self.assertRaises(ValueError): self.packet()

    def test_tar_traversal_links_duplicate_and_special_refused(self):
        for label, names, type_ in [('up', ['../out'], tarfile.REGTYPE), ('link', ['link'], tarfile.SYMTYPE),
                                     ('duplicate', ['a','A'], tarfile.REGTYPE), ('fifo', ['pipe'], tarfile.FIFOTYPE)]:
            archive = self.root / (label + '.tar.gz')
            with tarfile.open(archive, 'w:gz') as tar:
                for name in names:
                    m = tarfile.TarInfo(name); m.type = type_
                    if type_ == tarfile.REGTYPE: m.size = 1
                    tar.addfile(m, io.BytesIO(b'x') if m.isfile() else None)
            with self.subTest(label=label), self.assertRaises(ValueError): b.extract(archive, self.root / label)
            self.assertFalse((self.root / label).exists())

    def test_existing_destination_not_reused(self):
        archive = self.packet()
        with self.assertRaises(ValueError): b.extract(archive, self.inputs)

    def test_unconfigured_or_wrong_emission_not_promoted(self):
        dest = self.unpack()
        r = json.loads((dest / 'BOOTSTRAP.json').read_text())
        e = dest / 'emission/EMISSION.json'; value=json.loads(e.read_text()); value['version']='0.12.0-dev'; e.write_text(json.dumps(value))
        r['files']['emission/EMISSION.json']={'sha256':b.sha(e),'bytes':e.stat().st_size}
        (dest / 'BOOTSTRAP.json').write_text(json.dumps(r))
        with self.assertRaises(ValueError): b.verify(dest, SOURCE, TREE, 'unix-native')

    def test_run_calls_only_checked_out_native_producer(self):
        dest = self.unpack()
        with patch.object(b,'source_identity',return_value=TREE), patch.object(b,'tool',return_value={'path':'/cc'}), patch.object(b.subprocess,'run') as run:
            b.run(dest,'unix-native','linux-arm64',SOURCE,ROOT,'/cc')
            args=run.call_args.args[0]
            self.assertEqual(args[1:3],[str(ROOT/'scripts/service-release.py'),'native'])
            self.assertEqual(args[3:5],['--source-root',str(ROOT)])
            request=json.loads((dest.parent/'native-linux-arm64.json').read_text())
            self.assertEqual(request['target'],'linux-arm64')
            self.assertEqual(request['emissionReceipt']['sha256'],b.sha(dest/'emission/EMISSION.json'))
            self.assertNotIn('BACKPLANE_PREBUILT',json.dumps(request))
        with patch.object(b,'source_identity',return_value=TREE), self.assertRaises(ValueError):
            b.run(dest,'unix-native','windows-x64',SOURCE,ROOT,'/cc')

    def test_windows_executes_metadata_request_from_separate_frozen_checkout(self):
        request=self.inputs/'windows-service-request.json'
        request.write_text(json.dumps({'sourceCommit':SOURCE,'sourceTree':TREE}))
        archive=self.root/'windows.tar.gz'
        b.pack(self.inputs,archive,SOURCE,TREE,'windows-native')
        dest=self.root/'windows-inputs'; b.extract(archive,dest)
        product=self.root/'separate frozen product'
        with patch.object(b,'source_identity',return_value=TREE), patch.object(b.subprocess,'run') as run:
            b.run(dest,'windows-native',None,SOURCE,product)
            self.assertEqual(run.call_args.args[0],[b.sys.executable,str(ROOT/'scripts/windows-release-request.py'),'native',str(dest/'windows-service-request.json')])
            self.assertEqual(run.call_args.kwargs['cwd'],product)

    def test_android_executes_separately_pinned_metadata_without_mutating_packet(self):
        request=self.inputs/'android-release-inputs.json'
        request.write_text(json.dumps({'sourceCommit':SOURCE,'sourceTree':TREE}))
        original=request.read_bytes()
        archive=self.root/'android.tar.gz'
        b.pack(self.inputs,archive,SOURCE,TREE,'android')
        dest=self.root/'android-inputs'; b.extract(archive,dest)
        product=self.root/'separate frozen product'
        with patch.object(b,'source_identity',return_value=TREE), patch.object(b.subprocess,'run') as run:
            b.run(dest,'android',None,SOURCE,product)
            args=run.call_args.args[0]
            helper=ROOT/'scripts/build-android-artifacts.py'
            self.assertEqual(args[1:4],[str(helper),'--execution-helper-sha256',b.sha(helper)])
            self.assertEqual(args[args.index('--source')+1],str(product))
            self.assertEqual((dest/'android-release-inputs.json').read_bytes(),original)
            self.assertEqual(run.call_args.kwargs['cwd'],product)

    def test_existing_and_bootstrap_android_use_real_producer_secret_names(self):
        for name in ('release.yml', 'release-bootstrap.yml'):
            text=(ROOT/'.github/workflows'/name).read_text()
            for key,secret in [('KEYSTORE_PASSWORD','BACKPLANE_ANDROID_KEYSTORE_PASSWORD'),
                               ('KEY_ALIAS','BACKPLANE_ANDROID_KEY_ALIAS'),
                               ('KEY_PASSWORD','BACKPLANE_ANDROID_KEY_PASSWORD')]:
                self.assertIn(key+': ${{ secrets.'+secret+' }}',text)
                self.assertNotIn('          '+secret+':',text)

    def test_execution_records_distinct_metadata_and_product_identity(self):
        with patch.object(b.subprocess,'check_output',return_value='d'*40+'\n'), patch.dict(b.os.environ, {'GITHUB_SHA':'d'*40}):
            r=b.record_execution(self.root,SOURCE,TREE)
            self.assertEqual(r['workflowSourceCommit'],'d'*40)
            self.assertEqual(r['productSourceCommit'],SOURCE)
            self.assertFalse(r['configuredBuildAccepted'])
            self.assertEqual(b.record_execution(self.root,SOURCE,TREE),r)
        with patch.object(b.subprocess,'check_output',return_value='e'*40+'\n'), patch.dict(b.os.environ, {'GITHUB_SHA':'d'*40}), self.assertRaises(ValueError):
            b.record_execution(self.root,SOURCE,TREE)

    def test_https_without_credentials_only(self):
        for url in ('http://example.com/x','https://user:pass@example.com/x','https://example.com:8443/x','https://example.com/x#fragment'):
            with self.subTest(url=url), self.assertRaises(ValueError): b.fetch(url,'c'*64,self.root/'download',SOURCE,TREE,'unix-native')

    def test_wrong_download_digest_never_extracts(self):
        archive=self.packet()
        class Response(io.BytesIO):
            url='https://example.com/packet'
        with patch.object(b.urllib.request,'urlopen',return_value=Response(archive.read_bytes())), self.assertRaises(ValueError):
            b.fetch('https://example.com/packet','c'*64,self.root/'download',SOURCE,TREE,'unix-native')
        self.assertFalse((self.root/'download').exists())


if __name__=='__main__': unittest.main()
