# Service release producer

`scripts/service-release.py` supplies the genuine service component consumed by
the desktop producer and the matching emitted web consumed by the web producer.
It does not install, sign, invoke CI, run a server, change a live home, or publish.
The only payload execution is the newly compiled service's `--version` check.

```sh
python3 scripts/service-release.py describe
python3 scripts/service-release.py emit --request /absolute/emit.json --out /absolute/new-packet
python3 scripts/service-release.py native --request /absolute/native.json --out /absolute/new-build
python3 scripts/service-release.py build --request /absolute/request.json --out /absolute/new-build
python3 scripts/service-release.py component --request /absolute/component.json --out /absolute/new-component
uv run --offline --no-project python test/tools/service_release_test.py
```

Run `build` under the coordinator's admitted build slot on the actual target:
`linux-x64`, `linux-arm64`, or `darwin-arm64`. A different host fails before
compilation. Linux ARM64 therefore requires a real ARM64 executor; a Linux x64
receipt is never promoted to ARM64. The existing `scripts/build-app.sh` compiles
**src/server/main.bend** under the standard native lock, without a native GUI or
duplicate helper build. The wrapper retains that lock through private compile
header cleanup. Ordinary UI close and resident-service lifecycle are independent.

The checkout must be clean at the final committed release identity. Inputs and
outputs should live outside the checkout or in an ignored build directory.
The wrapper checks commit/tree and cleanliness before and after emission. Both
tool executables are pinned by hash, size and exact version output (`bend version`
and `clang --version`), and
rehash after use. Clang 19+ and GNU date are required by the existing native
builder; on Darwin use the provisioned LLVM and coreutils `gnubin` PATH.
Source check receipts must already refer to this same commit
and tree; this producer does not manufacture a whole-proof pass.

A separately pinned execution helper may use `--source-root ABS_FROZEN_CHECKOUT`
to operate on an unchanged product freeze. The same clean commit/tree and full
source-byte checks still apply. This permits an execution-tool correction without
changing or falsely relabelling product source. EMISSION/BUILD explicitly record
the actual helper hash and copy its exact bytes as `EXECUTION-HELPER.py`; component
assembly retains that provenance. The release coordinator must bind the helper
artifact independently from the product commit. This is not a Bend shim or an
unbound prebuilt-C override.

For small native runners, use the **emit → native** path. Run only `emit` on
the admitted large-memory Boat executor. It accepts the build request below,
but needs no protected configuration and does not require its target host to
match the eventual native target. It removes all inherited Google/telemetry
inputs from the child environment and sets both bakes to 0. It runs the real
server entry checks and `scripts/build-app.sh` with `BACKPLANE_EMIT_ONLY=1`,
then emits/postprocesses the matching web once. It never invokes a C compiler
or executes a native payload. The existing builder still queries the pinned
Clang version; the emitter request therefore includes both tool identities.
Its standard native lock protects the shared C work directory.

The portable output is `all.c`, source and web manifests, source qualification,
web notices, web emission evidence, logs, `web/`, and `EMISSION.json`.
EMISSION is schema1 `backplane-service-c-emission`,
`status:VERIFIED_PORTABLE_C_EMISSION_ONLY`, `target:portable-c`, with supported
`nativeTargets`, frozen `sourceCommit`/`sourceTree`, version/stamp/channel,
`entrypoint:src/server/main.bend`, pinned Bend `compiler`, exact relative
`cArtifact`, complete packet `members`, source/web manifest hashes and source
qualification reference. `emissionInputs` records both bakes false and no
protected input forwarding. It never claims a configured native BUILD pass.
Keep this packet and its independently pinned receipt intact during transfer.

The protected native host uses this request instead:

```json
{
  "schema": 1,
  "kind": "backplane-service-native-inputs",
  "target": "darwin-arm64",
  "release": {
    "version": "0.12.0", "tag": "v0.12.0", "channel": "release",
    "commit": "FULL_FINAL_COMMIT", "tree": "FULL_FINAL_TREE"
  },
  "toolchain": {
    "clang": {"path": "/absolute/clang", "sha256": "ACTUAL_SHA256", "bytes": 0, "version": "EXACT_VERSION_OUTPUT"}
  },
  "emissionReceipt": {"path": "/absolute/packet/EMISSION.json", "sha256": "ACTUAL_SHA256", "bytes": 0},
  "emissionDirectory": "/absolute/packet"
}
```

