#!/usr/bin/env python3
"""Local Mac Release archive + IPA export from explicit, pinned inputs.

No JS emission, simulator/device action, profile installation, keychain unlock,
provisioning update or upload. Invoke through work_run/native-build only after
root supplies the signing policy, store ledger and source prequalification.
"""
from pathlib import Path, PurePosixPath
import argparse
import datetime
import hashlib
import json
import os
import platform
import plistlib
import re
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import zipfile


class InputError(ValueError):
    pass


def require(ok, message):
    if not ok: raise InputError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def pinned(spec, base):
    require(isinstance(spec, dict), 'Missing pinned input')
    p = Path(spec.get('path', ''))
    if not p.is_absolute(): p = base / p
    require(p.is_file() and sha(p) == spec.get('sha256'), 'Pinned input hash mismatch')
    return p.resolve()


def build_number(value):
    require(isinstance(value, str) and re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', value),
            'Explicit numeric iOS build number and ledger floor required')
    parts = tuple(int(n) for n in value.split('.'))
    return parts + (0,) * (3 - len(parts))


def check_public_identity(identity, c):
    configured = identity.get('configuredPublicIdentity', {})
    s = c['signing']
    require(configured.get('BUNDLE_ID') == c['bundle_id'] and configured.get('TEAM_ID') == s['team_id'],
            'Signing policy differs from root configured public bundle/team')
    for key in ['app', 'island']:
        expected = s['profiles'][key]
        bundle = c['bundle_id'] + ('.island' if key == 'island' else '')
        require(any(row.get('uuid') == expected['uuid'] and row.get('sha256') == expected['sha256'] and
                    row.get('applicationIdentifier') == s['application_identifier_prefix'] + '.' + bundle and
                    row.get('teamIdentifier') == [s['team_id']] and row.get('debuggable') is False and
                    s['certificate_sha256'] in row.get('certificateSha256', [])
                    for row in identity.get('profiles', [])),
                'Signing profile/certificate differs from root public identity receipt')


