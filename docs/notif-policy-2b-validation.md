# Notification Settings, increment 2B

Implementation commit: `fc430f550`, branch `notif-policy/2b`.

The window, web, iOS and Android Settings use `Notify.rows` and the existing
`setting` action immediately after Continue after a restart. Defaults come
from `Policy.on`. Window descriptions wrap; their measured height is added
to the Settings scroll extent. Existing web CSS wraps these rows. Both phone
Settings views render arbitrary rows and buttons, so no Swift or Kotlin
source change is needed. The normal hub `setting.set` path accepts every key.

Validation completed in this worktree with Bend 2.0.36, on CPUs 0–5 at nice 19:

- `bend test/notify_settings_test.bend`: 60 assertions pass. Covers defaults,
  SettingSet changes, labels in all three shared layouts, both controls for
  every key, immediate local updates without changing the sequence, emitted
  RPCs, and the hub accepting each key.
- `bend test/menu_test.bend`: 23 assertions pass, including Settings scrolling.
- `bend test/notice_test.bend`: 20 assertions pass.
- `bend src/mobile/screen.bend --check-only`: ALL PROOFS CHECK.
- The exact `notify_rows_defaults` law and its production proof were extracted
  into an isolated fixture importing the changed production modules:
  `bend build/notif-policy/rows-proof.bend` prints ALL PROOFS CHECK.
- `git diff --check`: passes.

The shared `/tmp/bp-bend.lock` had been held for more than 20 minutes. The
single-test fallback permitted by the task was used. Foreground acquisition
attempts for `scripts/check.sh` (20 seconds), combined check/test (60 seconds),
root `bend PROOF.bend` (20 seconds), and `scripts/test.sh` (1 second) timed out
with flock status 1 before those programs ran. Full check, root proof and
suite results are therefore **unavailable**, not passing. No validation job
was left queued behind the lock. The lead must run these gates before acceptance.

Window screenshots were rendered by `test/native/ui_snap.bend`, executed on
Bend's JS lane with the bitmap font, then converted from PPM. The native
application binary and phone binaries were not built because the shared
build locks remained occupied. No device or simulator test was performed.
The fixtures mark both onboarding steps complete so the Settings are unobscured.

Web screenshots use the actual `View.settings` DOM emitted by
`test/native/notify_settings_web.bend`, converted to HTML with the existing
`src/web/style.css`, and rendered by headless Chrome. No throwaway hub or
web bundle was built; these are static Settings snapshots, not an interaction
or end-to-end test. No live hub or `~/.backplane-bend` was accessed.

Screenshots, visually reviewed:

- `/home/h/Documents/i2cjak/bp-coord/notif-policy/shots/2B-window-dark.png`
- `/home/h/Documents/i2cjak/bp-coord/notif-policy/shots/2B-window-light.png`
- `/home/h/Documents/i2cjak/bp-coord/notif-policy/shots/2B-web-dark.png`
- `/home/h/Documents/i2cjak/bp-coord/notif-policy/shots/2B-web-light.png`

Foreground logs and the snapshot fixtures are under `build/notif-policy/`
(ignored by Git).
