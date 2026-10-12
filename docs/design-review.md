# Design review (AllSpice, locally)

AllSpice is "GitHub for hardware". This page lists its features, marks which
ones Backplane can run locally, and gives the plan for building the missing
ones. KiCad comes first. Other CAD tools plug in through `src/core/cad.bend`.

Sources: allspice.io/product, allspice.io/features, learn.allspice.io (index
`llms.txt`: Design Reviews, Create a Release, Automations, file formats,
comment → issue, checklists).

## Inventory

| AllSpice feature | Status | Backplane today / what to build |
|---|---|---|
| Visual PCB diff, colour-coded added/removed/changed, object level | have | `Hist.mark` (hist.bend): layers 26-28 in red, amber and green, the rest dimmed; `Pv.child.diff` |
| Visual schematic diff | have, one sheet at a time | Same path. Missing: whole hierarchy with changes per sheet, and moving through sheets while comparing (`Hist.rebase` drops a comparison to the live file) |
| Diff any two commits or branches ("arbitrary commits without a review") | partial | The compare menu offers only the 40 newest branches and commits, HEAD, turns and steps. Missing: tags, any ref or SHA typed in, `a..b` vs `a...b` (base of the merge) |
| Per-layer diff | missing | Marks collapse onto layers 26-28 and lose their source layer. Build: keep the source layer so layer flips and focus filter marks |
| Side by side | missing | Build an Old / Diff / New flip on all four clients (same scene, so it costs nothing). True two-pane view: later, web first |
| Design review = PR with a hardware view | have | `Git.act` commit, push, create_pr; `gh` accounts (gh.bend); thread worktrees |
| Comments pinned to a sheet or layer location | missing | Build: `src/core/review.bend`, anchors (file, commit, sheet, layer, x/y in mm), stored in the event log, pins in every viewer, MCP tools for agents |
| Version-linked comments | missing | An anchor names its commit. On a later version, a pin shows "moved" when its item changed (by `Hist.mark` key) |
| Comment → issue | missing (GitHub) | Comment menu: Open issue (`gh issue create`, from the person's click) |
| Approvals / sign-off | partial | PR merge exists. Build: checklist sign-off per review (below) |
| Review checklists and templates | missing | Build: `.backplane/checklist.md` in the repo (a markdown task list), ticked per PR or commit, results in the report |
| BOM generation | missing | Build: `src/core/bom.bend` reads symbols from `.kicad_sch` (Reference, Value, Footprint, MPN, Manufacturer, DNP, in BOM), groups them, writes CSV; `kicad-cli sch export bom` for releases |
| BOM diff, parts-change summary | missing | Build: BOM diff between any two versions as a markdown table; appended to PR bodies `Git.act` creates |
| BOM checks (missing footprint, duplicate refdes, bad or missing MPN, ratings) | missing | Build: rules in `checks.bend`. Rating mismatch needs part data: KiStack bom skill, agent-side |
| Automations (Actions): deterministic checks, triggers, jobs | missing | Build: "design checks" (ERC, DRC, BOM rules, checklist, and custom scripts from `.backplane/checks.json`) on a commit, PR or working copy, run in a detached worktree; triggers: on demand, before PR creation, at tag (release gate) |
| Release management, tag + attached outputs | missing | Build: tag, then from a clean worktree of the tag: Gerbers, drill, CPL, BOM CSV, schematic and board PDFs, STEP, optional IPC-2581/ODB++. Stored in `<repo>/.backplane/releases/<tag>/`, and as `gh release` assets when the remote is GitHub (the person's click publishes) |
| Release gating | missing | A release refuses while checks fail, unless forced |
| Milestones, issues | cloud (GitHub's) | Skip. `gh` covers it |
| DRCY AI review, grounded Q&A, connections checker | have (agents) | Claude, Codex, Grok and Muse with KiStack skills. Build: the agent sees open comments and check results, and can comment and run checks through MCP |
| Full revision search, traceability | partial | Steps and turns and `git log`. Skip anything beyond that for now |
| Headless API/MCP/SDK, CI/CD | partial | Agents' MCP plus `/debug`. New MCP tools above |
| Altium / OrCAD / Allegro / Xpedition parsing | later | Integration layer only: `cad.bend` adapters (detect, roles, check and output commands). Proprietary formats need parsers or exporters we lack |
| Library management | skip | Out of scope |
| Hosted repos, mirroring, SSO, MFA, SOC 2, GovCloud, billing, teams, Slack | cloud-only | Skip |

## Integration layer

`src/core/cad.bend`, pure data. Each `Cad.Tool` has:
- a name;
- its file extensions, each with a role (board, schematic, project, symbol library);
- its checks (an argv template, the report format, a parser id);
- its outputs (an argv template, an output folder);
- whether the viewer can draw its files.

KiCad is the first adapter, built over `kicad-cli` 10 (`sch erc`, `pcb drc` with `--format json`, `sch export bom|pdf|netlist`, `pcb export gerbers|drill|pos|pdf|step|ipc2581|odb`). The server runs the templates, so it holds no per-tool logic. A later adapter (Altium through its own CLI or an exported netlist, Eagle through KiCad's importer) adds a record, a parser and a test.

## Plan, in increments (one PR each)

1. **Compare anything.** Tags and any typed ref in the compare menu; merge-base (`...`) compares; the whole hierarchy with changes per sheet, moving through sheets inside a comparison; per-layer marks; Old / Diff / New flip. All four clients.
2. **BOM and BOM diff.** `bom.bend`, a Review tab in the viewer that shows markdown reports (BOM, BOM diff, later checks and releases) through the existing `Md.render` on all four clients; a parts-change summary on PRs.
3. **Design checks.** ERC, DRC, BOM rules, checklist, custom scripts, on any version, in a detached worktree. Violations drawn as markers at their positions; MCP `design_check`; a PR gate.
4. **Review comments.** Anchored pins on all four clients (right-click or long-press "Comment here"), replies, resolve; event log variants; MCP `review_comments`/`review_comment`; open comments in the agent's prompt; export to the PR and to an issue.
5. **Releases.** Tag, gate on checks, outputs from the tag, notes from the BOM diff and checks since the last tag, local folder plus `gh release`.

## Status

1. Compare anything: done (window, web, iOS, Android). Typed refs, tags and the branch point; per-layer marks follow the active layer; sheets keep comparing; Old / Diff / New; the bar under every board and schematic.