def validate(c, source, base):
    require(c.get('schema') == 1 and c.get('channel') == 'release', 'Release input schema/channel required')
    require(re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', c.get('release', '')), 'Explicit stable version required')
    require(all(re.fullmatch(r'[0-9a-f]{40}', c.get(k, '')) for k in ['sourceCommit', 'sourceTree']),
            'Exact source commit/tree required')
    require(build_number(c.get('build_number')) > build_number(c.get('published_build_number_floor')),
            'Build number must exceed root store ledger floor')
    require(re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', c.get('bundle_id', '')),
            'Explicit root-configured bundle identity required')
    ledger = pinned(c.get('build_ledger'), base)
    observed = json.loads(ledger.read_text())
    require(observed.get('scope') == 'ios-distribution-builds' and observed.get('bundle_id') == c['bundle_id'] and
            observed.get('highest_build_number') == c['published_build_number_floor'], 'Root store ledger does not bind build floor')
    files = c.get('source_files')
    require(isinstance(files, dict) and {'scripts/build-ios-artifacts.py',
            'mobile/ios/Backplane.xcodeproj/project.pbxproj', 'mobile/ios/Info.plist',
            'mobile/ios/IslandInfo.plist'} <= files.keys(), 'Frozen iOS source closure required')
    for name, digest in files.items():
        p = PurePosixPath(name)
        require(not p.is_absolute() and '..' not in p.parts and str(p) == name and
                (name.startswith('mobile/ios/') or name == 'scripts/build-ios-artifacts.py'), 'Source boundary violation')
        require(not any(v in p.parts for v in ['build', '.git', 'xcuserdata']) and
                p.name not in ['bridge.js', 'signing.env'] and p.suffix != '.p8', 'Generated/local signing input in source closure')
        require((source / name).is_file() and not (source / name).is_symlink() and sha(source / name) == digest,
                'Frozen source hash mismatch')
    require(sha(Path(__file__)) == files['scripts/build-ios-artifacts.py'], 'Producer is not pinned source')
    bridge = pinned(c.get('bridge'), base)
    qualification = pinned(c.get('bridge_qualification'), base)
    def strings(v):
        if isinstance(v, dict):
            for item in v.values(): yield from strings(item)
        elif isinstance(v, list):
            for item in v: yield from strings(item)
        elif isinstance(v, str): yield v
    require(sha(bridge) in set(strings(json.loads(qualification.read_text()))), 'Qualification does not bind bridge')
    prequal = pinned(c.get('source_prequalification'), base)
    q = json.loads(prequal.read_text())
    require(q.get('status') == 'ACCEPTED_FOR_ARTIFACT_BUILD' and q.get('scope') == 'source-bridge-native-path' and
            q.get('artifact_runtime_accepted') is False and q.get('source_files') == files and
            q.get('bridge_sha256') == sha(bridge) and
            all(q.get(k) == c[k] for k in ['release', 'sourceCommit', 'sourceTree', 'channel']),
            'Source prequalification must bind tuple without claiming artifact runtime acceptance')
    signing = c.get('signing', {})
    require(signing.get('style') == 'manual' and signing.get('method') == 'app-store-connect' and
            signing.get('allow_provisioning_updates') is False and signing.get('allow_upload') is False and
            signing.get('keychain_policy') == 'already-authorized-noninteractive',
            'Explicit manual local-export-only signing policy required')
    for key, pattern in [('team_id', r'[A-Z0-9]{10}'), ('application_identifier_prefix', r'[A-Z0-9]{10}'),
                         ('certificate_sha1', r'[0-9a-f]{40}'), ('certificate_sha256', r'[0-9a-f]{64}')]:
        require(re.fullmatch(pattern, signing.get(key, '')), 'Explicit signing team/prefix/public certificate required')
    profiles = signing.get('profiles', {})
    entitlements = signing.get('entitlements', {})
    require(set(profiles) == {'app', 'island'} and set(entitlements) == {'app', 'island'}, 'Both app and island policy required')
    for key in ['app', 'island']:
        pinned(profiles[key], base)
        require(re.fullmatch(r'[0-9A-Fa-f-]{36}', profiles[key].get('uuid', '')), 'Explicit provisioning profile UUID required')
        require(isinstance(entitlements[key], dict) and entitlements[key].get('get-task-allow', False) is False,
                'Distribution entitlements must not permit debugging')
    public_identity = pinned(c.get('signing_public_identity'), base)
    check_public_identity(json.loads(public_identity.read_text()), c)
    return bridge, qualification, prequal, ledger


def verify_git(c, source):
    def git(*args):
        p = subprocess.run(['git', '-C', str(source), *args], capture_output=True, text=True)
        require(p.returncode == 0, 'Committed unchanged producer/source required')
        return p.stdout.strip()
    require(git('rev-parse', 'HEAD') == c['sourceCommit'] and git('rev-parse', 'HEAD^{tree}') == c['sourceTree'],
            'Source commit/tree mismatch')
    names = list(c['source_files'])
    git('ls-files', '--error-unmatch', '--', *names)
    git('diff', '--quiet', 'HEAD', '--', *names)


def check_profile(profile, c, key):
    s = c['signing']; ent = profile.get('Entitlements', {})
    bundle = c['bundle_id'] + ('.island' if key == 'island' else '')
    require(profile.get('UUID') == s['profiles'][key]['uuid'] and
            profile.get('TeamIdentifier') == [s['team_id']] and
            profile.get('ApplicationIdentifierPrefix') == [s['application_identifier_prefix']], 'Provisioning profile identity mismatch')
    require(ent.get('application-identifier') == s['application_identifier_prefix'] + '.' + bundle and
            ent.get('get-task-allow') is False and not profile.get('ProvisionedDevices') and
            not profile.get('ProvisionsAllDevices'), 'Exact App Store distribution profile required')
    certificates = profile.get('DeveloperCertificates', [])
    require(any(hashlib.sha256(cert).hexdigest() == s['certificate_sha256'] for cert in certificates),
            'Profile does not include approved public signing certificate')
    expiry = profile.get('ExpirationDate')
    require(isinstance(expiry, datetime.datetime) and expiry.replace(tzinfo=datetime.timezone.utc) >
            datetime.datetime.now(datetime.timezone.utc), 'Provisioning profile expired')


def check_info(info, c, bundle):
    require(info.get('CFBundleIdentifier') == bundle and info.get('CFBundleShortVersionString') == c['release'][1:] and
            info.get('CFBundleVersion') == c['build_number'], 'Actual iOS version/build/bundle mismatch')
    require(info.get('DTPlatformName') == 'iphoneos' and 'iPhoneOS' in info.get('CFBundleSupportedPlatforms', []),
            'Device iOS artifact required; simulator output rejected')


def export_options(c):
    s = c['signing']
    return {'method': 'app-store-connect', 'destination': 'export', 'teamID': s['team_id'],
            'signingStyle': 'manual', 'signingCertificate': s['certificate_sha1'],
            'provisioningProfiles': {c['bundle_id']: s['profiles']['app']['uuid'],
                                     c['bundle_id'] + '.island': s['profiles']['island']['uuid']},
            'manageAppVersionAndBuildNumber': False}


def wrapper(c, path, target, members, bridge_member, signing, bridge_sha):
    return {'schema': 1, 'kind': 'backplane-target-package', 'target': target,
            'sourceCommit': c['sourceCommit'], 'sourceTree': c['sourceTree'], 'version': c['release'][1:],
            'channel': c['channel'], 'archive': {'name': path.name, 'sha256': sha(path), 'bytes': path.stat().st_size},
            'members': members, 'bridgeMember': bridge_member, 'bridgeSha256': bridge_sha,
            'actualNativeVersion': c['release'][1:], 'configuration': 'Release', 'buildNumber': c['build_number'],
            'package': c['bundle_id'], 'signing': signing, 'qualification': 'BUILT_PENDING_TARGET_RUNTIME_ACCEPTANCE',
            'artifactRuntimeAccepted': False}


def safe_ipa(archive):
    names = archive.namelist(); require(len(names) == len(set(names)), 'Duplicate IPA member')
    for name in names:
        p = PurePosixPath(name)
        require(not p.is_absolute() and '..' not in p.parts and str(p) == name.rstrip('/') and
                (archive.getinfo(name).external_attr >> 16) & 0o170000 != 0o120000,
                'Unsafe IPA path or unsupported symbolic link')


def build(inputs, source, output):
    c = json.loads(inputs.read_text())
    bridge, qualification, prequal, ledger = validate(c, source, inputs.parent)
    require(platform.system() == 'Darwin', 'Local Mac execution required')
    require(not output.exists(), 'Output exists; inspect prior receipt instead of repeating')
    s = c['signing']; keychain = Path(s.get('keychain_path', ''))
    require(keychain.is_absolute() and keychain.is_file(), 'Explicit already available signing keychain required')
    developer = Path(c.get('developer_dir', ''))
    require(developer.is_absolute() and (developer / 'usr/bin/xcodebuild').is_file(), 'Explicit Xcode developer directory required')
    verify_git(c, source)
    output.mkdir(parents=True)
    receipt = {'status': 'FAILED_NOT_PUBLISHED', 'release': c['release'], 'sourceCommit': c['sourceCommit'],
               'sourceTree': c['sourceTree'], 'version': c['release'][1:], 'channel': c['channel'],
               'inputs_sha256': sha(inputs), 'producer_sha256': sha(Path(__file__)), 'source_files': c['source_files'],
               'bridge_sha256': sha(bridge), 'qualification_sha256': sha(qualification),
               'source_prequalification_sha256': sha(prequal), 'build_ledger_sha256': sha(ledger),
               'signing_public_identity_sha256': sha(pinned(c['signing_public_identity'], inputs.parent)),
               'artifact_runtime_accepted': False, 'next_gate': 'Root actual-artifact target runtime acceptance; all seven publication gates remain mandatory.'}
    log_path = output / 'producer.log'
    try:
        with tempfile.TemporaryDirectory(prefix='bp-ios-artifacts-') as directory, log_path.open('wb') as log:
            stage = Path(directory)
            for name in c['source_files']:
                p = stage / name; p.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source / name, p)
            ios = stage / 'mobile/ios'; shutil.copyfile(bridge, ios / 'Backplane/bridge.js')
            env = {k: os.environ[k] for k in ['HOME', 'PATH', 'TMPDIR', 'USER', 'LOGNAME', 'LANG'] if k in os.environ}
            env.update(DEVELOPER_DIR=str(developer), LC_ALL='C')
            def run(argv, capture=False):
                p = subprocess.run(argv, env=env, stdout=subprocess.PIPE if capture else log,
                                   stderr=log, timeout=1800)
                require(p.returncode == 0, 'Local archive/export/verification failed; inspect producer.log')
                return p.stdout
            receipt['toolchain'] = {'xcode': run([str(developer / 'usr/bin/xcodebuild'), '-version'], True).decode().strip(),
                'xcodebuild_sha256': sha(developer / 'usr/bin/xcodebuild'), 'codesign_sha256': sha('/usr/bin/codesign')}
            for key in ['app', 'island']:
                profile = plistlib.loads(run(['/usr/bin/security', 'cms', '-D', '-i', str(pinned(s['profiles'][key], inputs.parent))], True))
                check_profile(profile, c, key)
                (stage / (key + '.entitlements')).write_bytes(plistlib.dumps(s['entitlements'][key]))
            receipt['derived_entitlements_sha256'] = {key: sha(stage / (key + '.entitlements')) for key in ['app', 'island']}
            archive = stage / 'Backplane.xcarchive'
            command = [str(developer / 'usr/bin/xcodebuild'), '-quiet', '-project', str(ios / 'Backplane.xcodeproj'),
                       '-scheme', 'Backplane', '-configuration', 'Release', '-sdk', 'iphoneos',
                       '-destination', 'generic/platform=iOS', '-archivePath', str(archive), '-derivedDataPath', str(stage / 'dd'),
                       'MARKETING_VERSION=' + c['release'][1:], 'CURRENT_PROJECT_VERSION=' + c['build_number'],
                       'DEVELOPMENT_TEAM=' + s['team_id'], 'BASE_BUNDLE_ID=' + c['bundle_id'],
                       'CODE_SIGN_STYLE=Manual', 'CODE_SIGN_IDENTITY=' + s['certificate_sha1'],
                       'OTHER_CODE_SIGN_FLAGS=--keychain ' + shlex.quote(str(keychain)),
                       'PROVISIONING_PROFILE_SPECIFIER=$(BP_PROFILE_$(TARGET_NAME))',
                       'BP_PROFILE_Backplane=' + s['profiles']['app']['uuid'],
                       'BP_PROFILE_BackplaneIsland=' + s['profiles']['island']['uuid'],
                       'CODE_SIGN_ENTITLEMENTS=$(BP_ENTITLEMENTS_$(TARGET_NAME))',
                       'BP_ENTITLEMENTS_Backplane=' + str(stage / 'app.entitlements'),
                       'BP_ENTITLEMENTS_BackplaneIsland=' + str(stage / 'island.entitlements'), 'archive']
            receipt['archive_command'] = command
            run(command)
            def verify_app(app, phase):
                require(sha(app / 'bridge.js') == sha(bridge), 'Embedded bridge mismatch')
                found = list((app / 'PlugIns').glob('*.appex'))
                require(len(found) == 1, 'Expected exactly one island extension')
                results = {}
                for key, product in [('app', app), ('island', found[0])]:
                    bundle = c['bundle_id'] + ('.island' if key == 'island' else '')
                    check_info(plistlib.loads((product / 'Info.plist').read_bytes()), c, bundle)
                    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(product)])
                    ent = plistlib.loads(run(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(product)], True))
                    require(ent.get('get-task-allow', False) is False and
                            ent.get('application-identifier') == s['application_identifier_prefix'] + '.' + bundle and
                            ent.get('com.apple.developer.team-identifier') == s['team_id'] and
                            all(ent.get(k) == v for k,v in s['entitlements'][key].items()), 'Signed entitlements differ from explicit policy')
                    prefix = stage / ('certificate-' + key + '-' + str(len(list(stage.glob('certificate-*')))))
                    run(['/usr/bin/codesign', '-d', '--extract-certificates=' + str(prefix), str(product)])
                    cert = Path(str(prefix) + '0').read_bytes()
                    receipt.setdefault('observed_signing_certificates', []).append({'phase': phase, 'product': key,
                        'certificateSha256': hashlib.sha256(cert).hexdigest(), 'certificateSha1': hashlib.sha1(cert).hexdigest()})
                    require(hashlib.sha256(cert).hexdigest() == s['certificate_sha256'] and
                            hashlib.sha1(cert).hexdigest() == s['certificate_sha1'], 'Actual public signing certificate mismatch')
                    embedded = product / 'embedded.mobileprovision'
                    require(sha(embedded) == s['profiles'][key]['sha256'], 'Embedded provisioning profile mismatch')
                    profile = plistlib.loads(run(['/usr/bin/security', 'cms', '-D', '-i', str(embedded)], True))
                    check_profile(profile, c, key)
                    results[key] = {'bundleId': bundle, 'profileUuid': profile['UUID'], 'profileSha256': sha(embedded),
                                    'certificateSha256': hashlib.sha256(cert).hexdigest(), 'signatureVerified': True,
                                    'debuggable': False, 'entitlements': ent}
                return {'teamId': s['team_id'], 'certificateSha256': s['certificate_sha256'],
                        'signatureVerified': True, 'debuggable': False, 'products': results}
            archived_signing = verify_app(archive / 'Products/Applications/Backplane.app', 'archive')
            options = stage / 'export-options.plist'; options.write_bytes(plistlib.dumps(export_options(c)))
            receipt['export_options_sha256'] = sha(options)
            export = stage / 'export'
            run([str(developer / 'usr/bin/xcodebuild'), '-exportArchive', '-archivePath', str(archive),
                 '-exportOptionsPlist', str(options), '-exportPath', str(export)])
            ipas = list(export.glob('*.ipa')); require(len(ipas) == 1, 'Expected one local IPA export')
            unpack = stage / 'ipa'; unpack.mkdir()
            with zipfile.ZipFile(ipas[0]) as z:
                safe_ipa(z)
                ipa_members = [{'path': n, 'sha256': hashlib.sha256(z.read(n)).hexdigest(), 'bytes': z.getinfo(n).file_size}
                               for n in sorted(z.namelist()) if not z.getinfo(n).is_dir()]
            # Preserve executable permissions when verifying the locally exported IPA.
            run(['/usr/bin/ditto', '-x', '-k', str(ipas[0]), str(unpack)])
            apps = list((unpack / 'Payload').glob('*.app')); require(len(apps) == 1, 'Expected one exported app')
            exported_signing = verify_app(apps[0], 'exported-ipa')
            validate(c, source, inputs.parent); verify_git(c, source)
            packed = stage / 'archive.tar.gz'
            with tarfile.open(packed, 'w:gz') as tar: tar.add(archive, arcname='Backplane.xcarchive')
            archive_members = []
            with tarfile.open(packed) as tar:
                for item in tar.getmembers():
                    if item.isfile():
                        archive_members.append({'path': item.name, 'sha256': hashlib.sha256(tar.extractfile(item).read()).hexdigest(), 'bytes': item.size})
                    elif item.issym():
                        require(not PurePosixPath(item.linkname).is_absolute() and '..' not in PurePosixPath(item.linkname).parts,
                                'Unsafe archive symbolic link')
                        archive_members.append({'path': item.name, 'type': 'symlink', 'target': item.linkname})
                    else: require(item.isdir(), 'Unsupported archive member')
            receipt['artifacts'] = {}
            for target, product, suffix, members, member, signing in [
                ('ios-xcarchive', packed, '.xcarchive.tar.gz', archive_members,
                 'Backplane.xcarchive/Products/Applications/Backplane.app/bridge.js', archived_signing),
                ('ios-ipa', ipas[0], '.ipa', ipa_members, 'Payload/' + apps[0].name + '/bridge.js', exported_signing)]:
                destination = output / ('backplane-' + c['release'] + '-ios' + suffix); shutil.copyfile(product, destination)
                sidecar = output / (destination.name + '.receipt.json')
                sidecar.write_text(json.dumps(wrapper(c, destination, target, members, member, signing, sha(bridge)), indent=2) + '\n')
                receipt['artifacts'][target] = {'path': destination.name, 'sha256': sha(destination), 'bytes': destination.stat().st_size,
                    'target_receipt': sidecar.name, 'target_receipt_sha256': sha(sidecar)}
            receipt['status'] = 'ARTIFACTS_BUILT_PENDING_TARGET_ACCEPTANCE'
    except InputError as error:
        receipt['failure'] = str(error)
        raise
    finally:
        if log_path.exists(): receipt['log_sha256'] = sha(log_path)
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'status': receipt['status'], 'receipt': str(output / 'receipt.json')}))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inputs', type=Path, required=True); p.add_argument('--source', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True); a = p.parse_args()
    try: build(a.inputs.resolve(), a.source.resolve(), a.output.resolve())
    except InputError as error:
        raise SystemExit(str(error) + '; no publication was performed.') from None
    except subprocess.TimeoutExpired:
        raise SystemExit('iOS artifact command timed out; no publication. Inspect producer.log.') from None
