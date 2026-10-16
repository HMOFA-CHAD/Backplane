# Implementer B: spec 2a

Branch `cef/2a-b`, worktree `browser-cef/wt-2a-b`. No push, PR, merge,
Bend/src changes, live Backplane data, or display :0 use.

Implemented the keyed multi-browser CEF host, popup children and CDP target
identity, native geometry/focus/shield protocol, helper engine selection and
switching, Bun CDP adapter for source/compiled use, CEF runtime discovery and
verified installation, downloads over CDP, runtime packaging/checksum, and
protocol documentation. Added independent X11/XTest acceptance fixtures,
host protocol checks, CEF helper checks, host-EOF/relaunch checks, and runtime
installer checks. CEF runtime tests are still pending; implementation claims
below are distinguished from verified behavior.

## Verified commands/results

Run from the worktree root:

```sh
(cd tools/browser && bun install --frozen-lockfile)
```

Output: `Checked 1 install across 2 packages (no changes)`; exit 0.

```sh
bun tools/cef/test/chrome.ts
```

The wrapper runs these **unchanged** tests sequentially, both with DISPLAY
set to a free private Xvfb it owns, with temp profiles:

```sh
bun tools/browser/test/pages.ts
bun tools/browser/test/record.ts
```

Final run: exit 0; 110 `ok` lines; each test ends with `all passed`.
Full local stdout/stderr is `/tmp/cef-2a-b-chrome-final.log`. The private
Xvfb and parent were shut down before any subsequent browser test.

```sh
bun tools/browser/test/cef-runtime.ts
```

Exit 0, exact stdout:

```text
ok  empty runtime URL errors clearly
ok  find cache runtime
ok  environment overrides cache
ok  explicit path overrides environment
ok  SHA mismatch rejects before unpack
ok  verified archive installs atomically into version cache
all CEF runtime checks passed
```

```sh
clang++ -std=c++20 -fsyntax-only -I /home/h/.cache/backplane/cef/154.0.34 tools/cef/host.cc
sh -n scripts/build-cef.sh
git diff --check
```

Each exits 0 with no output. The lightweight C++ check only checks syntax
and the pinned CEF API; it does not link or replace the required host build.
An initial manual syntax check with `-std=c++17` failed on CEF's C++20
concepts; corrected to CEF's required C++20 (the existing CMake CEF setup
already supplies the proper language standard).

## Outstanding build/runtime validation

The required build has been queued through:

```sh
/home/h/Documents/i2cjak/bp-coord/bin/bp-admit.sh --mem 4 --cores 2 -- scripts/build-cef.sh
```

It has not been admitted. Example exact output:

```text
bp-admit: waiting (behind-older=1, avail 22 GB, pending 23 GB, cores reserved 10, load 20, 5 jobs)
```

Five live admitted 10 GB scopes on the 59 GB machine leave insufficient
reservation headroom for the additional 4 GB build plus bp-admit's 8 GB
reserve. No admission rules or shared reservations have been altered.
The coordinator has been asked to free one of its owned reservations.

After admission, remaining commands (one browser test at a time):

```sh
BACKPLANE_CEF="$PWD/build/cef/Release/backplane-cef" bun tools/cef/test/host.ts
BACKPLANE_CEF="$PWD/build/cef/Release/backplane-cef" bun tools/browser/test/cef.ts
BACKPLANE_CEF="$PWD/build/cef/Release/backplane-cef" bun tools/browser/test/cef-lifetime.ts
/home/h/Documents/i2cjak/bp-coord/bin/bp-admit.sh --mem 4 --cores 2 -- bun tools/browser/build.ts /tmp/x/backplane-browser
BACKPLANE_BROWSER=/tmp/x/backplane-browser BACKPLANE_CEF="$PWD/build/cef/Release/backplane-cef" bun tools/browser/test/cef.ts
BACKPLANE_BROWSER=/tmp/x/backplane-browser BACKPLANE_CEF="$PWD/build/cef/Release/backplane-cef" bun tools/browser/test/cef-lifetime.ts
/home/h/Documents/i2cjak/bp-coord/bin/bp-admit.sh --mem 4 --cores 2 -- scripts/build-cef.sh --package build/backplane-cef-linux-x64.tar.zst
sha256sum -c build/backplane-cef-linux-x64.tar.zst.sha256
wc -c build/backplane-cef-linux-x64.tar.zst
```

Package size: **not measured; build/package pending admission**.
Downloads and native input are not yet runtime verified.

## Deliberate protocol/implementation details

- The ws source transform guards the WebSocket constructor, rather than
  replacing utilsBundle.ws (a read-only getter). This keeps Chrome's
  original transport and permits switching engines in the same process.
- Controller keys use safeOwner truncated to 48 characters plus a global
  monotonic tab counter, so long/colliding owner names remain unique and
  fit the host's 64-character controller-key limit.
- Reconfiguring an already running CEF host with the same cache closes it
  before reopening URLs, because CEF's singleton profile lock prevents
  concurrent hosts on that cache. Chrome↔CEF switches reopen URLs first as
  specified. Recording stops for either transition.
- `focus` calls CEF SetFocus for a hidden page, but only calls XSetInputFocus
  when the child is shown: X11 rejects focus on an unmapped window with
  BadMatch. Shown-page focus follows the specified RevertToParent behavior.
- Device scale factor and locale are pinned to 1 and en-US so shield CSS
  coordinates equal native pixels and the packaged en-US locale suffices.
- The previous single-browser bench uses the old stdin protocol; it is
  retained as a spike artifact, and new acceptance tests use the new contract.
