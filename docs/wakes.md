Wake subscriptions let a thread finish its turn and receive a new message when
something happens. They also work for a bot's thread, which has no project.

Use `wake_on {kind, target, events?, once?, note?}`. It returns the subscription
id and its record. `wake_list {}` lists your active subscriptions;
`wake_cancel {id}` cancels one you own. Subscriptions survive hub restarts.

| Kind | Target | Events | Default |
| --- | --- | --- | --- |
| thread | Local thread id | end, done, fail, ask, idle | end |
| work | A work_run/work_watch id on this hub | end | end |
| pr | owner/repo#N, or #N in a project | merged, closed, ci, ci_fail | merged, closed |
| file | Absolute path | exists, changed | changed |

A subscription drops after its first message unless `once:false`. The message
starts `Wake <id>:`, lists every matching event from the same step, includes the
note, and explains cancellation for recurring subscriptions. Thread messages
include the last reply, capped at 1500 characters. A busy recipient gets the
message in its queue through the same delivery path as launcher reports.

Thread `end` includes completion, failure and interruption. `done` is completion;
`fail` includes a failed turn or an unexpected process exit.
`ask` arrives when an ask opens. `idle` requires a turn end, no busy work and
nothing queued. Watching yourself is refused. Watching a thread on another
machine is currently refused explicitly.

PR and file subscriptions poll on the existing minute tick. PRs share one query
per distinct target, with account selection through GhRun and bounded commands.
CI fires once all checks finish; ci_fail can arrive while other checks still run.
The PR message includes its title, state, merge commit, CI summary and up to 30
file names. A merge is not reported again when CI subsequently changes.

A file's baseline is captured before the MCP subscription is acknowledged.
Changes compare mtime and size to that baseline. `exists` may fire immediately
for a path already present. A recurring subscription suppresses identical poll
results. Deleting the subscriber persists WakeDropped events and removes its
indexes. Pending jobs cannot revive cancelled subscriptions.

All four clients use Subs.wakes rows in the Subagents panel. Each says
“waiting on”, names its kind and target, shows its events and note, and has
Cancel. The panel counts these as waiting separately from work in progress.

For throwaway tests only, `BACKPLANE_WAKE_TICK_MS` changes the existing tick
interval (default 60000 ms; zero or invalid values use that default); it affects
the other minute-tick tasks too.
`test/tools/wake_e2e.ts` retains the background-work wake checks and then runs
`wake_subscription_e2e.ts` against a separate throwaway hub and stand-in Claude.
