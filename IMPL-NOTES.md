# ios-snappy increment 1, implementer B

- Only this worktree and branch snappy/1b are edited. No push, PR, deployment or device/simulator operations.
- Navigation fields are appended; bot thread destinations use the same hub qualification as sel even with one hub. Room and reported remote destinations retain the focused screen's local bot id. Mirrored bots with threads open as bots.
- Plane routine rows also get nav because they open a bot tab. Their nav is the owning bot's thread. The existing act/value still selects that tab.
- Person queues overtake queued background work; JavaScript already running finishes. FIFO order holds within each lane. recv is quiet while person work waits, including the one-second background refresh deadline. Background refreshes continue once the person lane empties.
- Each native app keeps the last 24 thread and bot views. Android also retains 24 page contexts for the cached bot's thread and plane. Cached content is inert; Back remains outside it.
- Taps use a monotonic timer for content timing and a 350 ms push guard. iOS retains its 800 ms post-pop animation guard and the #68 tapped-selection logic. Explicit navigation awaits its requested nav so an older screen cannot undo the push or reopen a cancelled destination.
- Swift nav decoding is optional, and Kotlin defaults empty, to tolerate old screen JSON. Current Bend always supplies row nav.
- DEBUG ACTS supports @open=<name> and @times (prints the last 24 timings). The @open path and BACKPLANE_BOT use the same method as real taps.

Validation so far:

- Isolated Mac `xcodebuild` (Debug, generic iOS Simulator SDK, no simulator boot/install): exit 0. Output tail:
  ```text
  2026-10-13 14:03:46.203 xcodebuild[21692:4304361] [MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.
  ```
- Production Swift queue regression: exit 0. Output:
  ```text
  PASS: production Swift worker: act1 quiet2 recv1 recv2 tick3; personWaiting clears
  ```
- The first shared-lock validation watcher ended with unknown outcome before any test log was written. Its process was gone. No success was assumed; the complete validation batch is being rerun.


The Swift worker has a standalone queue regression harness in `test/tools/phone_worker_test.py`. It extracts the production worker and verifies that two person calls overtake three queued background calls, FIFO order holds within both lanes, and the waiting-person flag clears. It uses no app or simulator.

Bend navigation and regression test batch passed: `mnav`, `mbots`, `hubs`, `mplane`, `plane`, `onboard` all exited 0 with no FAIL lines. The initial full check found a syntax error in the new proof implementation headers (typed binders where law implementations require inferred binders); corrected before rerunning the proof/check. No existing law was altered.

The 14:40 addendum supersedes the original one-second background rule. Both engines will coalesce streaming screens to a 250 ms window with an owed-screen flush; person work bypasses that window. Timing now records both the first destination and first matching live screen. iOS first is measured when `show` actually installs the path, including the preserved post-pop guard; Android first is measured when `opening` is installed. Commit order follows the addendum from this point, and the branch will be rebased onto origin/main before the final commit.

Addendum verification so far:

- Integrated iOS opening, priority lane, first/full timing and 250 ms throttle compile on the Mac (exit 0).
- Actual engine regression (a tiny in-memory JSC bridge; no app/hub/simulator):
  ```text
  PASS: person screen survives queued recv; two quiet frames retain cmds; final version 2 flushes
  PASS: off-screen traffic and its timer build no screen
  ```
- Actual bridge `flush`/`out` regression with JIT disabled:
  ```text
  PASS: actual bridge flush draws an owed screen once, forces a dropped screen, and otherwise builds nothing
  ```
- The standalone engine test observes production queue insertion to make the backlog deterministic. Its bridge fixture supplies only visibility/owed/screens/commands. A harness executor deadlock and a stub signature mismatch were corrected; the actual iOS build also verified the decoder calls.

Rebased onto `origin/main` at `6acaec6b18005670bdee02ac8d6d6f31e241d6e9` before final builds/tests. Resolved the two autostash overlaps: preserved #77's uber opening behavior and #78's `open-url` handling on both phones, plus the unchanged Antigravity mobile settings/provider rows in `screen.bend`. The pre-rebase tracked diff is saved in `build/snappy/pre-rebase.patch`; Git also retained the autostash as a backup.

