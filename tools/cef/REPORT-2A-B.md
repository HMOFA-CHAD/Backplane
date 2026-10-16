# Implementer B: spec 2a completed

Branch `cef/2a-b`, worktree `browser-cef/wt-2a-b`. No push, PR, merge,
Bend or application `src/` changes, live Backplane data, port 3787, or
input on display :0. All requested builds and acceptance checks passed.

Implemented the keyed multi-browser CEF host, popup children and CDP target
identity; native geometry, focus and shield commands/events; helper engine
selection/switching; Bun CDP adapter for source and compiled runs; CEF runtime
discovery and verified installation; CDP downloads; packaging/checksum; and
both protocol READMEs.

Runtime validation found and fixed two integration issues:

- CEF initially announces a new Alloy child as CDP type `other`. Playwright
  ignores it and asynchronously detaches that session. The helper waits for
  that detach and the final `page` type, then attaches the reported target on
  the same root WebSocket. This also handles popups and creates no targets.
- CDP focus emulation suppresses ordinary CEF focus callbacks when a window
  manager focuses only the embedding parent. The host observes XInput2 raw
  button presses through dlopen’d libXi.so.6 and gives the clicked native
  child X keyboard focus. Its observer consumes none of the page’s input.

## Build and environment

Per the user's correction, all final builds ran **directly** inside the
existing systemd scope capped at 10 GB memory and 3 CPUs. CEF builds use two
Ninja workers. No nested bp-admit or CPU-count override was used. The earlier
passive admission waiter was already gone when this turn began; no signal
was sent to it. The existing CEF 154.0.34 distribution was reused without
re-downloading it.

Exact commands, from this worktree root:

```sh
(cd tools/browser && bun install --frozen-lockfile)
BACKPLANE_JOBS=2 nice -n 10 scripts/build-cef.sh
nice -n 10 bun tools/browser/build.ts build/cef-test/backplane-browser
```

Dependency install exited 0 with `Checked 1 install across 2 packages (no changes)`.
The initial CEF build compiled 213 targets. The final incremental build
exited 0 and printed:

