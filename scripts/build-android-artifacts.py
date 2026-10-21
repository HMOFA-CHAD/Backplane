#!/usr/bin/env python3
"""Produce local, verified Release APK+AAB from pinned source and bridge inputs.

Never emits Bend/JS, installs an app or publishes. Run heavy work through
work_run with the native-build lock. Signing values are environment-only.
"""
from pathlib import Path, PurePosixPath
import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile


class InputError(ValueError):
    pass


def require(ok, message):
    if not ok:
        raise InputError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def pinned_file(spec, base):
    require(isinstance(spec, dict), 'Missing pinned input')
    path = Path(spec.get('path', ''))
    if not path.is_absolute():
        path = base / path
    require(path.is_file() and sha(path) == spec.get('sha256'), 'Pinned input hash mismatch')
    return path.resolve()


def validate(config, source, base):
    require(config.get('schema') == 1, 'Unsupported artifact input schema')
    release = config.get('release', '')
    require(re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', release), 'Explicit stable release required')
    require(config.get('channel') == 'release' and
            all(re.fullmatch(r'[0-9a-f]{40}', config.get(key, '')) for key in ['sourceCommit', 'sourceTree']),
            'Explicit release channel and source commit/tree required')
    code, floor = config.get('version_code'), config.get('published_version_code_floor')
    require(type(code) is int and type(floor) is int and 0 <= floor < code <= 2100000000,
            'Explicit version code must exceed the published floor')
    require(re.fullmatch(r'[0-9a-f]{64}', config.get('expected_signer_sha256', '')),
            'Explicit approved signer SHA256 required')
    files = config.get('source_files')
    require(isinstance(files, dict) and files, 'Frozen Android source closure required')
    required = {'mobile/android/gradlew', 'mobile/android/build.gradle.kts',
                'mobile/android/settings.gradle.kts', 'mobile/android/app/build.gradle.kts',
                'scripts/build-android-artifacts.py'}
    require(required <= files.keys(), 'Incomplete source closure')
    for name, digest in files.items():
        p = PurePosixPath(name)
        require(not p.is_absolute() and '..' not in p.parts and str(p) == name and
                (name.startswith('mobile/android/') or name == 'scripts/build-android-artifacts.py'),
                'Source path outside Android producer boundary')
        require(not any(part in {'build', '.gradle', '.git'} for part in p.parts) and p.name != 'local.properties',
                'Generated or local file in frozen source closure')
        f = source / name
        require(f.is_file() and not f.is_symlink() and sha(f) == digest, 'Frozen source hash mismatch')
    require(sha(Path(__file__)) == files['scripts/build-android-artifacts.py'], 'Producer is not the pinned source')
    bridge = pinned_file(config.get('bridge'), base)
    qualification = pinned_file(config.get('bridge_qualification'), base)
    q = json.loads(qualification.read_text())
    def values(item):
        if isinstance(item, dict):
            for v in item.values(): yield from values(v)
        elif isinstance(item, list):
            for v in item: yield from values(v)
        elif isinstance(item, str): yield item
    require(sha(bridge) in set(values(q)), 'Qualification does not bind the bridge')
    prequalification = pinned_file(config.get('source_prequalification'), base)
    accepted = json.loads(prequalification.read_text())
    require(accepted.get('status') == 'ACCEPTED_FOR_ARTIFACT_BUILD' and
            accepted.get('scope') == 'source-bridge-native-path' and
            accepted.get('artifact_runtime_accepted') is False and accepted.get('release') == release and
            accepted.get('bridge_sha256') == sha(bridge) and accepted.get('source_files') == files and
            all(accepted.get(k) == config[k] for k in ['sourceCommit', 'sourceTree', 'channel']),
            'Source prequalification must bind this tuple without claiming artifact runtime acceptance')
    bundletool = pinned_file(config.get('bundletool'), base)
    return bridge, qualification, prequalification, bundletool


def check_manifest(xml, version, code):
    root = ET.fromstring(xml)
    ns = '{http://schemas.android.com/apk/res/android}'
    app = root.find('application')
    require(root.get('package') == 'dev.backplane.mobile', 'Wrong Android package')
    require(root.get(ns + 'versionName') == version and root.get(ns + 'versionCode') == str(code),
            'Native version metadata differs from requested release')
    require(app is not None and app.get(ns + 'debuggable', 'false').lower() == 'false',
            'Release artifact must be non-debuggable')


def certificate_hashes(text):
    # apksigner and keytool render the same public SHA256 with different spacing.
    return {re.sub(r'[^0-9a-f]', '', match.lower()) for match in
            re.findall(r'(?:SHA-?256(?: digest)?):\s*([0-9A-Fa-f:]{64,95})', text)}


def check_embedded(path, member, digest):
    with zipfile.ZipFile(path) as archive:
        require(archive.namelist().count(member) == 1 and
                hashlib.sha256(archive.read(member)).hexdigest() == digest, 'Embedded bridge mismatch')


def verify_source_git(config, source):
    def git(*args):
        p = subprocess.run(['git', '-C', str(source), *args], capture_output=True, text=True)
        require(p.returncode == 0, 'Release source must be committed and unchanged')
        return p.stdout.strip()
    require(git('rev-parse', 'HEAD') == config['sourceCommit'] and
            git('rev-parse', 'HEAD^{tree}') == config['sourceTree'], 'Release source commit/tree mismatch')
    names = list(config['source_files'])
    git('ls-files', '--error-unmatch', '--', *names)
    git('diff', '--quiet', 'HEAD', '--', *names)


def target_package(config, path, kind, bridge_sha):
    member = 'assets/bridge.js' if kind == 'apk' else 'base/assets/bridge.js'
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), 'Duplicate archive member')
        members = [{'path': name, 'sha256': hashlib.sha256(archive.read(name)).hexdigest(),
                    'bytes': archive.getinfo(name).file_size} for name in sorted(names)
                   if not archive.getinfo(name).is_dir()]
    return {'schema': 1, 'kind': 'backplane-target-package', 'target': 'android-' + kind,
            'qualification': 'BUILT_PENDING_TARGET_RUNTIME_ACCEPTANCE', 'artifactRuntimeAccepted': False,
            'sourceCommit': config['sourceCommit'], 'sourceTree': config['sourceTree'],
            'version': config['release'][1:], 'channel': config['channel'],
            'archive': {'name': path.name, 'sha256': sha(path), 'bytes': path.stat().st_size},
            'members': members, 'bridgeMember': member, 'bridgeSha256': bridge_sha,
            'actualNativeVersion': config['release'][1:], 'configuration': 'Release',
            'buildNumber': config['version_code'], 'package': 'dev.backplane.mobile',
            'signing': {'certificateSha256': config['expected_signer_sha256'],
                        'signatureVerified': True, 'debuggable': False}}


