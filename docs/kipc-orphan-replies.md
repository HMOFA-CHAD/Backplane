# IPC worker reply lifetime

Closing an IPC socket used to terminate its worker and remove its slot while
leaving every pending Promise unresolved. An unexpected worker error or exit
also had no pending-reply completion handler. The helper stayed alive, so the
hub's helper-exit handler could not answer those requests either.

`tools/kipc/src/replies.ts` now owns each worker's pending replies. Connection
close, worker error and worker exit complete that connection's pending requests
with errors, once. Late replies cannot complete a replacement worker's requests;
unrelated workers retain their requests. Enqueue failure affects only the
request that failed to enqueue. A transport failure reports that the operation's
outcome is unknown: it does not claim a successful edit or rollback.

The ordinary response path remains:

1. The helper's `handle` writes `{id, ok:false, error}` for the original request.
2. `KServe.reply` / `Browser.deliver` match that helper id to its reply channel.
3. `KIpc.run` / `KIpc.fin.k` / `KIpc.fail` produce the original MCP request's
   error result on its reply channel.
4. `Mcp.ask.raw` receives it, attempts `Mcp.answer` / `Conn.finish`, and only then
   posts `McpShut` for that transport call. A disconnected peer receives no
   success, and a failed send still returns through the normal close path.

The focused test uses both deterministic workers and real disposable Bun
workers. It covers two orphan waits versus a separate live request, actual
worker exit/error, replacement isolation, duplicate/late replies and enqueue
failure. Run `bun test tools/kipc/test/replies.test.ts`; no KiCad or hub is started.

This is a source-only correction. It has not replaced the running helper, hub,
queued package or binaries. The two historical client timeouts identify an
orphaned wait, but do not prove that this particular worker-close path caused
them. An MCP client timeout alone is not evidence that KiCad stopped working.

The current MCP dispatcher has no `notifications/cancelled` handler that reaches
an existing request's reply channel. Thread/task cancellation leaves transport
slots open intentionally. `kicad.retry` resets failed server records; it neither
answers pending requests nor completes their transport. There is no supported
live request-completion endpoint in this version. This correction adds no raw
slot deletion, global timeout, server signal, runtime-state edit or forced
restart. It cannot retroactively resolve already-orphaned Promises in the
running helper.
