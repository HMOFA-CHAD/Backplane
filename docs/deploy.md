# Safe deploy and restart

A restart is cheap: with `restart.continue` on (the default) the hub resumes
every turn it cut. What a restart must not cut is a **tool call in flight** (a
build, an edit) and a **build under way** (the machine-wide `/tmp/bp-bend.lock`
and `/tmp/bp-wt-build.lock` that `scripts/build-app.sh` holds). A deploy waits
for both, then swaps the new package in and restarts in place.

## Asking

- An agent: the `deploy_restart {stage?, note?}` MCP tool. It answers at once
  ("scheduled") and the agent ends its turn; after the restart it is woken by
  one message, "Backplane restarted for a deploy ...: <from> → <to>."
  `deploy_status` and `deploy_cancel` read and cancel it.
- A client (the person): the requests `deploy.restart {stage?, note?}`,
  `deploy.cancel` and `deploy.status`.
- `scripts/dev.sh install [h@host]`: builds, stages the package and posts
  `deploy_restart` to the running hub's loopback MCP route
  (`POST /mcp/deploy`; "deploy" is no thread, so the person is the requester).
  It prints "deploy queued" and ends. With no hub answering, or with
  `--force`, it installs and restarts now, as before.

`stage` is an absolute folder holding the package (`backplane`,
`backplane-serve`, `web/`, ...). Empty means the files are already in place.

## How it waits

The request is the private setting `deploy.wait`, one JSON line (`by`, `note`,
`stage`, `from`, `since`, `noted`, `locked`, `open`). Each tick, while it waits:

1. The hub's open tool calls, in memory only (core/deploy.bend `Open.*`; the
   server's `Bn.tools`). A call opens where its Act is posted (`ToolOpen`:
   Claude's `tool_use` block, Codex's `item.started`, Grok's/Muse's logged
   call) and shuts at its result (`ToolShut`: the `tool_result` block, Codex's
   `item.completed`, ACP's `tool.done`); a turn's end, an archive, a delete or a
   stopped agent shuts every call of the thread (`ToolsGone`). None of it is in
   the log, and after a restart the list is empty (the old processes are
   gone). A thread between two calls has none open, so a deploy goes then,
   however long its turn. The requester's own `deploy_*` call is never opened;
   a subagent's Agent/Task call stays open until its result. The wait line
   records what was open at the last look (`open`) for the plane row,
   `deploy_status` and the 30-minute note.
2. With none, the server asks the locks (`flock -n` on each path of
   `BACKPLANE_DEPLOY_LOCKS`, colon-separated, default the two build locks;
   without flock(1) they count as free) and answers `Deploy.check`.
3. Clear: `deploy.done` is written (the same line plus the threads cut) and
   `deploy.wait` cleared in one step, then the server moves the staged package
   into the running install's folder as `scripts/dev.sh`'s `install_into` does
   (renames; the old `web/` is kept as `web.old`) and restarts the hub in
   place (the updater's `Upgrade.restart`, same PID). A failed swap clears
   `deploy.done` and tells the requester; nothing restarts.
4. After 30 minutes the requester is told once what still blocks.

The Status plane shows a "Restart pending" row in Running while one waits
("waiting for 2 tool calls and the build lock · Cancel"; a click cancels:
action `deploy-cancel`), and Settings' update line says the same.

## After

At start `Deploy.after` reads `deploy.done`: it clears it and tells the
requester once. A thread the restart cut gets the words appended to its
continue message instead (`Deploy.suffix` in `Carry.k`), so no thread gets two.

Laws `deploy_*`, `tool_*`; tests `test/deploy_test.bend`, `bun test/tools/deploy_e2e.ts`.
