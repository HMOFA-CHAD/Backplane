# Configured producer bootstrap

This workflow starts the first real protected producer run. It does not require a
previous successful producer run, emit Bend on a small runner, install anything,
create a tag or publish a release. Unix native jobs use the owner's split03
`service-release.py native`; Windows and Android use their existing producers.
iOS continues on the coordinated local Mac with the accepted signing identity.

Root first freezes the committed source containing split03 and this workflow.
Use that same full SHA for the input envelope, workflow dispatch and checkout.
Do not rebind development binaries or failed/unexecuted source checks. The
source qualification included in a portable emission is the owner's actual
source/entry/proof evidence, with retained identical closures stated honestly.

The large-memory Boat executor runs the real secret-free `service-release.py
emit` once. Its complete, verified output goes under `emission/` in an otherwise
new input directory. The unchanged packet can feed all three actual Unix native
hosts: Linux x64, Linux ARM64 and Darwin ARM64. The native producer verifies every
source/C/web byte and qualification before internally selecting PREBUILT; only
native compilation receives private Google and telemetry inputs.

Prepare each public input directory as follows:

| Operation | Required input directory contents |
| --- | --- |
| `unix-native` | `emission/` including actual `EMISSION.json`, `all.c`, source/qualification/logs, notices and matching web |
| `windows-native` | Actual `windows-service-request.json`, the exact Windows emitted input archive and measured runtime payload it references; all request paths relative to this directory |
| `android` | Actual `android-release-inputs.json`, qualified bridge, native source prequalification, pinned bundletool and other referenced public files, all with relative paths |

No key, keystore, profile, configuration header or secret is transferred in this
packet. The actual Android credentials remain GitHub secrets. The native owner
chooses the public signer identity and monotonically increasing version code in
the actual request. The four configured secrets map to the existing producer's
`BACKPLANE_ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` and
`KEY_PASSWORD` environment names.

From the clean final checkout (paths below are examples, not executed claims):

```sh
python3 scripts/release-bootstrap.py pack \
  --source "$FROZEN_COMMIT" --operation unix-native \
  --directory /absolute/public-input-directory --out /absolute/public-inputs.tar.gz
```

This writes a complete source/tree/version/member envelope, then returns the
actual archive SHA256. Transfer the immutable public packet through the existing
Boat temporary HTTPS hosting route. Keep the independently selected digest;
credentials never appear in the URL or the packet. Retain the packet until the
run ends. Root-selected URL/digest are data, never shell or executable code.

```sh
gh workflow run release-bootstrap.yml --repo i2cjak/Backplane \
  --ref main \
  -f ref="$FROZEN_COMMIT" -f operation=unix-native \
  -f packet_url="$PUBLIC_PACKET_URL" -f packet_sha256="$PACKET_SHA256"
```

`--ref main` selects the merged workflow; its actual `github.sha` must equal
the frozen full SHA, so a moved branch fails closed. GitHub dispatch selects a
branch or tag; no release tag is created to launch validation.

Use `operation=windows-native` and `operation=android` for their respective
packets. Independent jobs can run concurrently; a concurrency group prevents
cancelling an in-flight operation. A dispatch failure or suspended Actions is an
execution blocker, not a reason to fabricate a successful producer run. Inspect
actual run/job status and existing outputs before a retry.

The URL fetch happens before any protected compile/signing environment is
introduced. It requires HTTPS and an independently supplied SHA, rejects unsafe
archive entries and verifies the full source envelope. The only commands run
are producers in the checked-out source. Generated native requests bind the
actual installed compiler path/hash/version. Unix native uses one C lane, and
never requires Bend on that runner. Mac uses LLVM21/coreutils in the ephemeral user environment; Linux selects an already-installed clang19+ without administrator commands; the compile header generators clean their own private files.

Artifacts contain actual configured raw build receipts/binaries/web, or signed
Release APK/AAB and native receipts. Upload on failure preserves scoped producer
evidence without claiming a successful package. Artifact output is intermediate:
the desktop/runtime owner still measures closure and packages with Electron, and
actual target smoke/configuration/sandbox evidence precedes aggregate acceptance.
No commercial desktop certificate or managed-stop ABI is introduced: the root's
resident-service and unsigned-portable policies remain in force. Only root
publishes after all seven actual target rows are qualified.
