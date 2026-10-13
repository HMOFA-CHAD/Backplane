# ios-snappy increment 3 (implementer A): tabs and on-device settings

Branch `snappy/3a`. Spec: `bp-coord/ios-snappy/spec-3.md`.

## What changed

Bend (`src/mobile/`)
- `tabs.bend` (new): `MTab.json(u, ix, rows)` is one hub's `tabs` object: `home.badge` (need-you count, `Plane.tally`, the sidebar's own tally; no plane is built), `bots.badge` (rooms with unread, `Rooms.unread`), `routines.{badge, rows}` (every bot's routine as a row: title, sub = schedule, `at` = next due, `ago` = last run, bot name, machine, `nav`/`act`/`value` that open the bot's Routines tab).
- `hubs.bend`: `Hubs.tabs.put` adds each hub's tabs in `Hubs.shown.r`; `Hubs.tabs` merges them (badges add up, routine rows qualified by hub, de-duplicated like the plane's, soonest due first). `Hubs.local(hs, key, value)` writes the scratch `@local.<key>` on every hub. New routed action `hub-settings` (value `<hub>|on` / `<hub>|off`): brings that hub into focus and opens/shuts its Settings only if not already so (`One.hubset`). `Hubs.moves()` 11→12, `Hubs.routes()` 29→30.
- `screen.bend`: `Mob.view(u)` = `@local.view` when it is `projects`/`active`, else the hub's `sidebar.view`; used for the `view` field and the active/projects choice (`Mob.screen.ixr`). `Mob.set.row.l` marks a settings row `local: true` (Theme, Thread list, Tour). No other field of `Mob.screen.go` changed.
- `app.bend`/`bridge.js`: `Backplane.local(key, value)` → `App.local` → `Hubs.local`.
- Laws `local_view_*`, `hub_settings_moves_focus` (LAWS.bend/PROOF.bend under `# ios-snappy: tabs`). Test `test/mtabs_test.bend`.

