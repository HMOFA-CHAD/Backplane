# Settings

The web and desktop Settings menu groups the existing fourteen pages under
Your workspace, Agents, Hardware, and Machine & data. Each category has a
fixed icon slot, its existing localized title, a short description, and a
chevron. The menu uses two columns on wider screens and one on small screens.
Category buttons have explicit accessible names and descriptions. English
and Japanese menus retain the same page IDs, settings controls and actions.
Search still filters the existing title/keyword/row index; Enter opens its
first result. Subpages show their category icon and description above the
existing controls. This change does not alter settings values or defaults.

The occasional second click had a reproducible transport cause: a background
`view.update` or `view.changed` could issue a newer presentation revision while
Settings was opening or a same-target `settings-page` action was in flight.
That retired the navigation response's display authority. ThinHost now defers
those refreshes until the Settings action settles, then refreshes with the
accepted session. Existing upload deferral is preserved. Transport identity,
privacy filtering, selection changes and other action behavior are unchanged.

Focused evidence: `desktop/test/thin-host.test.cjs` includes failing-before,
passing-after cases for both Settings open and submenu navigation raced by a
background refresh. `test/tools/settings_review.mjs` runs the emitted production
`settings_fixture.bend` in an isolated browser: fourteen categories, icons,
search/Enter, Japanese labels and a 390 px layout. It does not write live
settings or claim live hub/device validation. Native phone UI was not changed.

## Show thinking

Settings → Agents → Show thinking (`agent.thinking`, off until turned on)
asks agents for their thinking and shows it in the thread, folded under
"Thinking" and its first line. Claude is started with
`--thinking-display summarized` (without it its thinking blocks come with
no text); turning the setting either way restarts a thread's Claude
process at its next turn (the setting is part of `Agent.key`). Codex runs
with `model_reasoning_summary="detailed"` and its `reasoning` items are
kept. Pi's `thinking_end` carries a whole thought. Each finished thought is
an `ActivityLogged` of tone `thinking`, logged only while the setting is on;
turning it off hides the ones already logged (web and phones). Thoughts
arrive whole, after the model finishes thinking, not streamed. The ACP
agents (OpenCode, Grok, Oh My Pi, Antigravity) send thinking as chunks that
are not collected yet, and Muse's reasoning is not read.