`native` requires the actual target host, clean identical committed checkout,
protected bake inputs below, and pinned native Clang. It does not need Bend
installed and never invokes it. Before compilation it verifies the supplied
receipt hash, every packet member, C hash, source commit/tree and **every source
file's actual bytes**, matching WEB1/gzip and qualified log references.
Only then, under the standard native lock, does it copy the approved C into
the builder work directory and enable its internal `BACKPLANE_PREBUILT=1`.
It requires the builder's explicit prebuilt branch receipt and unchanged C
hash afterward. Ambient PREBUILT overrides never select or authorize input.
The version stamper's existing same-version behavior is a no-op, verified by
that unchanged C hash. The exact source-bound C can feed each supported target.

This stage forces `BACKPLANE_JOBS=1`, including on a protected GitHub runner,
so the large Bend emit is never attempted there. The target performs the
real bake-header generation and C compilation with its protected Google and
telemetry inputs, followed by the actual binary architecture/version check.
It copies the already-qualified web bytes and source evidence without another
emission. Raw configured BUILD records `portableEmission` receipt/C hashes,
emitter compiler and one native compiler lane, while retaining the unchanged
public compile witness consumed by the desktop producer. Only this successful
native stage can claim a configured native build. An unresolved target executor,
protected key provisioning or measured dependency remains a failed prerequisite.

A build request has this shape (all artifact references use actual values):

```json
{
  "schema": 1,
  "kind": "backplane-service-build-inputs",
  "target": "linux-x64",
  "release": {
    "version": "0.12.0", "tag": "v0.12.0", "channel": "release",
    "commit": "FULL_FINAL_COMMIT", "tree": "FULL_FINAL_TREE"
  },
  "toolchain": {
    "bend": {"path": "/absolute/bend", "sha256": "ACTUAL_SHA256", "bytes": 0, "version": "EXACT_VERSION_OUTPUT"},
    "clang": {"path": "/absolute/clang", "sha256": "ACTUAL_SHA256", "bytes": 0, "version": "EXACT_VERSION_OUTPUT"}
  },
  "sourceQualification": {"path": "/absolute/qualification.json", "sha256": "ACTUAL_SHA256", "bytes": 0},
  "webNotices": {"path": "/absolute/web-notices.json", "sha256": "ACTUAL_SHA256", "bytes": 0}
}
```

References resolve relative to the containing request, or may be absolute. The
source qualification uses the desktop web producer's schema:
`schema:1`, `kind:backplane-web-source-qualification`, `status:PASS`, `commit`,
`tree`, `version:0.12.0`, and nonempty `checks` containing references to actual
final source/entry/proof logs. Their bytes are checked, copied and rebound.
`webNotices` is a source-bound `schema:1`, `kind:backplane-web-source-notices`,
`sourceCommit`, `sourceTree`, `licenses` mapping web destination names to frozen
checkout source files, and `packages`. Each package has `name`, `version`,
`sourceDisposition`, and nonempty `licenses:[{path,sha256}]` relative to web.
Supply all redistribution notices for the actual emitted assets. No license is
inferred from a binary or silently downloaded.

Protected configuration is passed only through the build environment:

* `BACKPLANE_GOOGLE_CLIENT_ID` and `BACKPLANE_GOOGLE_CLIENT_SECRET`;
* `BACKPLANE_TELEMETRY_URL=https://backplane.works/api/v1/events`;
* `BACKPLANE_TELEMETRY_KID` matching `rel-[a-z0-9-]{1,28}`;
* `BACKPLANE_TELEMETRY_KEY`, 64 lowercase hex characters.

