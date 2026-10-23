# Cooperative Electron Browser

Source restoration for combined UI batch `t1792700806-414704`. This document is
an acceptance plan, not a passing runtime report. No independent build, CI,
runtime test, installation, profile migration or release was run by this lane.

The existing sandboxed `WebContentsView` is the page shown in Browser. The
existing private main/service channel authorizes both toolbar intents and the
agent's `preview_*` calls against that actual owner/tab/document. The bridge
exposed to the app renderer supplies geometry, status, reconnect and takeover
events. It exposes no credentials, guest object or CDP command channel.

The missing seams were the preload's `.browser` bridge and the thin renderer's
device-hint allowlists. A saved controller state query handles renderer reloads.
The thread strip says who drives and offers Take over/Hand back; the native
shield consumes the takeover click and releases input only after the service
grants it. Its background is transparent so the person can watch the actual
page while the bot drives. Native input replies may acknowledge a navigation
without acquiring authority to command the new document.

Preview compatibility includes generation-scoped snapshot refs, CSS and basic
role/name and text locators, literal typing, key events, scrolling, JavaScript,
condition waits, localhost URL normalization, `domContentLoaded` readiness and
optional bounded PNG snapshots. Advanced Playwright locator syntax and frame
selection remain outside this adapter. An oversized image is refused with a
text-snapshot suggestion. The service's exact method allowlist includes only
the added target-scoped `Page.captureScreenshot`; file chooser/upload and
Browser/Target session escapes remain refused.

The Electron guest partition remains `persist:backplane-browser-guests` in the
selected home's existing `electron-profile`. No profile is cleared or copied.
The prior CEF/Chrome `browser-profile` remains on disk; its cookies are not
silently imported into Electron. The local native surface is used only for a
local owner; a remote owner must follow the existing remote page route. There
is no separate automation browser or bot profile fallback in desktop mode.

## Integrator's one combined run

Use the combined source and the batch's one build/stage. Ensure that the staged
shell advertises direct Browser protocol 1 and its **actual running service**
started with `BACKPLANE_DESKTOP_BROWSER=1`. Reusing an old mode-0 resident hub
cannot be fixed by retrying the renderer; confirm the intended home's service
and perform the already-authorized batch local apply. Keep telemetry and mail
off in the isolated fixture and retain the established rollback/profile policy.

Run `node --test desktop/test/browser-preload.test.cjs
desktop/test/no-browser-hub.test.cjs` with the other selected batch checks. The
integrator owns the required Bend proof check before any combined commit.
Preserve laws; this lane neither changed nor weakened `LAWS.bend`.

Import `runSharedBrowserAcceptance` from
`desktop/test/shared-browser.cjs` into the existing real Electron acceptance
runner, after its fixture reaches `backplaneRemoteReady=true`:

```js
await runSharedBrowserAcceptance({
  app, page, origin, token, threadId, otherThreadId,
  out: path.join(evidenceDir, 'shared-browser'),
});
```

`app/page` must be the already-running Electron fixture; `token` stays in the
test runner. Both threads must exist in that isolated fixture. The helper
starts only a controlled local HTTP site with `frame-ancestors 'none'` and
`X-Frame-Options: DENY`. No login, 2FA, external message, purchase or provider
turn is involved. It exercises the actual HTTP MCP preview route and native
Electron views/input, not fake IPC or another browser. It writes a JSON receipt
and a screenshot. Return actual failures to this lane; do not treat the plan as
proof that the runtime passed.

Checks cover visible native guest geometry/security settings, bot ref edits,
scroll/evaluate/wait, a swallowed shield click, canonical takeover, bot refusal,
trusted human edits to the same document, handback and fresh snapshot, role
locators and local Enter submission, navigation readiness, stale-ref refusal,
toolbar history/reload, renderer reload, storage/cookie retention, native tab
creation/selection/close and per-thread identity. A fixture script's direct
metadata observations are test-only and never become product bridge methods.

## Manual and remaining verification

- Physically open Browser, type a local address, navigate/back/forward/reload,
  scroll, and resize the app. Watch that the page remains visible under the
  agent's transparent shield. A normal cross-origin HTTPS site that denies
  embedding must load as native content; do not authenticate or send anything.
- Let a bot snapshot and change the controlled page. Click the displayed page
  once: it takes control without triggering its button/link. Type and click
  with real keyboard/mouse, including composition if applicable. Bot preview
  calls must refuse during takeover. Hand back; the next snapshot must show
  those exact edits. Open/dismiss overlays and change thread/tab while driving.
- Reload/crash/recover the app renderer and confirm the same native guest and
  latest state return. Reconnect an unavailable service explicitly; no uncertain
  command may replay. A service/controller disconnect currently disposes guest
  objects; no cross-process JavaScript heap/sessionStorage restoration is
  claimed. Reopening still uses the retained persistent guest profile.
- Full Electron exit/relaunch cookie retention needs the **same isolated home**
  in a second launch. The helper checks renderer reload and cookie flush, not
  this separate lifetime. No product profile is used as a fixture.
- Remote machine page delivery and reconnection, physical IME, unqualified
  popup adoption, downloads/uploads and target-scoped cross-frame automation
  remain unverified here. Existing popup/file guards are preserved, including
  denial of unqualified popups. Remote pages are not represented as local native
  guests; verify the remote transport before claiming remote-browser acceptance.

Native view visibility/bounds and transparent backgrounds use Electron's
[View API](https://www.electronjs.org/docs/latest/api/view). Runtime evidence,
rather than API availability alone, decides acceptance on this workstation.
