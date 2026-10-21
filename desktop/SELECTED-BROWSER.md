# Selected browser composition (additive proposal)

This optional path composes a root-selected browser with already configured
native components. It never changes the native release identity or rewrites
original `BUILD`, `SOURCE`, `COMPILE`, `WEB`, service or runtime receipts.
It does not fetch, emit, compile, execute, sign, allocate or publish anything.

Root owns the actual browser source, generated manifest, receipts, and canonical
policy. The selected browser source is separate from original native source.
Root has now supplied canonical staging policy
`fee94f08b3ce7d909a1265d9f33820ea816887703e940ca0d7a57374f9509314`;
`selected-browser.cjs` and composer pin that exact SHA. No policy bytes were
changed by this implementation. No environment, CLI or input can override the
trust constant. The direct producer verifies the actual policy file, its native
service archive/receipt pin, source/configuration and selected-browser freeze
bindings; a caller-created freeze and formatted SHA cannot authorize replacement.
Original proposal01/02 records remain immutable and superseded.

## Callable input

Existing commands accept an optional named argument:

```
node desktop/compose-target-freeze.cjs --policy ABS_POLICY --components ABS_COMPONENT_INPUTS --service ABS_SERVICE_JSON_OR_WINDOWS_ZIP --out NEW_ABS_FREEZE --selected-browser ABS_BROWSER_INPUT
node desktop/prepare-native-stage.cjs stage --components ABS_COMPONENT_INPUTS --service ABS_SERVICE_JSON_OR_WINDOWS_ZIP --freeze ABS_FREEZE --out NEW_ABS_STAGE --selected-browser ABS_BROWSER_INPUT
```

The ordinary `produce-release.cjs stage --request ... --output ...` interface
also accepts `request.selectedBrowser`. It uses the existing component adapter
plus `rootDisposition: {path, sha256, bytes}` referencing the actual pinned root
staging policy: `{receipt: {path, sha256, bytes}, payload: {directory}, rootDisposition}`.
Composer can fill `rootDisposition` from its `--policy`; the native stage adapter
and direct request must supply it. The payload may alternatively be a verified
`payload.archive` reference with optional safe `root`. Relative references resolve
against the input JSON, so a Windows guest does not need a Linux absolute path.
Without `selectedBrowser`, existing request/stage/archive behavior is unchanged.
An input and freeze selection must either both exist or both be absent.

The browser payload contains exactly `WEB.json` and `web/**`. The receipt is:

```
schema: 1
kind: backplane-selected-browser
status: VERIFIED
version: 0.12.0
channel: release
sourceCommit: ROOT_ACTUAL_BROWSER_COMMIT
sourceTree: ROOT_ACTUAL_BROWSER_TREE
entrypoint: src/web/index.html
webManifest: WEB.json
webRoot: web
webManifestSha256: ACTUAL_WEB_MANIFEST_SHA
members: EXACT_PAYLOAD_FILE_INVENTORY
packages: NONEMPTY_PUBLIC_NOTICES_WITH_HASHED_WEB_RELATIVE_LICENSE_PATHS
```

The existing `matching-generated-web` schema in `WEB.json` describes the actual
selected source, files, sizes and hashes. Membership/modes, graph references,
gzip equality (including nested assets), notices, safe paths, symlink refusal,
font refusal and native-format refusal are checked. Windows membership uses the
existing qualified native mode projection; original receipts are not rewritten.

Root's target disposition adds `targets[TARGET].selectedBrowser`:

```
mode: generated-web-subtree-only
receipt: {sha256: ACTUAL_BROWSER_RECEIPT_SHA, bytes: ACTUAL_SIZE}
sourceCommit: ROOT_ACTUAL_BROWSER_COMMIT
sourceTree: ROOT_ACTUAL_BROWSER_TREE
webManifestSha256: ACTUAL_SELECTED_WEB_MANIFEST_SHA
resourceWebManifestSha256: ORIGINAL_SERVICE_WEB_MANIFEST_SHA
baselineDesktopReceiptSha256: ORIGINAL_ACCEPTED_DESKTOP_SHA  # Mac/Windows composite only
```

Composer copies this selection into the freeze, adds the selected receipt pin to
the target components, and separately records `resourceWeb[TARGET]` with the
original native source/manifest. Existing component, Windows shell override,
compile configuration, signing, resident lifecycle and tooling pins remain.
The root disposition SHA/size is required in the freeze.

## Validation order and stage

1. Validate the original complete component under all existing native service,
   configured bake, architecture, closure, member, notice and matching-web guards.
2. Validate the optional selected browser against root's exact pins.
3. Copy and verify the original components unchanged.
4. Replace only staged `backplane-service/web/`; verify the selected web again
   and compare every non-web service member byte/mode for equality.

