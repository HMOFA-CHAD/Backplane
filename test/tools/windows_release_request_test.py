"""No native process launches: check workflow argument/path/provenance refusal."""
import importlib.util
import hashlib
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch, Mock

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('request', ROOT/'scripts/windows-release-request.py')
request=importlib.util.module_from_spec(spec);spec.loader.exec_module(request)

class RequestTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);(self.root/'runtime').mkdir();(self.root/'native').mkdir()
        (self.root/'inputs.tar.gz').write_bytes(b'not a native artifact, offline fixture')
        self.row={'schema':1,'sourceCommit':'a'*40,'version':'0.12.0','channel':'release','operation':'native',
                  'runtimePayload':'runtime','runtimeManifestSha256':'b'*64,'inputArchive':'inputs.tar.gz',
                  'inputSha256':hashlib.sha256((self.root/'inputs.tar.gz').read_bytes()).hexdigest()}
    def plan(self,operation='native'):
        return request.plan(self.root,self.row,operation,'a'*40,'0.12.0')
    def test_native_is_argument_array_without_config_values(self):
        command=self.plan();self.assertEqual(command[0],'native');self.assertNotIn('shell',command)
        self.assertEqual(command[-1],'build/windows-service-native')
    def test_actual_metadata_import_preserves_separate_product_root(self):
        row=self.root/'request.json'
        import json
        row.write_text(json.dumps(self.row))
        module=SimpleNamespace(main=Mock())
        loader=Mock()
        spec=SimpleNamespace(loader=loader)
        original=request.sys.dont_write_bytecode
        try:
            with patch.object(request.sys,'argv',['request','native',str(row)]), patch.dict(request.os.environ,{'BACKPLANE_FROZEN_COMMIT':'a'*40,'BACKPLANE_VERSION':'0.12.0'}), patch.object(request.Path,'cwd',return_value=self.root), patch.object(request.importlib.util,'spec_from_file_location',return_value=spec) as locate, patch.object(request.importlib.util,'module_from_spec',return_value=module):
                request.main()
                self.assertEqual(locate.call_args.args[1],ROOT/'scripts/windows-service.py')
                self.assertEqual(module.ROOT,self.root)
                loader.exec_module.assert_called_once_with(module)
                self.assertTrue(request.sys.dont_write_bytecode)
                self.assertEqual(module.main.call_args.args[0],self.plan())
        finally:
            request.sys.dont_write_bytecode=original
    def test_mismatched_source_version_operation_refused(self):
        for key,value in [('version','0.11.2'),('sourceCommit','b'*40),('operation','package'),('channel','dev')]:
            old=self.row[key];self.row[key]=value
            with self.assertRaises(ValueError):self.plan()
            self.row[key]=old
    def test_changed_or_missing_c_archive_refused(self):
        (self.root/'inputs.tar.gz').write_bytes(b'changed')
        with self.assertRaises(ValueError):self.plan()
    def test_paths_cannot_escape_or_use_reparse_links(self):
        for value in ('../runtime','/runtime','C:runtime','runtime/../runtime'):
            self.row['runtimePayload']=value
            with self.assertRaises((ValueError,OSError)):self.plan()
        self.row['runtimePayload']='linked';(self.root/'linked').symlink_to(self.root/'runtime',target_is_directory=True)
        with self.assertRaises(ValueError):self.plan()
    def test_unsigned_internal_never_promoted_by_package_operation(self):
        self.row.update(operation='package',nativeDirectory='native',signingPolicy='unsigned-internal')
        with self.assertRaises(ValueError):self.plan('package')
        self.row.update(signingPolicy='authenticode',signingThumbprint='C'*40)
        (self.root/'control.json').write_bytes(b'offline fixture only')
        self.row['managedControlReceipt']={'path':'control.json','sha256':hashlib.sha256((self.root/'control.json').read_bytes()).hexdigest()}
        command=self.plan('package');self.assertEqual(command[0],'package')
        self.assertIn('authenticode',command)
        self.assertEqual(command[command.index('--signing-thumbprint')+1],'C'*40)

    def test_resident_portable_unsigned_skips_optional_certificate_and_control(self):
        self.row.update(operation='package',nativeDirectory='native',signingPolicy='unsigned-portable-allowed',
                        lifecyclePolicy={'mode':'resident-service','managedStop':False,'managedUpdate':False})
        command=self.plan('package')
        self.assertIn('unsigned-portable-allowed',command)
        self.assertNotIn('--signing-thumbprint',command)
        self.assertNotIn('--managed-control-receipt',command)
