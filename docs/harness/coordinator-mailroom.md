# Coordinator mailroom

The promoted uberbot is the person's conversational interface. Workers and
bots keep their own source timelines and rooms. Their reports enter internal
mail; they do not appear as incoming worker messages in the coordinator's chat.

A committed report, including FYI, starts or joins the owning conversation's
private triage run. This also works when generic `mail.on` automation is off.
Room reports file once, then route to their member bots; the coordinator's
member wake goes through triage. Direct reports, launched-thread subscriptions,
task results, bot results, and explicit wakes share this path. Source work is
never started, stopped, archived or approved merely by acknowledging mail.

The run uses the owner's memory identity and project/room scope, with a private
system prompt that does not inherit the owner's front-of-house persona.
The brief includes relevant durable memory, recent messages from the original
conversation, task board, live asks, decisions and source links. The read-only
`mail_context` tool searches/pages the owner's full stored conversation, even
beyond that brief. Its owner is derived from the authenticated live run;
caller-supplied target fields are rejected. It returns explicit errors for an
unavailable store. `memory_recall`/`memory_list` retain the owner's identity.

Triage chooses a durable notice receipt, authorized coordination in source
threads/rooms, or escalation. Meaningful completions, blockers, decisions,
actual approvals and uncertain outcomes require attention. FYI, unchanged holds
and duplicates stay quiet. Inputs are processed oldest first, including equal
timestamps: a newer FYI cannot hide an older ask. `mail_dispose` requires the
exact input and returns `next_input`; it records only that notice. On successful
completion with all inputs handled, the hub marks the quiet conversation done.
An actual open source approval cannot be disposed as a routine notice. Decisions
and receipts never supply permission, answer an approval or complete source work.

`escalate` requires the exact input in coordinator runs. Both `bot` and `person`
destinations privately queue an assessment to the owner's original conversation.
This uses the durable ride and adds no raw message or source alert to that chat.
Bub must write a fresh contextual answer with actionable source links. Original
asks remain at their sources for the person to answer. Source alerts from
managed workers/private runs/other bots are suppressed; browsing their timelines
and approval cards remains available.

The model inherits the app's existing text-generation provider/model settings,
so the person can use a cheaper configured model. Optional advanced per-bot
settings `run.provider.<bot>` and `run.model.<bot>` override it; known mismatched
model families are rejected in favor of the selected provider's configured
choice/default. Existing ordinary-bot model policy is unchanged. Starts use the
normal global fallback chain and provider checks. Failed, denied or unknown
triage forwards every still-pending input privately to its owner, with explicit
uncertainty, rather than claiming success. Exhausted provider fallback follows
the same path. A missing triggering body fails the run explicitly. A failed
mail-journal append reports delivery failure through the independent private
ride, without committing a header or producer acknowledgement; an event-log
write failure uses the existing visible service write-failure banner. Durable
assessment context also remains in the owner’s next system prompt if its
previous delivery turn failed. This does not relax any provider approval, sandbox or charter.

Delivery is recorded per owner/input. An optional escalation `key` correlates
the same exact event/version across direct, room and launch reports; a changed
result requires a new key. This records queued delivery, not that the person was
already told. Bub consults `told_check` and records `told_mark` after writing the
actual user update. There is no parallel FYI digest producer. Identical wake
subscriptions reuse their id, and launched report subscriptions cover additional
wake requests for the same source. Legacy duplicate launch/wake subscriptions
are consumed without producing a second report. Explicit wakes never bypass
triage. Receipts and delivery markers survive replay/restart; adopted runs and
explicit disabled restart continuation retain their existing behavior.

Validation belongs to the shared integration batch:

- `bend test/mailtriage_test.bend`: routing, scope, quiet receipts, asks, private
  escalation, event keys, read/done, model configuration, rooms, bot reports,
  duplicate subscriptions, failure, replay, restart and adopted runs.
- `bend test/mailtriage_policy_proof.bend`: bounded checks of the two additive
  universal laws; full `bend PROOF.bend` remains the integration gate.
- Existing `mailrun`, `mailrun_model`, `maildisposition`, `mailcontinuity` and
  `oprep` regression tests.
- `bun test/tools/mailtriage_e2e.ts APP WIRE_DIR`: isolated compiled hub and
  authenticated agent MCP, deterministic provider stand-ins, real store reads,
  original-conversation authoring, source approvals and restart. No live user
  state, credentials, external mail, network services or hardware are used.

A source patch or pure test pass does not establish runtime acceptance or live
activation. Run the runtime test on the exact combined build before local handoff.
