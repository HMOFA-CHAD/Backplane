# Service release producer

`scripts/service-release.py` supplies the genuine service component consumed by
the desktop producer and the matching emitted web consumed by the web producer.
It does not install, sign, invoke CI, run a server, change a live home, or publish.
The only payload execution is the newly compiled service's `--version` check.

```sh
python3 scripts/service-release.py describe
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
tool executables are pinned by hash, size and exact `--version` output, and
rehash after use. Clang 19+ and GNU date are required by the existing native
builder; on Darwin use the provisioned LLVM and coreutils `gnubin` PATH.
Source check receipts must already refer to this same commit
and tree; this producer does not manufacture a whole-proof pass.

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

Missing configuration fails before compilation. The wrapper sets both bakes to
1, version and stamp to `0.12.0`, telemetry channel to `release`, and Clang flags
to `-O3 -gline-tables-only`. Prebuilt overrides and emission/object cache reuse
are disabled. Do not echo protected values or retain generated configuration
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
