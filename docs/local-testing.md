# Local testing

Local builds need no tag, nightly, hosted workflow or release publication. Use
this checkout, pinned Bend, a local Bun, Python and the already installed Electron 44.9.2
runtime. The commands below do not change the installed profile or event log.

```sh
# One coordinated gate after the batch is implemented. Reuses exact-input passes.
python3 scripts/local-ci.py --dry-run
python3 scripts/local-ci.py

# Build a review stage independently of CI/release scheduling.
python3 scripts/local.py build --smoke
cat build/local/LATEST

# Preview the printed stage with a new isolated home; never the live profile.
python3 scripts/local.py preview /absolute/path/to/build/local/STAGE
```

`build --smoke` records service/web, desktop staging, phone bridge, Android compile (when its SDK is present) and UI test
times in `LOCAL.json`. It then qualifies that same server with the shared
wire fixture, full smoke, Mailroom triage, stack, Bun effects, heartbeat and
phone bridge checks. Each runtime command has its own log and timing under
`runtime-evidence/`. A matching exact-input runtime pass reuses those checks;
the new artifact still has to start and serve its complete web assets.
The existing content-keyed server emit and web caches
are shared across worktrees. Shell edits reuse both. An explicit
`--runtime /absolute/runtime` selects an installed Electron runtime; npm installs
only the pinned dependencies, without downloading Electron. The Linux sandbox
stays enabled, reusing an existing root-owned helper where already configured.
The preview starts with a separate home, blocked automation, no tailnet,
telemetry OFF and updates OFF. Closing the window leaves its test hub alive;
the acceptance test cleans up only its own captured child.

To apply a passing stage locally:

```sh
python3 scripts/local.py apply /absolute/path/to/build/local/STAGE
# After the harness reports its safe restart:
python3 scripts/local.py activate /absolute/path/to/build/local/STAGE
# Open Backplane again to load the new shell.
```

Apply requires both UI and runtime acceptance. It copies the reviewed stage into `~/.local/share/backplane-local/STAGE`,
saves the previous service/web/launcher there and asks the hub to deploy at a
safe point. It does not restart systemd directly. Activate requires the exact
expected service version and commit before replacing the desktop launcher.
The normal supervised headless hub, profile, event log and privacy/automation
settings stay in place. No UI close shuts down that hub.
`DEPLOY.json` records preparation/queue time and, when activated, the time until
the exact new greeting was observed. That latter interval is an upper bound
including the safe-point wait and any delay before activation, not an invented
restart duration.

Rollback uses the same safe hub deployment:

```sh
python3 scripts/local.py rollback /absolute/path/to/build/local/STAGE
```

Keep the installed local stage until its successor is accepted; it holds both
the active desktop and rollback. Do not delete it as a disposable worktree build.

The combined CI controller takes one machine-wide lock before admission,
reserves 16 GiB/two cores through `bp-admit`, runs two test workers at most and
records every gate's elapsed seconds and reused input key in
`build/local-ci/TIME/RESULT.json`. Proof keys cover the actual import closure,
compiler/libraries and runner; test keys also include JS/Python drivers. A
changed input, corrupted record, incomplete run or failure cannot create a pass.
The build stage is always recreated and inspected, even when other gates reuse passes.
`--full` ignores passes. CI remains dispatch-only on GitHub; local testing never
dispatches hosted runners. Boat's existing opt-in, budget, start limits and
cleanup policy remain authoritative. No runner registration, allocation or
account limit is changed by this workflow.

For a measured historical comparison, hosted CI runs
[39806371387](https://github.com/i2cjak/Backplane/actions/runs/39806371387)
and [39805054562](https://github.com/i2cjak/Backplane/actions/runs/39805054562)
took 16m59s and 20m08s from creation to completion. Their longest test shards
took 1015s and 1148s; JS-service jobs took 202s and 205s. Those runs overlapped
push and PR triggers. The current dispatch-only policy prevents that duplication.
These are historical hosted measurements, not a claim about the new local run.
The first cold local suite took 1353.880s with two workers; it did not beat
those hosted wall times. After a staging-only fix, exact-input reuse reduced
the type-check/proof work from 249.382s to 0.294s of cache validation. Local
testing used Bun 1.3.10; the existing dev workflow warns that bundled Bun
notices name the release pin, 1.4.3. This is a local test qualification.

The passing combined stage measured 1.321s for cached service/web staging,
0.484s for the desktop, 0.120s for the cached phone bridge, 2.647s for the real
Electron UI acceptance and 29.419s for the full runtime checks (including
2.082s for Mailroom triage). The corrected full suite passed all 261 files in
1357.241s. The X11 check verifies the Backplane icon and launcher identity;
opaque pixels and alpha are exact, with at most one channel unit of rounding
allowed on translucent edges. Native macOS/Windows packaging remains untested.

The shared phone bridge is built or reused by its exact inputs in the same acceptance sequence; Android Kotlin is compiled when an SDK is available. iOS native
builds require a Mac; Android native builds require an SDK. Linux screenshots
at phone width qualify the web layout, not native phone binaries.
