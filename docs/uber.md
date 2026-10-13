# The uberbot

One bot the person makes their main interface across all projects, machines and bots. Nothing promotes a bot by itself.

Built now (increment 1a, core only; the clients' screens come next):
- `UberSet{bot, uid, at}` (model.bend, codec.bend) folds as the settings `uber.bot` (its bot id here; "" for none) and `uber.uid` (its id across machines). It is not shared with other machines yet (far.bend leaves it out).
- `src/core/uber.bend`: `Uber.bot(st)` (the uberbot's id; "" when its bot is gone or is a mirror from another machine), `Uber.is`, `Uber.uid(now, seed)`, `Uber.promote(st, bot, uid, now)` (a `Promo`: an error text, or the changes to log; "" demotes). Only a live bot of this machine can be promoted. Laws `uber_*`.
- RPC `bots.uber {bot}`. A demotion is logged at once. A promotion first runs a server job (`BotFx "uber"`, `BotJob.uber`) that backs the bot up under `<home>/backups/uber-<now>-<bot>`: its home folder (`home/`) and the log lines that name the bot or its thread (`events.jsonl`). The log itself is never rewritten. Only when that worked does the server log `UberSet` with a fresh uid; otherwise it answers an error and logs nothing.
- The uberbot's turn prompt says so (bothub.bend's `Bots.prompt.uber`).
- Client state (client.bend, botui.bend): the uberbot is not in the bot list (`BU.rows`); `BU.uber(u)` is its row. Its tabs start with `status` (`BU.tabs.for`, `BU.tab.dflt`). Actions `uber` (select it on Status), `uber-promote <bot>`, `uber-demote`, `uber-bot <bot>|<tab>` (a bot with a tab, for a routine's row); a bot's menu (`bot-menu <id>`, kept as `b:<id>`) offers "Make uberbot" / "Not uberbot".
- Rooms seen: the setting `room.seen.<room>` (seconds). `Rooms.unread(u, room)` counts the posts after it that the person did not write; opening a room with some unread sends `setting.set` of it to now, one with none sends nothing.
- The status plane, `src/core/plane.bend`: `Plane.of(u, now)` is what the Status tab draws, for every client: need (approval, question, failed; most urgent first), run (working, queued), bots, rooms with unread, routines (running first, then the soonest due), the rest of the day's live threads (at most 50, `idle_n` the whole count), and the machines. Threads and bots on the owner's other machines are in the client's state as `<link>~<id>` and are included; a machine that does not answer shows its rows as away and asks for nothing. `Plane.key(u, now)` is cheap and changes whenever the plane can (the log's sequence, each machine's head and whether it answers, the minute), so a client builds the plane only when it changes; `Plane.counts(p)` is the sidebar row's "3 need you · 7 running". Laws `plane_*`.

Next (not built):
- The window, web and phones draw the Status tab and the sidebar row; right-click and long-press open the bot menu.
- Sync between a person's machines for the uberbot: an op log with hybrid logical stamps and version vectors, last-writer-wins per key with forget tombstones, so the same uberbot (its `uid`) has one memory on every machine.
- The conversation lease: one machine at a time holds the uberbot's conversation, with a term number and a 10 minute grace before another may take it.
- Routines: an unpinned routine runs at least once (a duplicate across machines is detected and logged); a routine pinned to a machine runs at most once.
