"""Focused helper/source identity boundary controls; never builds or signs."""
from pathlib import Path
import importlib.util,json,shutil,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('helper',ROOT/'scripts/build-android-artifacts.py');P=importlib.util.module_from_spec(spec);spec.loader.exec_module(P)
class ExecutionHelper(unittest.TestCase):
    def test_explicit_helper_keeps_original_source_and_prequalification_pins(self):
        packet=ROOT/'build/phone-cache/android-stable-inputs-01/packet'
        source=ROOT/'build/phone-cache/android-stable-inputs-01/source'
        config=json.loads((packet/'android-release-inputs.json').read_text())
        self.assertEqual(config['source_files']['scripts/build-android-artifacts.py'],'97be5807e8586025c680717af3dc7d44c225fdf91f7ef8dbffbe6f81c62adb9f')
        with self.assertRaises(P.InputError):P.validate(config,source,packet)
        digest=P.sha(ROOT/'scripts/build-android-artifacts.py')
        P.validate(config,source,packet,digest);P.verify_source_git(config,source)
        for wrong in ['0'*64,True,'wrong']:
            with self.subTest(wrong=wrong),self.assertRaises(P.InputError):P.validate(config,source,packet,wrong)
        with tempfile.TemporaryDirectory() as directory:
            temp=Path(directory)
            for name in config['source_files']:
                target=temp/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source/name,target)
            P.validate(config,temp,packet,digest)
            (temp/'mobile/android/app/build.gradle.kts').write_text('newer unqualified source')
            with self.assertRaises(P.InputError):P.validate(config,temp,packet,digest)
        changed=dict(config,source_files=dict(config['source_files']))
        changed['source_files']['scripts/build-android-artifacts.py']=digest
        with self.assertRaises(P.InputError):P.validate(changed,source,packet,digest)
if __name__=='__main__':unittest.main()