iOS (`mobile/ios/Backplane`)
- `AppSettings.swift` (new): `AppTab`, `AppSettings` (UserDefaults: appearance, thread list, default tab, haptics, `app.migrated.v1`), `Haptics`.
- `Tabs.swift` (new): `AppTabs` (TabView, `.sidebarAdaptable` on iOS 18+, badges), Bots page (Bots | Rooms segment), Routines page, `AppSettingsTab`, `HubSettingsPage`.
- `AppModel.swift`: `stacks[tab]` (one `NavigationStack` path per tab; `path` is the visible tab's), `tab`, `switchTab` (re-selects the new stack's top through `select`, with `awaitedNav`/`shownSel` set so the cached page shows at once and in-flight screens for the old selection are ignored; an empty stack selects nothing and clears nobody's stack), routing of a selection that arrives from elsewhere (`destination(screen, nav)`: the screen's `bot` → Bots, the uber card's `sel` → Home, else Threads; a tapped row opens in its tab: `destination(kind:action:)`), first-screen migration and default tab, hub-settings cache on disk (`hub-settings.json` beside the kept state), cache size/clear, `Backplane.local` calls after start, load, hubs and on every change.
- Views: `ProjectsView` is now only the Threads tab (search, projects/active, add project); `UberCardRow`/`PlaneSections` moved to `HomeTab` (Plane.swift); `BotsSection` removed; `SettingsSheet` replaced by `HubSettingsRows` (skips `local` rows). `BackplaneApp` reads `AppSettings.colorScheme`, never `screen.theme`.

Android (`mobile/android/.../mobile`)
- `AppSettings.kt`, `Tabs.kt` (new), `Core.kt` (tab state, routing, migration, local view, hub-settings cache, cache clear), `Screen.kt` (`Tabs`, `RoutineRow`, `SetRow.local`, `parseSettings`/`settingsJson`), `Engine.kt` (`local`), `StateStore.kt`, `Ui.kt` (`Projects` is the Threads tab; `Tabs` replaces the root list), `Plane.kt` (`HomeTab`), `ThreadParts.kt` (`hubSettingsRows`), `MainActivity.kt` (theme from `AppSettings`).

## Choices where the spec left room
- **No uberbot, Home**: the `ContentUnavailableView` alternative (offers `uber-new`), not need/run rows built from threads.
- **Board segment in Routines**: not built (no `board` in the screen yet).
- **Routines badge**: always 0 (spec: optional).
- **Bots badge on Rooms rows**: the badge counts rooms with unread; the Rooms segment does not mark them (`RoomRow` carries no unread count; Bend's `MBots.rooms` was left alone).
- **Plane while another tab's page is selected**: Bend builds the plane only with nothing selected. Home keeps showing the last plane (`lastPlane`) and re-selects nothing (empty Home stack) when it comes up, which makes Bend build a fresh one.
- **From Home, a tapped row** goes to the destination tab (thread → Threads, bot/room/routine → Bots, the uberbot's own card stays on Home), per the deep-link rule; from any other tab a tap pushes in that tab (so a routine row in Routines opens its bot inside Routines).
- **Island picker** is shown from Home (iOS switches to Home first).
- **Hub settings with several hubs**: one row per hub; the row's page sends `hub-settings <hub>|on`, which brings that hub into focus (Bend has one `settings` flag, on the focused hub), and `|off` on leaving.
- **Android navigation** is state-driven, not a nav stack (a page is the whole screen over the list): the bar shows at list level, a page opens over it from its tab and Back returns to that tab; each tab keeps its own `LazyListState`. A wide screen (≥ 840 dp) gets a `NavigationRail`.
- **harness-coord guard**: `pgrep -f "harness-coord|hc/"` matches unrelated processes (a `notify-send` carrying a harness-coord message, the shell itself). I used `/tmp/a3-guard.sh` (the same pattern minus those lines); nothing real was running when I started heavy work.
- The first-run tour: the tour sheet logic is unchanged (waits for no other presented controller; Bend withholds the step while Settings is open).
- No migration write-back: the hub's `ui.theme` and `sidebar.view` are read once and never written; `screen.theme` stays in the screen only for that.

## Settings audit (everything the phones read or write)
| Setting | Where it lived | Now |
|---|---|---|
| `ui.theme` (hub setting) | hub Settings row Theme; `BackplaneApp` read `screen.theme` | Device: Appearance (System/Light/Dark). Hub row marked `local`, hidden on the hub page. Migrated once. |
| `sidebar.view` (hub setting) | hub Settings row Thread list; shared across hubs | Device: Thread list, sent as `Backplane.local("view")`. Row marked `local`. Migrated once. The hub's setting is still the fallback when none is chosen, and other clients keep using it. |
| Tour | hub Settings row (`ob-open`) | Device: "Show the tour" in App settings; row marked `local`. |
| Haptics (long press on rows/projects, board note, pairing) | always on | Device: Haptics toggle |
| Notifications permission | asked once at pairing | Device: row with the system state and a button to the system page. What alerts the hub sends stays a hub row (`notify.*`). |
| Paired hubs (`links`) | toolbar link button → HubsView | Device: Hubs row in Settings (toolbar button kept) |
| Kept state | invisible | Device: Cache size and "Clear cached state" |
| Default tab | n/a | Device: new |
| About (version, build) | hub row "Backplane <hub version>" is the hub's | Device: app version and build; the hub's version row stays on the hub page |
| `agent.provider`, `agent.model`, `settle.days`, `restart.continue`, `kicad.ipc`, KiCad/FreeCAD/Tailscale lines, machines (`sync.*`), pairing QR, `update.channel`, API keys, Antigravity, notif-policy / routines-cal / gmail rows | hub Settings | Hub: unchanged, on the lazy Hub settings page |
| `drafts`, `cid`, `asked-notify` | app internals | unchanged (not user-facing) |

## Results
(filled in at the end)
