# Pi and Oh My Pi

Backplane can run two more agents, `pi` and `omp`. They are separate
programs with different protocols. Backplane uses each one's own protocol,
not OpenCode's and not each other's.

| | Pi | Oh My Pi |
|---|---|---|
| Project | earendil-works/pi (`@earendil-works/pi-coding-agent`), MIT | can1357/oh-my-pi (`@oh-my-pi/pi-coding-agent`), MIT |
| Verified against | 1.4.0 | 18.12.6 |
| Run as | `pi --mode rpc`, Pi's JSONL RPC | `omp acp`, its ACP server |
| Code | `src/core/pi.bend` | `src/core/omp.bend` |

## Install and sign in

- **Pi:** install it from https://pi.dev and put `pi` on PATH. Run `pi` once and use `/login`, or set the provider's API key.
- **Oh My Pi:** install it from https://github.com/can1357/oh-my-pi and put `omp` on PATH. Run `omp` once and use `/login`.

Backplane never writes either agent's settings, credentials or sessions. They stay in `~/.pi/agent` and `~/.omp`.

Each provider appears in every model picker once its CLI is on PATH. The models come from `pi --list-models` (run offline) and from `omp models --json`. Both list only models they have credentials for. If no models show, sign in first.

## What a thread gets

- **Sessions:** a thread keeps its session from turn to turn.
  - Pi gets `--session-id <Backplane's id>` and resumes without replaying history.
  - omp uses `session/resume`.
  - If the agent no longer has the session, the turn says so once as an info row. The agent then starts without the earlier conversation.
- **Instructions:** Backplane's instructions go in with `--append-system-prompt` at every start. They never enter the conversation. Each agent also reads `AGENTS.md` and `CLAUDE.md` in the thread's folder.
- **Backplane tools:**
  - Pi gets the thread's Backplane MCP server from Backplane's extension, which is written to `<home>/pi/backplane.js` and loaded with `-e`.
  - omp gets it in `session/new` and `session/resume`.
- **Effort:**
  - Pi takes `--thinking`. The picker offers off through high for models that think.
  - omp uses its session's `thinking` option, with the levels it reports per model, plus off and auto.
- **Stop** ends the agent's process. Both agents save their sessions as they go.

## Supervision

| Backplane mode | Pi (Backplane's extension) | omp (`--approval-mode`) |
|---|---|---|
| Supervised | Asks before every tool except read, grep, find, ls and Backplane's own | `always-ask`: asks before writes, edits and commands |
| Accept edits | Edit and write run; everything else asks | `write`: writes, edits and MCP tools run; commands ask |
| Auto, Full access | Nothing asks | `yolo`: nothing asks |

Pi has no approval prompts of its own, so Backplane's extension gates every tool call, including MCP tools and tools that codemode calls. omp asks through ACP permission requests for bash, delete and move, and through form elicitations for everything else. Both kinds go to the person as Backplane approvals.

"Allow for session" works as it does for Grok, by tool name.

## Questions

These go to the person as Backplane questions:

- A dialog from another Pi extension (select, confirm, input or editor).
- A one-question `ask` from omp.

When omp asks several questions at once, or offers a multiple choice, Backplane declines it and says so in the thread.

## Not mapped

- **Reasoning text:** neither agent's reasoning is shown. The hub has no reasoning row for these event shapes.
- **Token usage and cost:** not shown for either agent.
- **Images:** attached images reach either agent as file paths in the text, not as image blocks.
- **omp errors:** omp reports a model or provider error during a turn as reply text, so the turn ends as completed.
