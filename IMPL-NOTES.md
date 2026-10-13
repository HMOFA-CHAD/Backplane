# ios-snappy increment 4A: lost work ends

## What changed (src/core/hub.bend)
- `Bg.gone`: an agent's exit tells (as before, `Bg.lost` "exit") and then always clears the thread's bg rows (`Bg.clear`), whatever `restart.continue` says. Delegated children (`Work.kids`) and watched work (`watch.<th>`) are not touched.
- `Lost.key/stash/of/aside/unstash`: work lost at a restart is put aside in a setting `lostbg.<thread>` (rows as `Bg.show` writes them) and the thread's own `bg` rows are emptied in the same step (`Rec.lost.on`, `Rec.lost.again`). `Bg.lost` and the restart counting read `Lost.of` (stash + current rows), so what the agent is told (`Lost.text`) is exactly what it was, and the stash is emptied when it is told. `settings` are generic events: nothing new to decode.
- `Rec.lost.old`: at `Hub.recover` rows an earlier restart left ended with outcome "unknown" (already told, `Lost.new` skips them) are cleared. These were all of the island's ghosts in the real log.

## Choices
- Rows are removed from the thread's rows, not just marked ended: `Bg.live` (and so `Work.busy`, `island_busy_shows`, `work_busy_counts_ended_rows`) counts ended rows by design, and those laws must not change.
- `restart.continue` off at recover: unchanged (law `lost_off_logs_and_keeps`: the rows stay, ended "unknown", until a turn or the next recover/exit ends them). They are open-state "ended", not at work (`Bg.running` is 0). The next recover removes them (`Rec.lost.old`).
- `Rec.lost.again` (second restart before the telling): used to mark rows unknown; now logs and clears them (the text is the same).
- After an exit with `restart.continue` on, the told agent is started again (existing behaviour, law gone_idle_told), so the island shows that thread as "Working", not "waiting on N".
- #86 (safe deploy) restarts the hub; the next start runs the same `Hub.recover`/`Hub.carry`, so a safe restart ends lost work the same way. Nothing in deploy code needed changing.

## Watched work (item 3)
`Watch.rearm` is pure and cannot tell whether a process lives, but the server's watcher (`Watch.job`/`Watch.loop`/`Watch.check.sh`) already re-attaches: `run` work is checked by its `pid` file (kill -0), its `code` file, and `pid` work by boot id + start time (`pidid`); a process that is gone with no `code` reads "gone" at the first check (<= 2 s) and `Watch.end` drops the row and tells the agent "it ended, outcome unknown". Live work (a `setsid` run that survived the restart) keeps being watched. So dead watches never linger beyond a couple of seconds; I made no change (a "lost in a restart" wording would change what the agent is told). The real log has no `watch` rows left. `file` watches have no process and wait for their deadline.

## Not done / caveats
- The harness-coord `pgrep` pattern matches many unrelated command lines (including notifier text), so I could not use it as a gate; all heavy runs went through `flock /tmp/bp-bend.lock` and queued behind harness-coord's.
- A rebase with a `merge.union.driver` of `true` silently dropped my LAWS/PROOF blocks once; restored and re-committed.