```text
ninja: Entering directory `/home/h/Documents/i2cjak/bp-coord/browser-cef/wt-2a-b/build/cef'
[1/2] Building CXX object CMakeFiles/backplane-cef.dir/host.cc.o
[2/2] Linking CXX executable Release/backplane-cef
/home/h/Documents/i2cjak/bp-coord/browser-cef/wt-2a-b/build/cef/Release/backplane-cef
```

The helper compile exited 0 with no stdout/stderr. Its compiled executable
is `build/cef-test/backplane-browser`.

## Acceptance commands and exact test stdout

Every browser run owned its private Xvfb on a free display in 96..99 and an
independent X11 parent, and used temporary profiles. Runs were sequential.
CEF hosts/helpers/parents ended through quit/EOF; only each test’s captured
Xvfb PID was signalled. The existing Chrome tests remain unchanged (including
their own captured-helper cleanup). No browser or test Xvfb was left running.

Full combined stdout/stderr logs are retained under `build/cef-test/logs/`.
The verbatim test stdout is below; harmless Mesa/amdgpu warnings and DevTools
endpoint diagnostics on stderr are omitted from these stdout blocks.

### Existing Chrome regressions

```sh
bun tools/cef/test/chrome.ts
```

The wrapper runs `bun tools/browser/test/pages.ts` and then
`bun tools/browser/test/record.ts` unchanged. 110 checks passed.

Exit 0. Stdout:

```text
ok   shared open
ok   shared raw frames on
ok   bot-1 open
ok   a.b/c open
ok   shared status
ok   bot-1 status
ok   shared url unchanged
ok   bot-1 url
ok   per-owner viewport
ok   bot-1 unwatched: a frame, not a cast
ok   bot-1 cast
ok   bot-1 cast: jpeg events
ok   bot-1 lease over: not cast again
ok   shared jpeg event
ok   a.b/c jpeg event
ok   raw frame events have no page
ok   bot-1.jpg is a JPEG
ok   shared.jpg is a JPEG
ok   a_b_c.jpg is a JPEG
ok   raw frame file
ok   bot-1 n increases
ok   bot-1 navigate
ok   shared status again
ok   shared unaffected by bot-1 navigate
ok   type on shared
ok   select
ok   select value
ok   select chose b
ok   upload
ok   upload seen by page
ok   download
ok   download saved
ok   open popup
ok   tabs
ok   popup joined bot-1 tabs and is active
ok   close popup tab
ok   tabs after close
ok   back on the form
ok   bot-1 to /me
ok   back
ok   back went to form
ok   forward
ok   reload
ok   text
ok   text reads main, capped
ok   cookie shared across pages
ok   screenshot
ok   screenshot png
ok   pdf
ok   pdf written
ok   pages
ok   pages lists three owners
ok   status with page in args
ok   args.page ignored
ok   close a.b/c page (helper stays)
ok   a.b/c jpg removed
ok   pages after close
ok   two owners left
ok   helper still alive
ok   run 2 text (blank)
ok   run 2 navigate
ok   run 2 text
ok   cookie survived a restart
ok   cookies_clear
ok   reload
ok   run 2 text after clear
ok   cookies cleared
all passed
ok   bot-t open
ok   bot-u open
ok   click before record
ok   no steps before record
ok   record on
ok   record result
ok   click Do thing
ok   type search
ok   type password
ok   type card
ok   select colour
ok   press Tab
ok   bot-u click
ok   bot-u type
ok   bot-u press
ok   click Go
ok   reached /done
ok   click step: role button, name
ok   click step keys
ok   target keys
ok   css prefers #id
ok   type step: value present
ok   one type step for the search field
ok   password: secret, label, no value
ok   card: secret, no value
ok   select step
ok   press Tab step
ok   submit step
ok   navigate to /done
ok   navigate deduped
ok   every step has at
ok   click link
ok   reached /two
ok   link click step
ok   navigate to /two
ok   another owner emitted nothing
ok   record off
ok   record off result
ok   click after off
ok   back home
ok   click body after off
ok   no events after record off
ok   secrets never on stdout
all passed
```

### Runtime discovery, checksum and installation

```sh
bun tools/browser/test/cef-runtime.ts
```

Exit 0. Stdout:

```text
ok  empty runtime URL errors clearly
ok  find cache runtime
ok  environment overrides cache
ok  explicit path overrides environment
ok  SHA mismatch rejects before unpack
ok  verified archive installs into version cache
all CEF runtime checks passed
```

### Native host protocol

```sh
BACKPLANE_CEF="$PWD/build/cef/Release/backplane-cef" bun tools/cef/test/host.ts
```

Exit 0. Stdout:

```text
ok  no startup browser without --url
ok  rejects malformed "nonsense"
ok  rejects malformed "create"
ok  rejects malformed "create a.b about:blank"
ok  rejects malformed "create a"
ok  rejects malformed "hide extra"
ok  rejects malformed "shield 2"
ok  rejects malformed "quit extra"
ok  rejects malformed "show a 0 0 0 1"
ok  rejects malformed ""
ok  created includes command, key, XID, target and timestamp
ok  created target matches /json/list
ok  create child is unmapped with default size
ok  show mapping
ok  size preserves hidden state
ok  command close reason
ok  host survives last browser close
ok  window.close has page reason
Browser.close response {"id":1,"result":{}}
ok  CDP Browser.close leaves host running
ok  EOF closes remaining browsers and exits zero
all host protocol checks passed
```

### Source helper CEF acceptance

```sh
BACKPLANE_CEF="$PWD/build/cef/Release/backplane-cef" bun tools/browser/test/cef.ts
```

Exit 0. Stdout:

```text
ok  engine cef starts
ok  a owns its snapshot
ok  b owns its snapshot
ok  exactly two page targets
ok  no top-level Chrome window
ok  a mapped at exact geometry; b hidden
ok  show b swaps children
ok  helper hide unmaps every browser
ok  hidden resize preserves unmapped state
ok  status reports real viewport
ok  CDP context binding and init script record click/type
ok  a hidden cast produces JPEG
ok  b shown cast produces JPEG
ok  popup is active owner tab
ok  popup inherits owner recording
ok  popup adds exactly one child
ok  tabs new uses embedded child
ok  agent CDP input works through shield
ok  shield blocks pointer and wheel
ok  shield coordinates are page CSS px
ok  unshielded pointer and wheel reach page
ok  real desktop click transfers X keyboard focus
ok  native focus event names the owner
ok  focus op accepts XTest keyboard input
ok  CEF pdf has clear error
ok  CEF download saves suggested file
download result {"path":"/tmp/bp-cef-test-vBOVKY/dl/cef.txt","url":"http://127.0.0.1:34959/file","suggestedFilename":"cef.txt","bytes":13}
ok  CEF shared raw RGB frames
ok  closing a keeps b and host alive
ok  last browser close keeps host running
ok  new page after last close uses same host
ok  switch to Chrome reopens active URLs
ok  old CEF host exited after switch
ok  switch back reopens active URLs
ok  helper close exits zero
ok  helper close waits for host exit
all CEF acceptance checks passed
```

### Source helper CLI startup, host exit/relaunch and EOF

```sh
BACKPLANE_CEF="$PWD/build/cef/Release/backplane-cef" bun tools/browser/test/cef-lifetime.ts
```

Exit 0. Stdout:

```text
ok  --engine cef and --cef launch directly
ok  host exit reports engine failure and closed
ok  host exit clears owner tabs
ok  old owned host exited
ok  next page request relaunches host
ok  reopened owner has new document
ok  helper EOF exits zero
ok  helper EOF waits for host exit
all CEF lifetime checks passed
```

### Compiled helper CEF acceptance

```sh
BACKPLANE_BROWSER="$PWD/build/cef-test/backplane-browser" BACKPLANE_CEF="$PWD/build/cef/Release/backplane-cef" bun tools/browser/test/cef.ts
```

Both compiled runs passed with `tools/browser/node_modules` temporarily
renamed to `node_modules.cef-test`, then restored by the shell’s EXIT trap.
This verifies the bundle and ws transform without the build-time packages.

Exit 0. Stdout:

```text
ok  engine cef starts
ok  a owns its snapshot
ok  b owns its snapshot
ok  exactly two page targets
ok  no top-level Chrome window
ok  a mapped at exact geometry; b hidden
ok  show b swaps children
ok  helper hide unmaps every browser
ok  hidden resize preserves unmapped state
ok  status reports real viewport
ok  CDP context binding and init script record click/type
ok  a hidden cast produces JPEG
ok  b shown cast produces JPEG
ok  popup is active owner tab
ok  popup inherits owner recording
ok  popup adds exactly one child
ok  tabs new uses embedded child
ok  agent CDP input works through shield
ok  shield blocks pointer and wheel
ok  shield coordinates are page CSS px
ok  unshielded pointer and wheel reach page
ok  real desktop click transfers X keyboard focus
ok  native focus event names the owner
ok  focus op accepts XTest keyboard input
ok  CEF pdf has clear error
ok  CEF download saves suggested file
download result {"path":"/tmp/bp-cef-test-dcvHpi/dl/cef.txt","url":"http://127.0.0.1:43721/file","suggestedFilename":"cef.txt","bytes":13}
ok  CEF shared raw RGB frames
ok  closing a keeps b and host alive
ok  last browser close keeps host running
ok  new page after last close uses same host
ok  switch to Chrome reopens active URLs
ok  old CEF host exited after switch
ok  switch back reopens active URLs
ok  helper close exits zero
ok  helper close waits for host exit
all CEF acceptance checks passed
```

### Compiled helper CLI startup, host exit/relaunch and EOF

```sh
BACKPLANE_BROWSER="$PWD/build/cef-test/backplane-browser" BACKPLANE_CEF="$PWD/build/cef/Release/backplane-cef" bun tools/browser/test/cef-lifetime.ts
```

Exit 0. Stdout:

```text
ok  --engine cef and --cef launch directly
ok  host exit reports engine failure and closed
ok  host exit clears owner tabs
ok  old owned host exited
ok  next page request relaunches host
ok  reopened owner has new document
ok  helper EOF exits zero
ok  helper EOF waits for host exit
all CEF lifetime checks passed
```

## Package and unpacked-runtime validation

```sh
BACKPLANE_JOBS=2 nice -n 10 scripts/build-cef.sh --package build/backplane-cef-linux-x64.tar.zst
(cd build && sha256sum -c backplane-cef-linux-x64.tar.zst.sha256)
mkdir -p build/cef-runtime-test
tar --zstd -xf build/backplane-cef-linux-x64.tar.zst -C build/cef-runtime-test
BACKPLANE_CEF="$PWD/build/cef-runtime-test/backplane-cef" bun tools/cef/test/host.ts
```

All commands exited 0. Package command output:

```text
ninja: Entering directory `/home/h/Documents/i2cjak/bp-coord/browser-cef/wt-2a-b/build/cef'
[1/1] Linking CXX executable Release/backplane-cef
/home/h/Documents/i2cjak/bp-coord/browser-cef/wt-2a-b/build/cef/Release/backplane-cef
136983592 build/backplane-cef-linux-x64.tar.zst
```