Missing configuration fails before compilation in `build` and `native`; it is
deliberately absent from `emit`. The configured stages set both bakes to
1, version and stamp to `0.12.0`, telemetry channel to `release`, and Clang flags
to `-O3 -gline-tables-only`. Ambient prebuilt overrides and emission/object cache
reuse are disabled; only `native` enables the builder's internal prebuilt path
after checking the pinned emission packet. Do not echo protected values or retain generated configuration
headers. Public BUILD contains only the agreed boolean configuration witness
and public endpoint; it contains no credential values or credential hashes.
The existing build log's Google client prefix is removed before log persistence.

Build outputs are `backplane-serve`, original `BUILD.json`, `SOURCE.json`,
`WEB.json`, `WEB-EMISSION.json`, `web/`, source qualification and sanitized logs.
The service header is checked as ELF64 x64/ARM64 or arm64 Mach-O, and its actual
version must be `backplane 0.12.0`. Web emission uses the production Bend root,
unmarshal/native postprocessors and service worker; every HTML/JS/CSS file gets
a deterministic gzip sibling checked against the complete decoded bytes. WEB
schema1 declares every member, including all notice files. No fonts are added.

`BUILD.status` is `VERIFIED_GENUINE_SERVICE_ONLY_CONFIGURED_BUILD`. The original
BUILD records `target`, `entry:src/server/main.bend`, `source_commit`,
`source_tree`, `version`, `versionStamp`, `telemetryChannel`, `binary_sha256`,
source/web manifest hashes, tool identities and sanitized log references. Its
`compileInputs` is exactly:

```json
{
  "version": "0.12.0", "versionStamp": "0.12.0", "telemetryChannel": "release",
  "google": {"requested": true, "requiredInputsPresent": true},
  "telemetry": {"requested": true, "requiredInputsPresent": true,
    "endpoint": "https://backplane.works/api/v1/events"}
}
```

This witness is written only after successful configured compilation. Existing
development BUILD receipts cannot acquire it through component assembly.

Offline component assembly takes `schema:1`,
`kind:backplane-service-component-inputs`, the same `target` and `release`,
`buildDirectory`, a reference `buildReceipt` to its original BUILD,
`runtimeDirectory`, and a reference `runtimeQualification`. Runtime approval is
`schema:1`, `kind:backplane-service-runtime-qualification`, `status:PASS`,
`target`, `sourceCommit`, `sourceTree`, `binarySha256`,
`runtimeManifestSha256`, `closureSha256`, and exact `members` for runtimeDirectory.
It comes from the target closure owner after actual dependency measurement.
It is not a substitute for installed product runtime acceptance.

Runtime input contains `RUNTIME.json`, `CLOSURE.json`, libraries and notices,
without colliding with service/web files. RUNTIME has `target`, nonempty
`inventory:[{path,package,version,architecture,sha256,bytes}]` and `packages` with
the license shape above. CLOSURE has `target`, `measured:true`, `status:PASS`,
`unresolvedMandatory:[]`, and `edges:[{from,kind,name,...}]`. Edge `kind` is
normal, delay or dynamic. Every edge is either `system:true` with
`classification:approved-system`, or resolves to an exact supplied file via
`resolved`. The measured edges refer to the final combined payload, including
`backplane-serve`. The runtime owner must bind normal and dynamically loaded
dependencies; this wrapper never invents an empty measurement or resolves a
library by searching the build machine.

Component output `payload/` preserves original BUILD bytes, service/web/source,
runtime files and approval, plus the copied source logs and web emission evidence.
Internal provenance references are relative to their containing JSON so the
component and standalone web evidence survive transfer to another target host.
Adjacent `SERVICE.json` is schema1
`backplane-bend-service`, `status:VERIFIED`, with target, commit/tree,
`version:0.12.0`, `channel:release`, `genuineService:true`, server entry,
`roles:{service:backplane-serve,web:web}`, original BUILD reference, complete
member hashes/sizes/modes, runtime/closure hashes and package notices. The
desktop producer consumes `{receipt:REFERENCE,payload:{directory:PAYLOAD}}`.
The standalone web producer consumes build `web/` with `WEB.json` and
`WEB-EMISSION.json`, pinned in the final release freeze.

Both operations leave installed-runtime acceptance pending and `published:false`.
The desktop/web archive producers and root's actual target checks, configured
ingestion witness, release collector, PR/merge and GitHub publication follow.
