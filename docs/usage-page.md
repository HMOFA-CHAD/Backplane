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

The Tokens view has provider tabs, limited to providers advertised as available
in this machine's `models` capability arrays (the same source as the fallback
picker). There is no separate provider enable switch. A saved selection falls
back to the first available provider if availability changes. Tabs support
Left/Right, Home/End and normal Tab/Enter operation. No provider is inferred
from a model name. Cached availability can be stale when disconnected.

Each tab plots recorded tokens by UTC day for the selected period. This month
runs from the first of the month through today; Today is one day. Solid bars
show recorded token subtotals, a baseline marks a reported zero, and hatched
columns mean no token reading. Expand Daily readings for exact values and
coverage. The native phone pages use the same readings, with dim missing-day
columns and an expandable list. Plot height is reserved before painting.

Daily provider/project dimensions are additive rollups from accepted
`TurnUsage` events: `tok.<epoch>.dv.<YYYY-MM-DD>|<provider>` and
`tok.<epoch>.dp.<YYYY-MM-DD>|<project>`. They use the same token components and
coverage counters as existing totals. `daily.since` marks the start of these
readings in the active counting epoch. Existing persisted monthly totals are
never divided into daily guesses. Earlier days, providers without usage
collectors, and turns without readings remain unknown. The first counted day
may be partial. No history import or new network endpoint is added.

Below the graph, Top 5 projects ranks positive recorded token subtotals across
all models and providers, independently of the selected provider tab. This
month uses the existing `p.<project>|<YYYY-MM>` totals; Today uses the new daily
project totals and shares their coverage limitation. Each project aggregate is
read once; model totals and reasoning are not added again. Equal titles remain
separate project IDs. Missing catalog entries retain their ID as Unavailable
project; an empty project identity is Unknown project. Unknown readings and
zero-token projects do not fill ranking slots. Fewer than five projects are
shown when fewer have positive recorded consumption.

The existing month view's provider/model and project details remain paged in
groups of twelve below these views. Today does not claim a daily model
breakdown. Limits, reported cost and context retain their existing source and
missing-data behavior. No model pricing or cost-to-token conversion is used.

Focused validation: `test/usage_graph_test.bend` with
`test/tools/usage_graph.mjs` exercises the production rollups, provider actions,
UTC boundaries, cross-model rankings, unavailable/unknown projects, reset
isolation, legacy missing dimensions, web nodes. `usage_graph_mobile_test.bend` and its driver cover phone chart payload and machine-scoped provider actions; native application builds are separate targets. Review
renders use explicit deterministic TurnUsage fixtures, never claimed as live
account readings.

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