Checksum output: `backplane-cef-linux-x64.tar.zst: OK`.

- Package: `build/backplane-cef-linux-x64.tar.zst`
- Size: **136,983,592 bytes (130.64 MiB)**
- SHA-256: `0d340a0f35909e3dc337be3e79e2139b4cb484214df550103f4c62919042eb1d`
- Sibling checksum: `build/backplane-cef-linux-x64.tar.zst.sha256`
- Stripped libcef.so: 272,219,288 bytes.
- Stripped backplane-cef: 608,960 bytes.
- Compiled helper: 107,566,989 bytes.

Archive contents:

```text
backplane-cef
libcef.so
chrome_100_percent.pak
chrome_200_percent.pak
resources.pak
icudtl.dat
v8_context_snapshot.bin
locales/en-US.pak
libvk_swiftshader.so
vk_swiftshader_icd.json
libvulkan.so.1
LICENSE.txt
```

Only en-US is packaged; the host pins en-US. chrome-sandbox is omitted
because the host uses no_sandbox. The unpacked runtime passed all 20 host
checks, ending with `all host protocol checks passed`.

Additional final checks:

```sh
sh -n scripts/build-cef.sh
git diff --check
```

Both exit 0 with no output.

## Deviations and implementation details

- **Top-level X window exception:** CEF requires its unmapped `Chromium
  clipboard` selection-owner window at the X root. The test excludes only
  that exact unmapped infrastructure window. Every actual page and popup
  is verified as a child; no Chrome browser UI window is created. This is
  the one exception to a literal “no Chromium-named root children” check.