Original `backplane-service/WEB.json` remains the original matching-web record.
`PROVENANCE/selected-browser.json` and `selected-browser-web.json` carry the new
receipt and manifest. The actual pinned root policy is preserved byte for byte in
`PROVENANCE/root-staging-disposition.json`, exposed by
`components.rootStagingDisposition`; archive and collector can verify the policy
body independently. The policy pins the original service receipt (Unix) or
service archive (Windows), not only its source identity. The final archive also carries exact current `STAGE.json` bytes in
`PROVENANCE/selected-browser-stage.json`; `DESKTOP.stageReceiptSha256` and
`DESKTOP.stageReceipt` bind them for independent collector verification.
`STAGE`, freeze and `DESKTOP` record `resourceWeb` and
`selectedBrowser` separately. Their `webManifestSha256` denotes the installed
selected browser when present. Native release/source fields keep their original
values. `NOTICES.json` remains the native baseline inventory; additional browser
notices are validated and retained in the selected-browser receipt. If an old
notice points inside web, that old hashed license must still exist unchanged.

## New target evidence

Every selected browser requires a new hash-bound `selectedBrowserRuntime` receipt:

```
schema: 1
kind: desktop-selected-browser-runtime
scope: same-target-selected-browser
status: PASS
target: ACTUAL_NATIVE_TARGET
version: 0.12.0
stageReceiptSha256: CURRENT_STAGE_SHA
payloadManifestSha256: CURRENT_PAYLOAD_SHA
freezeReceiptSha256: CURRENT_FREEZE_SHA
selectedBrowserReceiptSha256: SELECTED_BROWSER_RECEIPT_SHA
webManifestSha256: SELECTED_WEB_SHA
sourceCommit: SELECTED_BROWSER_COMMIT
sourceTree: SELECTED_BROWSER_TREE
checks: {authenticatedOrigin: true, newAssetsLoaded: true, routeRetention: true, draftRetention: true, inlineBoundedMore: true, explicitRetry: true}
rendererSandbox: {processType: renderer, osEnforced: true, flags: ACTUAL_FLAGS}
evidence: [{path: PROVENANCE/selected-browser-evidence/report.json, sha256: ACTUAL_SHA, bytes: ACTUAL_NONEMPTY_SIZE}]
```

Raw evidence references must use exactly the package-relative namespace shown
above, one ASCII filename of 1..128 characters matching
`[A-Za-z0-9][A-Za-z0-9._-]*`, with no `..`. Paths must be case-insensitively
unique. Require 1..16 nonempty regular files, at most 8 MiB each and 32 MiB total;
symlinks, directories, missing files, absolute paths and digest/size mismatch
reject. The fixture writes these relative files alongside its runtime envelope
before freezing it. Archive copies their bytes to those same names using
exclusive creation and rechecks every copy, preserving the original runtime
JSON bytes and references. These files stay provenance metadata, outside the
native/web payload digest. Collector can verify them directly from the archive.

These are required facts to be measured on the matching native target, not
generated PASS values. Sandbox bypass flags reject. Root owns actual execution
and final receipt binding. Old Linux or browser viewport results are not a
substitute for another target.

Linux uses the existing four current-payload full-essential proof references
plus this new browser runtime reference, after the specific privilege approval.

Mac/Windows may instead use this explicit acceptance envelope:

```
schema: 1
kind: backplane-desktop-browser-composite-acceptance
scope: retained-native-baseline+selected-browser
target: SAME_NATIVE_TARGET
stageReceiptSha256: CURRENT_STAGE_SHA
payloadManifestSha256: CURRENT_PAYLOAD_SHA
baseline:
  desktop: ORIGINAL_ACCEPTED_DESKTOP_REFERENCE
  freeze: ORIGINAL_FREEZE_REFERENCE
  proofs: {signing: ORIGINAL_REF, sandbox: ORIGINAL_REF, lifecycle: ORIGINAL_REF, runtimeAcceptance: ORIGINAL_REF}
selectedBrowserRuntime: NEW_SAME_TARGET_BROWSER_RUNTIME_REFERENCE
```

The baseline `DESKTOP` SHA must be root-pinned. Every raw proof must match its
original `DESKTOP` hash/size, old payload and old freeze. Original native receipt
identities and every non-web payload member/mode must equal the new stage.
Old proof semantics still pass the existing signing/sandbox/lifecycle/runtime
guards. They are copied byte for byte as `baseline-*.json`, along with original
`DESKTOP` and freeze. The new `DESKTOP.acceptance.kind` is
`desktop-browser-composite`, with explicit scope and lineage; it carries baseline
proof references and the new browser runtime separately. It never promotes old
proofs to full eight-check acceptance of the new payload.

Collector support for this explicit composite representation belongs to the
release owner. This patch does not mutate collectors, candidates or publication.

## Focused offline controls

`node --test desktop/test/selected-browser.test.cjs` runs new synthetic controls
only. It reuses existing fixture definitions without executing the old suite.
Only the fixed root-policy constant is substituted in isolated in-memory module
copies for synthetic fixtures; the shipped producer has no trust override.
It checks four-target composition, original-first rejection, non-web preservation,
pending/wrong pins, unsafe members/links/fonts/native data/gzip/notices, portable
references, Windows modes, exact baseline lineage, and new runtime requirements.
Synthetic executable headers are data and are never executed; no product archive,
emission, native/runtime job or successful UI acceptance is replayed.