The room/remote navigation classifier uses a fixed prefix pattern, which both avoids the general String.starts_with proof normalization trap and bounds its work. Added a general law covering every nonempty bot thread without a reserved room/remote prefix; the original example and room/remote laws remain.

Final validation (on the rebased tree, all confirmed exit 0):

- `mnav`, `mbots`, `hubs`, `mplane`, `plane`, `onboard`: all pass with no FAIL/Error lines. mnav covers bots, uber, rooms, reported remote bots with one/two hubs, plus plane threads/bots/rooms/routines.
- `scripts/check.sh`: passes; the only proof notice is the expected foreign-code list accepted by the repository's checker. This includes all four new nav laws and every preserved existing/upstream law.
- `scripts/build-mobile.sh` with JDK 17 and the writable SDK: bridge and release APK built; Kotlin compiles.
- `BUN_JSC_useJIT=0` tap bench on the provided kept state: every one of seven rows matches its opened destination. Bub's full Bend screen took 132 ms on this desktop profile; native first/full instrumentation is present, without claiming device timing.
- Mac `xcodebuild` after the rebase and after copying the freshly built bridge: passes. No app installed and no simulator touched.

The runs above completed before the new harness-coord priority instruction was received. After receiving it, the required pgrep check matched active coordinator processes; no new heavy run was started.

Incremental commits, in the addendum's order:
- d41f6550e iOS: open bots, the uberbot and rooms immediately with cached pages
- 7601effe7 iOS: run person calls ahead of queued hub frames
- 524b1dbe7 Android: add a person lane to the Bend engine
- b9e4e66f5 Phones: coalesce streaming screens for 250 ms and flush the final state

The first opening commit includes Bend nav fields and their laws/tests as its dependency, so it can be built independently. The following commits add the iOS person lane, the Android person lane, and the 250 ms throttle. The final commit adds the already-built Android opening/caches/skeleton/back/debounce/first-full timing, the tap bench, and these notes.

Actual output excerpts:

```text
hubs check exit=0
mnav exit=0
mbots exit=0
hubs exit=0
mplane exit=0
plane exit=0
onboard exit=0
check.sh exit=0
build-mobile.sh exit=0
tap bench exit=0
Mac xcodebuild exit=0
manifest-0.bend: 315 files
manifest-0.bend: 315 files
check: 11s
SOME PROOFS FAIL
Error: 30 defs rely on unsafe or foreign code:
- src/gfx/fontfx.Font.find
- src/gfx/fontfx.Font.open
proof: overlapped with check, total 87s
```

```text
ok plane Nine present
ok plane Nine
ok plane D present
ok plane D
ok plane Digest present
ok plane Digest
mobile nav tests passed

```

```text
bridge-native: String.cmp (sP) and String.eq (W) native
js-unmarshal: hubs.Hubs (KN, eN) crosses as it is
mobile/build/assets/bridge.js (2557939 bytes)
-rw-rw-r-- 1 h h 18827464 Oct 13 15:51 dist/backplane-android.apk
```

```text
2026-10-13 15:52:03.969 xcodebuild[37208:4467974] [MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.
```

```text
open ring-requests           bend    85 ms  parse    0 ms     107 KB  entries - plane n bot room
back ring-requests           bend   100 ms  parse    0 ms      94 KB  entries - plane y bot -
row staff nav=@room:r1790403491-15272
open staff                   bend    88 ms  parse    0 ms     114 KB  entries - plane n bot room
back staff                   bend    95 ms  parse    0 ms      93 KB  entries - plane y bot -
PASS: 7 row navs match opened screens
```

Full logs and generated artifacts remain under `build/snappy/`, the bridge is `mobile/build/assets/bridge.js`, and the APK is `dist/backplane-android.apk`.
