# CI validation and native compiler

CI runs the installed, checksum-pinned Bend 2.0.36 for type checking, proofs
and JavaScript tests. Tests use a bounded 1 GiB OS stack and a 512 MiB JSC
stack, matching `scripts/check.sh`. Both test shards and Linux builds pin
Bun 1.4.3. Each of the four test shards uses two workers, and native C
compilation uses two workers, leaving headroom for the larger render tests
and C units on the 16 GiB runners.

`scripts/test.sh` runs each standalone IO test and its matching
`test/tools/NAME.mjs` driver when present. JavaScript fixtures are emitted
and their drivers execute assertions; successful emission alone cannot pass.
Files with an IO `main` and a driver exercise both. The intentionally failing
`cache_identity_before_test.bend` is reserved for
`test/tools/mobile_cache_identity_gate.py`, which checks its exact negative
result. It is excluded from the positive suite.

The native app exceeded the upstream emitter's function-ID limit: the failing
source generated 69,676 segments against a maximum of 65,536 identifiers.
Extra swap and splitting the emitted C cannot change that limit. Native builds
therefore use `scripts/native-compiler.py`, which stages an isolated copy of
the upstream compiler with `patches/bend-native-ids.patch`. It does not replace
the installed Bend or alter the checker, proof kernel, Base or JS emitter.

The patch uses four previously unused bits in the native term's tag field:

| Field | Bits | Bound |
| --- | --- | --- |
| Function identifier | 40–55 and 59–62 | 0–1,048,575 |
| Constructor identifier | 40–55 | 0–65,535, unchanged |
| Runtime tag | 56–58 | Existing tags 1–6 |
| Heap location | 0–39 | Unchanged |
| Reference-count marker | 63 | Unchanged |

Small identifiers retain their original bit representation. Constructor and
function table limits are checked separately; overflow still fails explicitly.
Terms are process-local runtime values, not persisted event or wire formats.

The source is [Bend v2.0.36](https://github.com/bendlang/bend/tree/v2.0.36),
licensed under Apache-2.0. The archive is pinned to SHA-256
`cbcd6f4b75897a05065872efac9b8d43595a467118331461eb1b92429b9e1689`,
and the unmodified emitter to
`4e5ee824d2624eb8eb3ba408fd99671239e72759371e562f1a83d50bb614649a`.
Patch application requires exact context. The cache receipt hashes every
retained source/effect/license file and rejects a changed or incomplete cache.
It lives under `$XDG_CACHE_HOME/backplane-bend/compiler` (default
`~/.cache/backplane-bend/compiler`). A cold setup downloads at most 128 MiB
with a 60-second socket timeout. A warm setup uses the verified cache offline:

```sh
python3 scripts/native-compiler.py --prepare
```

Native builds require Python 3.12+, Bun and `patch`, in addition to the existing
clang 19+ and host headers. The C emit cache includes the launcher, patch and
actual Bun executable in its input identity. `scripts/build.sh` retains the
upstream license, patch and compiler/Bun identities under `dist/licenses/bend`;
`scripts/package.sh` includes that directory in its archive.

Split builds retain the same receipt, license and patch beside the emitted C
in `build/cc/NAME/compiler`. Transfer this directory together with `all.c`
and the web bundle for `BACKPLANE_PREBUILT=1`. The receiving host verifies the
pinned provenance and packages the original emitter's identity without needing
Bun for native compilation. Missing or mismatched provenance fails the build.

Run the focused guards with:

```sh
python3 -m unittest discover -s test/tools -p test_runner_test.py
python3 test/tools/native_compiler_test.py
scripts/check.sh
scripts/test.sh
scripts/build.sh
scripts/smoke.sh
```

The native guard executes the actual ID allocation code at both limits,
compiles an oracle from the actual emitted term operations, checks high IDs,
heap/reference-count separation and the original small-ID ABI, and compiles
and runs a complete small CPU program. The full builds and smoke tests remain
required: a packing oracle alone does not validate the complete application.