- **Same-cache CEF reconfiguration:** an already running CEF host using
  the same cache must quit before its replacement reopens URLs, because
  CEF’s singleton profile lock forbids concurrent hosts on that cache.
  Chrome↔CEF switches reopen active URLs before closing the old engine,
  as specified; recording stops for either transition.
- **Hidden focus:** SetFocus(true) still runs for a hidden page, but
  XSetInputFocus runs only for a shown, viewable child, since X11 rejects
  focus on an unmapped window with BadMatch. Shown-page focus uses
  RevertToParent and passed real XTest clicks and keys.
- **Target attachment:** the extra root-session attach described above
  handles CEF’s initial `other` target phase. It uses a separate request-id
  range in the Bun adapter and consumes only those replies; Playwright
  still receives ordinary target events. No private Playwright APIs or
  Target.createTarget calls are used.
- **ws transform:** guards the WebSocket constructor rather than assigning
  the read-only utilsBundle.ws getter. It is inert for Chrome and works in
  source and compiled runs. The compiled tests also passed with local
  node_modules absent.
- **Keys:** long safeOwner names are truncated to 48 characters and get a
  global monotonic tab suffix, to fit the 64-character controller-key limit
  while disambiguating long/colliding names.
- **Artifact isolation:** the compiled helper is under this worktree’s
  `build/cef-test/` instead of shared `/tmp/x/`, avoiding collisions with
  other implementers on this machine.
- **Build admission:** direct builds inside the existing capped scope
  replace the spec’s nested bp-admit command, per the user’s explicit
  correction. Memory/cpu scope limits remain in effect.
- Device scale factor is pinned to 1 so shield coordinates equal page CSS
  pixels. The original single-browser bench keeps its old spike protocol;
  the new acceptance tests exercise the multi-browser contract.

No acceptance work remains blocked. Downloads work on the pinned runtime;
PDF intentionally answers `pdf needs the headless engine`. The runtime
asset URL and SHA constants remain empty for the lead to publish later,
as requested. IME, GPU performance and non-X11 platforms were outside this
increment’s acceptance tests.
