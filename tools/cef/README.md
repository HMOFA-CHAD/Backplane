# backplane-cef

A real Chromium (CEF, the Chromium Embedded Framework) drawn as a native
child window inside Backplane's X11 window, so the Browser panel gets
Chromium's own input, scrolling, IME, clipboard and focus. Agents drive the
same page over CDP (`--port`), so the person and the agent never hold two
copies of one page.

Linux X11 only for now. macOS, Windows and Wayland need their own embedding
(CEF has `SetAsChild` on each, but Wayland has no foreign child windows).

```sh
scripts/build-cef.sh                  # -> build/cef/Release/backplane-cef (+ libcef.so, paks, locales)
build/cef/Release/backplane-cef --url https://example.com --size 800x600 --port 9333
```

`scripts/build-cef.sh` fetches the prebuilt CEF minimal distribution once
into `$XDG_CACHE_HOME/backplane/cef/<version>` (checked against its sha1),
builds `libcef_dll_wrapper` and `host.cc` with CMake and Ninja
(`BACKPLANE_JOBS`, default 2), and strips `libcef.so` (1.4 GB with debug info,
260 MB without). Chromium is never built from source.

Flags:

- `--parent XID`: embed in that window. Without it the host makes its own
  test window.
- `--url URL`, `--size WxH`, `--at XxY` (the child's place in the parent).
- `--cache DIR`: CEF's root cache (the profile). Never a Chrome profile
  that a running Chrome uses.
- `--port N`: Chromium's DevTools endpoint on 127.0.0.1 (`/json/version`).
- Any Chromium switch is passed through (`--remote-allow-origins=...`).
- `BACKPLANE_CEF_NO_GPU=1` adds `--disable-gpu`.

## Protocol

stdout: one JSON object a line, each with `t` (wall-clock ms):

| event | fields |
|---|---|
| `init` | `ms` from exec to CEF initialised |
| `ready` | `xid` (the browser's X window), `parent`, `port` |
| `navigated` | `url` (main frame) |
| `load` | `url`, `code` |
| `title` | `title` |
| `popup` | `url`: a `window.open`/`target=_blank`, loaded into this same browser |
| `ok` | `cmd` |
| `error` | `error` |
| `closed` | the browser closed; the host exits |

stdin, one command a line: `url URL`, `place X Y W H`, `show`, `hide`,
`focus 1|0`, `back`, `forward`, `reload`, `quit`. EOF on stdin quits.

## Notes from the spike

- The zygote changes the stack canary in every child it forks
  (`--change-stack-guard-on-fork`), so `main()` is built without a stack
  protector, as Chromium's own entry point is. Without that, children die
  with "stack smashing detected".
- Playwright 1.63's `connectOverCDP` works against the host from Node, but
  not from Bun 1.3: its vendored `ws` client (with its happy-eyeballs agent)
  never completes the upgrade, while Bun's own `WebSocket` does. The helper
  (a Bun binary) needs a small `ws` adapter over Bun's `WebSocket`.
- Over CDP, Playwright's `browser.close()` closes the host's browser. An
  agent must only disconnect.
- `CefBrowserHost::WasHidden` is for off-screen rendering only. Unmapping
  the child does not throttle the page: a hidden animating page still runs
  its `requestAnimationFrame`.

## Bench

`bun tools/cef/bench/bench.ts` compares this host with the Playwright helper
on the same pages at 800x600, on a private Xvfb (its probe `bench/xlat.c`
injects XTest input). See the comment at its top.