def build(config_path, source, output):
    config = json.loads(config_path.read_text())
    bridge, qualification, prequalification, bundletool = validate(config, source, config_path.parent)
    require(not output.exists(), 'Output exists; inspect its receipt before another attempt')
    sdk = Path(os.environ.get('ANDROID_HOME', '')).resolve()
    java = Path(os.environ.get('JAVA_HOME', '')).resolve()
    require(bool(os.environ.get('ANDROID_HOME')) and sdk.is_dir(), 'Explicit Android SDK required')
    require(bool(os.environ.get('JAVA_HOME')) and (java / 'bin/java').is_file(), 'Explicit Java toolchain required')
    build_tools = config.get('build_tools', '')
    require(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', build_tools), 'Explicit SDK build-tools version required')
    apksigner = sdk / 'build-tools' / build_tools / 'apksigner'
    analyzer = sdk / 'cmdline-tools/latest/bin/apkanalyzer'
    require(apksigner.is_file() and analyzer.is_file(), 'Required APK verification tools unavailable')
    for key in ['KEYSTORE_PASSWORD', 'KEY_ALIAS', 'KEY_PASSWORD']:
        require(bool(os.environ.get(key)), 'Configured release signing inputs required')
    store_path = os.environ.get('BACKPLANE_ANDROID_KEYSTORE_PATH')
    encoded = os.environ.get('BACKPLANE_ANDROID_KEYSTORE_BASE64')
    require(bool(store_path) != bool(encoded), 'Supply exactly one configured keystore source')
    if store_path:
        require(Path(store_path).is_file(), 'Configured keystore unavailable')
    verify_source_git(config, source)
    output.mkdir(parents=True)
    log_path = output / 'producer.log'
    receipt = {'status': 'FAILED_NOT_PUBLISHED', 'release': config['release'],
               'sourceCommit': config['sourceCommit'], 'sourceTree': config['sourceTree'],
               'version': config['release'][1:], 'channel': config['channel'],
               'inputs_sha256': sha(config_path), 'producer_sha256': sha(Path(__file__)),
               'bridge_sha256': sha(bridge), 'qualification_sha256': sha(qualification),
               'source_prequalification_sha256': sha(prequalification), 'source_files': config['source_files'],
               'artifact_runtime_accepted': False,
               'next_gate': 'Root target acceptance must bind actual built artifact hashes and runtime evidence before all-target publication.'}
    try:
        with tempfile.TemporaryDirectory(prefix='bp-android-artifacts-') as directory, log_path.open('w') as log:
            stage = Path(directory)
            for name in config['source_files']:
                target = stage / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source / name, target)
            target = stage / 'mobile/build/assets/bridge.js'
            target.parent.mkdir(parents=True)
            shutil.copyfile(bridge, target)
            env = os.environ.copy()
            if encoded:
                try:
                    key_bytes = base64.b64decode(encoded, validate=True)
                except (ValueError, base64.binascii.Error):
                    raise InputError('Configured keystore encoding is invalid') from None
                private = stage / 'configured-signing-keystore'
                private.touch(mode=0o600)
                private.write_bytes(key_bytes)
                env['BACKPLANE_ANDROID_KEYSTORE_PATH'] = str(private)
            else:
                env['BACKPLANE_ANDROID_KEYSTORE_PATH'] = str(Path(store_path).resolve())
            env.pop('BACKPLANE_ANDROID_KEYSTORE_BASE64', None)
            env['BACKPLANE_ANDROID_VERSION_NAME'] = config['release'][1:]
            env['BACKPLANE_ANDROID_VERSION_CODE'] = str(config['version_code'])
            def run(command, capture=False, cwd=None):
                p = subprocess.run(command, cwd=cwd, env=env, text=True,
                                   stdout=subprocess.PIPE if capture else log,
                                   stderr=log, timeout=1200)
                require(p.returncode == 0, 'Artifact build or verification command failed; inspect producer.log')
                return p.stdout
            run(['./gradlew', '--no-daemon', '--max-workers=2',
                 '-Dorg.gradle.jvmargs=-Xmx1g -Dfile.encoding=UTF-8',
                 '-Pkotlin.compiler.execution.strategy=in-process', ':app:assembleRelease', ':app:bundleRelease'],
                cwd=stage / 'mobile/android')
            apk = stage / 'mobile/android/app/build/outputs/apk/release/app-release.apk'
            aab = stage / 'mobile/android/app/build/outputs/bundle/release/app-release.aab'
            check_manifest(run([str(analyzer), 'manifest', 'print', str(apk)], True), config['release'][1:], config['version_code'])
            check_manifest(run([str(java / 'bin/java'), '-jar', str(bundletool), 'dump', 'manifest',
                                '--bundle=' + str(aab), '--module=base'], True), config['release'][1:], config['version_code'])
            apk_cert = certificate_hashes(run([str(apksigner), 'verify', '--verbose', '--print-certs', str(apk)], True))
            # jarsigner verifies integrity; keytool reports only the embedded public certificate.
            verify = run([str(java / 'bin/jarsigner'), '-J-Duser.language=en', '-verify', str(aab)], True)
            require('jar verified.' in verify, 'AAB signature verification did not succeed')
            aab_cert = certificate_hashes(run([str(java / 'bin/keytool'), '-J-Duser.language=en', '-printcert', '-jarfile', str(aab)], True))
            expected = {config['expected_signer_sha256']}
            receipt['observed_signer_sha256'] = {'apk': sorted(apk_cert), 'aab': sorted(aab_cert)}
            require(apk_cert == expected and aab_cert == expected, 'Public signing certificate differs from approved release identity')
            check_embedded(apk, 'assets/bridge.js', sha(bridge))
            check_embedded(aab, 'base/assets/bridge.js', sha(bridge))
            # Recheck frozen source and build prequalification before exposing artifacts.
            validate(config, source, config_path.parent)
            verify_source_git(config, source)
            receipt['artifacts'] = {}
            for kind, path in [('apk', apk), ('aab', aab)]:
                destination = output / (f'backplane-{config["release"]}-android.' + kind)
                shutil.copyfile(path, destination)
                wrapper = output / (destination.name + '.receipt.json')
                wrapper.write_text(json.dumps(target_package(config, destination, kind, sha(bridge)), indent=2) + '\n')
                receipt['artifacts'][kind] = {'path': destination.name, 'sha256': sha(destination),
                    'bytes': destination.stat().st_size, 'target_receipt': wrapper.name, 'target_receipt_sha256': sha(wrapper)}
            receipt.update(status='ARTIFACTS_BUILT_PENDING_TARGET_ACCEPTANCE', package='dev.backplane.mobile',
                           version_name=config['release'][1:], version_code=config['version_code'],
                           signer_sha256=config['expected_signer_sha256'], debuggable=False,
                           tools={'build_tools': build_tools, 'apksigner_sha256': sha(apksigner),
                                  'apkanalyzer_sha256': sha(analyzer), 'bundletool_sha256': sha(bundletool)})
    finally:
        if log_path.exists(): receipt['log_sha256'] = sha(log_path)
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'status': receipt['status'], 'receipt': str(output / 'receipt.json')}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        build(args.inputs.resolve(), args.source.resolve(), args.output.resolve())
    except (InputError, subprocess.TimeoutExpired):
        raise SystemExit('Artifact producer failed; no publication was performed. Inspect validated inputs or producer.log.') from None
