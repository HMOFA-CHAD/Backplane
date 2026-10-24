# Acknowledged sidebar transport

Web view requests opt into `sidebarRegion: {version: 1, token: ""}`. A full
response seeds one immutable sidebar with a public token equal to its positive
request revision. The next request can acknowledge that token. Only the same
surviving actor, with the exact private sidebar dependency key still equal, may
send an empty `bp-sidebar-ref` node instead of that sidebar. The key itself,
drafts, history and canonical data are never used as public tokens or logged.

The private key still includes canonical sequence, clock, target/view/epoch,
actual recipient info/live state and sidebar-sensitive transient inputs. This
change does not broaden the existing Settings render-cache eligibility. A
changed key, missing/wrong acknowledgement or fresh connection sends a full
seed. Old clients and mobile clients receive the original complete response.
Full render and stream-splice memos stay complete; transport runs afterward.

The client restores the exact acknowledged node before presentation validation,
logical size checks, decoding, commands and DOM patching. A reference must be
unique, empty and in the sidebar slot. Unacknowledged or malformed references
fail closed without effects or automatic retry. Every pending call retains its
own base; stale replies cannot install a cache or display. Selection/reconnect
clears the link cache. At most the existing eight pending calls plus one link
retain bases, bounded by the existing logical response limit; nothing persists.

Main content, session, message window, commands, target and revision fences are
unchanged. No new read queue, scheduling delay, thread or CPU worker is added.
This reduces repeated encoding/transfer/decoding only on genuine exact-key
hits. Full render, full first load, invalidations and receiver validation remain
costs. Controlled measurements distinguish those costs from live latency.
