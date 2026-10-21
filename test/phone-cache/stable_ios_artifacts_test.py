"""Pure source/control cases; never runs Xcode, security, codesign or a device."""
from pathlib import Path
import copy
import datetime
import hashlib
import importlib.util
import json
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('ios_producer', ROOT / 'scripts/build-ios-artifacts.py')
P = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(P)


class Controls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.files = {}
        for name in ['scripts/build-ios-artifacts.py', 'mobile/ios/Backplane.xcodeproj/project.pbxproj',
                     'mobile/ios/Info.plist', 'mobile/ios/IslandInfo.plist']:
            p = self.root / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes((ROOT / name).read_bytes())
            self.files[name] = P.sha(p)
        def pinned(name, data):
            p = self.root / name; p.write_text(data); return {'path': name, 'sha256': P.sha(p)}
        cert = b'fictional public certificate fixture; not a signing identity'
        profiles = {k: dict(pinned(k + '.mobileprovision', k), uuid='12345678-1234-1234-1234-123456789012') for k in ['app', 'island']}
        bridge = pinned('bridge.js', 'qualified fixture')
        self.c = {'schema': 1, 'release': 'v0.12.0', 'channel': 'release', 'sourceCommit': 'a'*40, 'sourceTree': 'b'*40,
                  'bundle_id': 'dev.backplane.mobile', 'build_number': '42', 'published_build_number_floor': '41',
                  'build_ledger': pinned('ledger.json', json.dumps({'scope':'ios-distribution-builds',
                      'bundle_id':'dev.backplane.mobile','highest_build_number':'41'})),
                  'source_files': self.files, 'bridge': bridge,
                  'bridge_qualification': pinned('qualification.json', json.dumps({'bridge_sha256':bridge['sha256']})),
                  'source_prequalification': pinned('prequalification.json', json.dumps({'status':'ACCEPTED_FOR_ARTIFACT_BUILD',
                      'scope':'source-bridge-native-path','artifact_runtime_accepted':False,'source_files':self.files,
                      'bridge_sha256':bridge['sha256'],'release':'v0.12.0','channel':'release','sourceCommit':'a'*40,'sourceTree':'b'*40})),
                  'signing': {'style':'manual','method':'app-store-connect','allow_provisioning_updates':False,'allow_upload':False,
                      'keychain_policy':'already-authorized-noninteractive',
                      'team_id':'ABCDEFGHIJ','application_identifier_prefix':'ABCDEFGHIJ',
                      'certificate_sha256':hashlib.sha256(cert).hexdigest(),'certificate_sha1':hashlib.sha1(cert).hexdigest(),
                      'profiles':profiles,'entitlements':{'app':{'aps-environment':'production'},'island':{}}}}
        self.profile = {'UUID':profiles['app']['uuid'],'TeamIdentifier':['ABCDEFGHIJ'],
                        'ApplicationIdentifierPrefix':['ABCDEFGHIJ'], 'DeveloperCertificates':[cert],
                        'ExpirationDate':datetime.datetime.now()+datetime.timedelta(days=1),
                        'Entitlements':{'application-identifier':'ABCDEFGHIJ.dev.backplane.mobile','get-task-allow':False}}
        self.public = {'configuredPublicIdentity': {'TEAM_ID':'ABCDEFGHIJ', 'BUNDLE_ID':'dev.backplane.mobile'},
                       'profiles': [{'uuid':profiles[k]['uuid'],'sha256':profiles[k]['sha256'],
                           'applicationIdentifier':'ABCDEFGHIJ.dev.backplane.mobile'+('.island' if k=='island' else ''),
                           'teamIdentifier':['ABCDEFGHIJ'],'debuggable':False,
                           'certificateSha256':[self.c['signing']['certificate_sha256']]} for k in ['app','island']]}
        self.c['signing_public_identity'] = pinned('public-identity.json', json.dumps(self.public))

    def validate(self, c=None): return P.validate(c or self.c, self.root, self.root)

    def test_valid_tuple_is_source_prequalification_only(self):
        self.assertEqual(self.validate()[0], self.root/'bridge.js')

    def test_counter_and_ledger_are_explicit(self):
        for value in [None, '', '41', '1', True]:
            c=copy.deepcopy(self.c); c['build_number']=value
            with self.subTest(value=value), self.assertRaises(P.InputError): self.validate(c)
        c=copy.deepcopy(self.c);c['published_build_number_floor']='40'
        with self.assertRaises(P.InputError):self.validate(c)

    def test_missing_certificate_or_team_never_falls_back(self):
        for key in ['certificate_sha1','certificate_sha256','team_id','application_identifier_prefix']:
            c=copy.deepcopy(self.c);del c['signing'][key]
            with self.subTest(key=key),self.assertRaises(P.InputError):self.validate(c)

    def test_root_configured_distribution_bundle_is_not_debug_example(self):
        c=copy.deepcopy(self.c);public=copy.deepcopy(self.public)
        c['bundle_id']='dev.backplane.works';c['signing']['team_id']='UZ24P5LGTB'
        c['signing']['application_identifier_prefix']='UZ24P5LGTB'
        public['configuredPublicIdentity']={'TEAM_ID':'UZ24P5LGTB','BUNDLE_ID':'dev.backplane.works'}
        for i,k in enumerate(['app','island']):
            public['profiles'][i]['teamIdentifier']=['UZ24P5LGTB']
            public['profiles'][i]['applicationIdentifier']='UZ24P5LGTB.dev.backplane.works'+('.island' if k=='island' else '')
        P.check_public_identity(public,c)
        c['bundle_id']='dev.backplane.mobile'
        with self.assertRaises(P.InputError):P.check_public_identity(public,c)

    def test_root_public_profile_and_certificate_binding(self):
        for key,value in [('team_id','OTHERTEAM1'),('certificate_sha256','0'*64)]:
            c=copy.deepcopy(self.c);c['signing'][key]=value
            with self.subTest(key=key),self.assertRaises(P.InputError):P.check_public_identity(self.public,c)
        c=copy.deepcopy(self.c);c['signing']['profiles']['app']['sha256']='0'*64
        with self.assertRaises(P.InputError):P.check_public_identity(self.public,c)

    def test_no_upload_or_automatic_signing_policy(self):
        for key,value in [('allow_upload',True),('allow_provisioning_updates',True),('style','automatic')]:
            c=copy.deepcopy(self.c);c['signing'][key]=value
            with self.subTest(key=key),self.assertRaises(P.InputError):self.validate(c)
        options=P.export_options(self.c)
        self.assertEqual(options['destination'],'export')
        self.assertFalse(options['manageAppVersionAndBuildNumber'])
        self.assertEqual(set(options['provisioningProfiles']),{'dev.backplane.mobile','dev.backplane.mobile.island'})

    def test_unbuilt_artifact_runtime_acceptance_rejected(self):
        spec=self.c['source_prequalification'];p=self.root/spec['path'];q=json.loads(p.read_text())
        q['artifact_runtime_accepted']=True;p.write_text(json.dumps(q));spec['sha256']=P.sha(p)
        with self.assertRaises(P.InputError):self.validate()

    def test_source_escape_and_secret_inputs_rejected(self):
        for name in ['../escape','mobile/ios/signing.env','mobile/ios/key.p8','mobile/ios/Backplane/bridge.js']:
            c=copy.deepcopy(self.c);c['source_files'][name]='0'*64
            with self.subTest(name=name),self.assertRaises(P.InputError):self.validate(c)

    def test_profile_exact_identity_and_distribution(self):
        P.check_profile(self.profile,self.c,'app')
        for changes in [{'TeamIdentifier':['OTHERTEAM1']},{'UUID':'other'}, {'ProvisionedDevices':['device']},
                        {'ProvisionsAllDevices':True},{'DeveloperCertificates':[b'wrong']},
                        {'ExpirationDate':datetime.datetime.now()-datetime.timedelta(days=1)}]:
            profile=dict(self.profile,**changes)
            with self.subTest(changes=list(changes)),self.assertRaises(P.InputError):P.check_profile(profile,self.c,'app')
        for key,value in [('application-identifier','ABCDEFGHIJ.*'),('get-task-allow',True)]:
            profile=copy.deepcopy(self.profile);profile['Entitlements'][key]=value
            with self.assertRaises(P.InputError):P.check_profile(profile,self.c,'app')

    def test_real_native_metadata_requires_device_version_and_counter(self):
        info={'CFBundleIdentifier':'dev.backplane.mobile','CFBundleShortVersionString':'0.12.0','CFBundleVersion':'42',
              'DTPlatformName':'iphoneos','CFBundleSupportedPlatforms':['iPhoneOS']}
        P.check_info(info,self.c,'dev.backplane.mobile')
        for changes in [{'CFBundleShortVersionString':'0.1.0'},{'CFBundleVersion':'1'},{'DTPlatformName':'iphonesimulator'},
                        {'CFBundleSupportedPlatforms':['iPhoneSimulator']},{'CFBundleIdentifier':'other.app'}]:
            with self.subTest(changes=changes),self.assertRaises(P.InputError):P.check_info(dict(info,**changes),self.c,'dev.backplane.mobile')

    def test_ipa_archive_paths_rejected_before_extraction(self):
        path=self.root/'test.ipa'
        with zipfile.ZipFile(path,'w') as z:z.writestr('../escape','bad')
        with zipfile.ZipFile(path) as z,self.assertRaises(P.InputError):P.safe_ipa(z)

    def test_no_platform_commands_on_non_mac(self):
        p=self.root/'inputs.json';p.write_text(json.dumps(self.c));out=self.root/'output'
        with patch.object(P.platform,'system',return_value='Linux'),patch.object(P.subprocess,'run') as run:
            with self.assertRaises(P.InputError):P.build(p,self.root,out)
            run.assert_not_called()
        self.assertFalse(out.exists())

    def test_missing_prepared_keychain_stops_before_any_command(self):
        p=self.root/'inputs.json';p.write_text(json.dumps(self.c));out=self.root/'output'
        with patch.object(P.platform,'system',return_value='Darwin'),patch.object(P.subprocess,'run') as run:
            with self.assertRaises(P.InputError):P.build(p,self.root,out)
            run.assert_not_called()
        self.assertFalse(out.exists())

    def test_wrapper_remains_runtime_pending(self):
        p=self.root/'fixture.ipa';p.write_bytes(b'not an actual IPA; schema fixture only')
        w=P.wrapper(self.c,p,'ios-ipa',[],'Payload/Backplane.app/bridge.js',{},self.c['bridge']['sha256'])
        self.assertEqual(w['kind'],'backplane-target-package');self.assertEqual(w['buildNumber'],'42')
        self.assertEqual(w['configuration'],'Release');self.assertFalse(w['artifactRuntimeAccepted'])
        self.assertEqual(w['qualification'],'BUILT_PENDING_TARGET_RUNTIME_ACCEPTANCE')
        self.assertEqual(w['archive']['sha256'],P.sha(p))


if __name__=='__main__':unittest.main()
