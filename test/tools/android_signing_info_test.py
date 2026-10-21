#!/usr/bin/env python3
"""Public signer transport/privacy checks; no app or real release secret use."""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('public_signer',ROOT/'scripts/android-signing-info.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class SigningInfoTest(unittest.TestCase):
    def env(self):
        return {'GITHUB_SHA':'b'*40,'BACKPLANE_ANDROID_KEYSTORE_BASE64':base64.b64encode(b'synthetic store').decode(),
                'KEYSTORE_PASSWORD':'synthetic-password','KEY_ALIAS':'fixture','PATH':os.environ['PATH'],
                'UNRELATED_SECRET':'must-not-reach-child'}

    def test_export_uses_environment_password_private_mode_and_removes_store(self):
        observed=[];certificate=b'\x30'+b'x'*50
        def run(args,**kwargs):
            observed.append((args,kwargs))
            if '-exportcert' in args:
                store=Path(args[args.index('-keystore')+1]);self.assertEqual(stat.S_IMODE(store.stat().st_mode),0o600)
                self.assertEqual(stat.S_IMODE(store.parent.stat().st_mode),0o700)
                self.assertEqual(store.read_bytes(),b'synthetic store');self.private_path=store
                self.assertNotIn('synthetic-password',args)
                self.assertNotIn('BACKPLANE_ANDROID_KEYSTORE_BASE64',kwargs['env'])
                self.assertNotIn('UNRELATED_SECRET',kwargs['env'])
                return SimpleNamespace(returncode=0,stdout=certificate,stderr=b'')
            self.assertNotIn('KEYSTORE_PASSWORD',kwargs['env'])
            return SimpleNamespace(returncode=0,stdout=b'',stderr=b'')
        with patch.object(m.shutil,'which',side_effect=lambda n:'/tool/'+n),patch.object(m.subprocess,'run',side_effect=run):
            receipt=m.public_signer(self.env(),'a'*40)
        self.assertEqual(receipt['certificateSha256'],hashlib.sha256(certificate).hexdigest())
        self.assertFalse(self.private_path.exists())
        self.assertFalse(receipt['appBuildExecuted']);self.assertFalse(receipt['privateInputsRetained'])
        self.assertNotIn('synthetic-password',json.dumps(receipt));self.assertNotIn('fixture',json.dumps(receipt))
        self.assertEqual(len(observed),2)

    def test_failed_export_keeps_no_store_or_secret_error(self):
        def run(args,**kwargs):
            self.private_path=Path(args[args.index('-keystore')+1])
            return SimpleNamespace(returncode=1,stdout=b'',stderr=b'synthetic-password private failure')
        with patch.object(m.shutil,'which',return_value='/tool'),patch.object(m.subprocess,'run',side_effect=run):
            with self.assertRaisesRegex(ValueError,'Configured certificate export failed') as caught:m.public_signer(self.env(),'a'*40)
        self.assertNotIn('synthetic-password',str(caught.exception));self.assertFalse(self.private_path.exists())

    def test_missing_or_invalid_inputs_fail_before_tools(self):
        for field in ('KEY_ALIAS','KEYSTORE_PASSWORD','BACKPLANE_ANDROID_KEYSTORE_BASE64','GITHUB_SHA'):
            env=self.env();env.pop(field)
            with self.subTest(field=field),patch.object(m.shutil,'which') as which,self.assertRaises(ValueError):
                m.public_signer(env,'a'*40)
            which.assert_not_called()
        with self.assertRaises(ValueError):m.public_signer(self.env(),'not-a-commit')

    @unittest.skipUnless(shutil.which('keytool') and shutil.which('openssl'),'actual JDK/OpenSSL not installed')
    def test_actual_tools_with_disposable_synthetic_keystore(self):
        with tempfile.TemporaryDirectory(prefix='bp-signer-fixture-') as tmp:
            store=Path(tmp)/'fixture.p12';env=os.environ.copy();env['BP_FIXTURE_STORE_PASSWORD']='synthetic-only-password'
            r=subprocess.run(['keytool','-genkeypair','-alias','fixture','-dname','CN=DisposableOfflineFixture',
                              '-keyalg','EC','-groupname','secp256r1','-validity','1','-storetype','PKCS12',
                              '-keystore',str(store),'-storepass:env','BP_FIXTURE_STORE_PASSWORD',
                              '-keypass:env','BP_FIXTURE_STORE_PASSWORD'],env=env,capture_output=True,timeout=30)
            self.assertEqual(r.returncode,0,'synthetic keytool setup failed')
            listing=subprocess.run(['keytool','-list','-v','-alias','fixture','-keystore',str(store),
                                    '-storepass:env','BP_FIXTURE_STORE_PASSWORD'],env=env,capture_output=True,text=True,timeout=30)
            self.assertEqual(listing.returncode,0)
            expected=re.search(r'SHA256:\s*([0-9A-F:]+)',listing.stdout).group(1).replace(':','').lower()
            query={'GITHUB_SHA':'b'*40,'PATH':env['PATH'],'KEY_ALIAS':'fixture','KEYSTORE_PASSWORD':env['BP_FIXTURE_STORE_PASSWORD'],
                   'BACKPLANE_ANDROID_KEYSTORE_BASE64':base64.b64encode(store.read_bytes()).decode()}
            receipt=m.public_signer(query,'a'*40)
            self.assertEqual(receipt['certificateSha256'],expected)


if __name__=='__main__':unittest.main()
