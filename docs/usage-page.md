# Usage page

Open Settings → Usage on the machine you want to inspect. The phone's App
settings also retains a separate Usage section for each paired machine,
including its stable key and connection status. Cached offline readings stay
with that machine.

Choose Tokens, Reported cost or Limits. Today means the current UTC calendar
day; This month means the current UTC calendar month. The page reads existing
`TurnUsage`/`Tok.*` rollups. It requests no transcript import, history replay or
new telemetry collection. Anonymous installation telemetry is unrelated.

Recorded tokens include uncached input, cache read, cache write and output.
Reasoning is included in output and is never added twice. Missing fields are
unknown: a recorded subtotal of zero does not establish that every provider
reported zero. Coverage gives the number of turns that supplied token readings.
Reported cost includes only costs a provider supplied and shows how many turns
reported one. A reported zero stays zero; an absent cost stays unknown. These
are provider API-price figures, not subscription charges. The page introduces
no model price estimates.

Turns without usage events are absent, rather than zero. In the inspected
backend, Claude and Codex produce those events; this page does not add usage
collectors for other providers. The coverage denominator counts recorded usage
turns, not every turn or session the person ran.

The month view has separate provider/model and project breakdowns, each paged
in groups of twelve. They use the month's aggregate index and project catalog,
never thread entries. Today does not claim a daily model/project breakdown:
the current ledger only maintains those dimensions by month. Limits and
context readings retain their existing source and missing-data behavior.

## Reference

The authentic repository is [pingdotgg/t3code](https://github.com/pingdotgg/t3code),
inspected at `5b2ee393c3d6576bcf44c5d2b74565770943e189` on 2026-10-20:

- [User documentation](https://github.com/pingdotgg/t3code/blob/5b2ee393c3d6576bcf44c5d2b74565770943e189/docs/user/usage.md)
- [Usage page](https://github.com/pingdotgg/t3code/blob/5b2ee393c3d6576bcf44c5d2b74565770943e189/apps/web/src/components/usage/UsagePage.tsx)
- [Usage data contract](https://github.com/pingdotgg/t3code/blob/5b2ee393c3d6576bcf44c5d2b74565770943e189/packages/contracts/src/usage.ts)
- [Server aggregation service](https://github.com/pingdotgg/t3code/blob/5b2ee393c3d6576bcf44c5d2b74565770943e189/apps/server/src/usage/UsageService.ts)

T3 Code's useful patterns here are separate metrics, environment selection,
progressive results and honest cost/coverage labels. Backplane retains its
existing Settings navigation and machine isolation. Its available counters do
not justify copying rolling ranges, pricing overrides or historical scans.
