"""Source/control tests only: no SDK, Gradle, signing or platform build."""
from pathlib import Path
import copy
import hashlib
import importlib.util
import json
import os
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('producer', ROOT / 'scripts/build-android-artifacts.py')
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)
BASELINE = 'd0bf89dfe800a49575f7a56bf305197e1399ddef7ce9b87b9b911a253e04d458'


class Controls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.files = {}
        for name in ['mobile/android/gradlew', 'mobile/android/build.gradle.kts',
                     'mobile/android/settings.gradle.kts', 'mobile/android/app/build.gradle.kts',
                     'scripts/build-android-artifacts.py']:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / name).read_bytes())
            self.files[name] = P.sha(target)
        def pinned(name, content):
            path = self.root / name
            path.write_text(content)
            return {'path': name, 'sha256': P.sha(path)}
        bridge = pinned('bridge.js', 'qualified fixture')
        self.config = {'schema': 1, 'release': 'v0.12.0', 'version_code': 2,
                       'channel': 'release', 'sourceCommit': 'a' * 40, 'sourceTree': 'b' * 40,
                       'published_version_code_floor': 1, 'expected_signer_sha256': BASELINE,
                       'source_files': self.files, 'bridge': bridge,
                       'bridge_qualification': pinned('qualification.json', json.dumps({'bridge_sha256': bridge['sha256']})),
                       'source_prequalification': pinned('prequalification.json', json.dumps({'status': 'ACCEPTED_FOR_ARTIFACT_BUILD',
                           'scope': 'source-bridge-native-path', 'artifact_runtime_accepted': False,
                           'release': 'v0.12.0', 'bridge_sha256': bridge['sha256'], 'source_files': self.files,
                           'channel': 'release', 'sourceCommit': 'a' * 40, 'sourceTree': 'b' * 40})),
                       'bundletool': pinned('bundletool.jar', 'test fixture only')}

    def valid(self, config=None):
        return P.validate(config or self.config, self.root, self.root)

    def test_accepted_tuple_and_explicit_historical_identity(self):
        self.assertEqual(self.valid()[0], self.root / 'bridge.js')
        self.assertEqual(P.certificate_hashes('Signer #1 certificate SHA-256 digest: ' + BASELINE), {BASELINE})
        self.assertEqual(P.certificate_hashes('Owner: CN=Android Debug\nSHA256: ' + ':'.join(BASELINE[i:i+2].upper() for i in range(0,64,2))), {BASELINE})

    def test_version_code_cannot_reuse_or_guess(self):
        for code in [None, True, 1, 0, 2100000001]:
            c = copy.deepcopy(self.config); c['version_code'] = code
            with self.subTest(code=code), self.assertRaises(P.InputError): self.valid(c)

    def test_stale_source_or_bridge_rejected(self):
        p = self.root / 'mobile/android/app/build.gradle.kts'
        p.write_text(p.read_text() + '\n// newer source\n')
        with self.assertRaises(P.InputError): self.valid()
        self.files[str(p.relative_to(self.root))] = P.sha(p)
        # Even updating source pins cannot reuse an acceptance of the old tuple.
        with self.assertRaises(P.InputError): self.valid()

    def test_qualification_requires_exact_bridge(self):
        self.config['bridge_qualification']['sha256'] = hashlib.sha256(b'wrong').hexdigest()
        with self.assertRaises(P.InputError): self.valid()

    def test_prequalification_cannot_claim_unbuilt_artifact_runtime(self):
        spec = self.config['source_prequalification']
        path = self.root / spec['path']; original = json.loads(path.read_text())
        for changes in [{'status': 'ACCEPTED_FOR_RELEASE'}, {'scope': 'final-artifact-runtime'},
                        {'artifact_runtime_accepted': True}, {'artifact_runtime_accepted': None}]:
            receipt = dict(original, **changes); path.write_text(json.dumps(receipt)); spec['sha256'] = P.sha(path)
            with self.subTest(changes=changes), self.assertRaises(P.InputError): self.valid()
        path.write_text(json.dumps(original)); spec['sha256'] = P.sha(path)
        self.valid()

    def test_no_source_escape_or_local_properties(self):
        for name in ['../escape', '/absolute', 'mobile/android/app/../../outside',
                     'mobile/android/local.properties', 'mobile/android/app/build/generated.kt']:
            c = copy.deepcopy(self.config); c['source_files'][name] = '0' * 64
            with self.subTest(name=name), self.assertRaises(P.InputError): self.valid(c)

    def test_missing_sdk_stops_before_subprocess_or_output(self):
        inputs = self.root / 'inputs.json'; inputs.write_text(json.dumps(self.config))
        output = self.root / 'artifacts'
        with patch.dict(os.environ, {}, clear=True), patch.object(P.subprocess, 'run') as run:
            with self.assertRaises(P.InputError): P.build(inputs, self.root, output)
            run.assert_not_called()
        self.assertFalse(output.exists())

    def test_actual_manifest_metadata_guards(self):
        xml = '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="dev.backplane.mobile" android:versionName="0.12.0" android:versionCode="2"><application android:debuggable="false"/></manifest>'
        P.check_manifest(xml, '0.12.0', 2)
        for bad in [xml.replace('0.12.0', '0.1.0'), xml.replace('versionCode="2"', 'versionCode="1"'),
                    xml.replace('debuggable="false"', 'debuggable="true"'), xml.replace('dev.backplane.mobile', 'other.app')]:
            with self.assertRaises(P.InputError): P.check_manifest(bad, '0.12.0', 2)

    def test_embedded_bridge_bytes_and_duplicate_member(self):
        file = self.root / 'artifact.zip'; data = b'qualified bridge'
        with zipfile.ZipFile(file, 'w') as z: z.writestr('assets/bridge.js', data)
        P.check_embedded(file, 'assets/bridge.js', hashlib.sha256(data).hexdigest())
        wrapper = P.target_package(self.config, file, 'apk', hashlib.sha256(data).hexdigest())
        self.assertEqual(wrapper['kind'], 'backplane-target-package')
        self.assertEqual(wrapper['sourceTree'], 'b' * 40)
        self.assertEqual(wrapper['members'], [{'path': 'assets/bridge.js', 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}])
        self.assertEqual(wrapper['archive']['sha256'], P.sha(file))
        self.assertEqual(wrapper['bridgeMember'], 'assets/bridge.js')
        self.assertEqual(wrapper['actualNativeVersion'], '0.12.0')
        self.assertEqual(wrapper['configuration'], 'Release')
        self.assertEqual(wrapper['signing']['certificateSha256'], BASELINE)
        self.assertFalse(wrapper['artifactRuntimeAccepted'])
        self.assertEqual(wrapper['qualification'], 'BUILT_PENDING_TARGET_RUNTIME_ACCEPTANCE')
        with self.assertRaises(P.InputError): P.check_embedded(file, 'assets/bridge.js', '0' * 64)
        with zipfile.ZipFile(file, 'a') as z:
            import warnings
            with warnings.catch_warnings():
                warnings.simplefilter('ignore'); z.writestr('assets/bridge.js', data)
        with self.assertRaises(P.InputError): P.check_embedded(file, 'assets/bridge.js', hashlib.sha256(data).hexdigest())


if __name__ == '__main__': unittest.main()
