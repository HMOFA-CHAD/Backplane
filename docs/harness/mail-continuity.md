# Mailroom completion and failed tools

An actionable message can be durably filed and delivered to a conversation's
short-lived Mailroom run while its owning front-of-house bot remains idle.
That is intentional routing, but delivery alone is not a disposition.

Observed on 2026-10-20: provider-side approval controls rejected `decide`,
`escalate`, and `mail` before the requests reached Backplane. Runs then returned
successful final responses saying that nothing was recorded or sent. Because
those runs are hidden and their responses were not reported to their owner,
requests for source decisions remained unattended for hours.

`Run.after` now examines completed/failed Mailroom runs before ordinary
wake/ride processing. A committed reply in the same conversation, explicit
Done/Snooze, or successful escalation of the current actionable input suppresses
the fallback. Reading/Open, a decision log by itself, an uncommitted mail append,
or a reply in another conversation does not. Header order distinguishes
same-second requests, including room requests.

Otherwise the hub commits the input identity and an internal report directly
to the run's own front-of-house bot, including its final response as context.
This follows the existing escalation delivery path rather than the inbound
mail funnel, so it cannot spawn another hidden Mailroom run. An already-running
owner receives it through the durable ride; an idle owner starts a turn.
The input remains unresolved. No rejected action is executed or retried, and
no provider approval, sandbox, charter, or notification preference is relaxed.

An interrupted process on hub recovery also reports unresolved work when
restart continuation is enabled. Adopted runs, explicit stops, disabled
continuation and mail-off behavior are respected. The forwarding token prevents
replays from creating duplicate reports.

Validation:

- `bend test/mailcontinuity_test.bend`: actual core routing, committed reply
  headers, escalation, replay, read/deferral, restart and notification guards.
- `bend test/mailrun_test.bend` and `bend test/mailrun_model_test.bend`.
- `bend PROOF.bend`: additive policy laws; existing laws remain intact.
- `bun test/tools/mailrun_e2e.ts APP WIRE`: successful tool-mediated escalation.
- `MAILRUN_FALLBACK_E2E=1 bun test/tools/mailrun_e2e.ts APP WIRE`: a deterministic
  agent stand-in models tool rejection before MCP and requires a single durable
  owner report after final completion. This tests harness behavior, not an
  actual provider approval service. Both require a native app built from this
  exact change; passing pure tests does not establish native acceptance.

The all-bots `mail_list(bot="*")` status scope is not the owning bot's unread
queue. Audit an individual bot by its id; neither unread count nor seen status
proves that a request was answered.

## Routine notices and provider approval

`mail_dispose` is a separate bounded write tool, advertised only to a live
Mailroom run. Its authenticated endpoint fixes the run and conversation. Every
call must name the exact current actionable input printed in the brief or
incoming mail heading. A stale input, non-run, completed run, additional target
or action fields, and mail-off calls are rejected without effects.

`done` and `defer` write an audited receipt for that notice only. They do not
complete an objective, mark the conversation Done, change a permission, or
start work. Use them for an already-treated duplicate or an unchanged known
hold, explaining why no new action is needed. A new input remains independently
actionable; reading, delivery and final response text still do not settle it.

`reply` files an internal FYI in that conversation to the current input's
existing local thread/bot sender. It cannot choose an arbitrary recipient or
start a recipient agent. The receipt commits with the real body/header append,
not the tool response. Pending/unknown append outcomes are not resent, and
failed commits retain the actionable fallback. Correlated reply headers name
the input so a late old reply cannot settle a newer request. Rooms, remote and
external recipients continue through the existing reviewed tools.

For Codex live Mailroom launches only, the launch configuration grants just
`mcp_servers.backplane.tools.mail_dispose.approval_mode="approve"`. Ordinary
launches get no added option. The existing sandbox, generation check, standing
rules, charter, generic tools and external/privileged review remain unchanged.
No write is advertised as read-only. Source checks alone do not qualify actual
provider approval behavior; isolated CLI/MCP execution is required before
integration. No live provider configuration is changed by this source patch.
