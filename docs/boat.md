# Boat jobs

Heavy commands (checks, proofs, tests, builds) can run on a disposable
[Boat](https://boat.dev) sandbox instead of this machine, so they don't
take the local "bend" lock or its memory.

```
work_run {note: "check on Boat",
          command: "cd <your worktree> && scripts/boat-job.sh --size default --timeout 900 -- scripts/check.sh"}
```

Each job gets its own sandbox, deleted when it ends; no lock is needed.
Admission follows Boat's live limits, read before every create: active
sandboxes and the rolling start windows per minute, hour and day (other
clients' starts included, through Boat's own remaining counts; ours also
from our own record, whichever is stricter, less jobs still starting). A
full slot or minute/hour window waits (`--wait`, default 1 h, one limits
read per pause, at least 15 s apart); a full day refuses. A rate-limited
create (429) backs off (retry-after, else 15 s, 30 s, ...; at most 5 tries)
and is admitted again; a create whose answer is unclear is never retried,
so it never makes a second sandbox. It keeps its slot, its start and its
worst-case budget until a sweep reconciles it: the one matching unknown
sandbox (size, lifetime, creation time) is adopted and deleted; none by the
end of its lifetime + 10 min closes it at its worst-case cost; look-alikes
still up after that make it unresolved, and new creates are refused until
they are gone (running jobs carry on). Other clients' sandboxes are never
adopted or deleted. Run it from the worktree whose source should
be checked (integrate main into your own worktree; don't reset the shared
checkout).

## What is verified (default, 8 GB, 4 vCPU)
| command | result | wall | peak RSS |
|---|---|---|---|
| `scripts/check.sh` (type-check + PROOF) | exit 0 | 149 s | 4.29 GB |
| `scripts/check.sh proof` | exit 0 | 98 s | 4.32 GB |
| `scripts/test.sh` (136 programs) | exit 0 | 294 s | 3.38 GB |
| native `BACKPLANE_LOW_MEM=1 scripts/build-app.sh src/app/main.bend build/backplane` (4 GiB heap hint, one clang at a time; `CC=clang-19`, `libx11-dev`, `libasound2-dev` installed in the job, `BACKPLANE_GOOGLE_BAKE=0`) | exit 0 twice; the built binary starts `--headless` and answers `/hello` | 17–21 min | 6.7–7.1 GB (0.6–1.0 GB left free: tight) |

Small (4 GB) is not validated for any of these. The native build at the default 8 GiB hint does not fit 8 GB (its emit alone is about 8.8 GB); use `BACKPLANE_LOW_MEM=1` there, or `--size large` (16 GB) if it starts failing.

The outcome arrives like any work: the command's exit code and the end of its output.
Every job's files are in `~/.local/state/backplane/boat/jobs/<job>/`:
`job.log` (the full output), `setup.log`, `manifest.sha256`,
`artifacts/` + `artifacts.sha256`, and `provenance.json` (revision, dirty
flag, manifest hash, Bend version and sha256, sandbox, size, command, exit).

## Options
- `--size small|default|large`: 2 vCPU / 4 GB at half rate, 4 vCPU / 8 GB, or 8 vCPU / 16 GB at twice the rate. Default is default; ask for large only when the job is measured to need it.
- `--timeout SECS` (default 1800): the command's limit; the sandbox lives at most that + 10 min, and never more than 2 h.
- `--artifact PATH` (repeat): copied back from the sandbox before it is deleted.
- `--exclude GLOB` (repeat): more files to keep out of the upload.
- `--budget-usd X` (default 0.50, or `BOAT_JOB_BUDGET_USD`): the daily cap.
- `--wait SECS` (default 3600, or `BOAT_JOB_WAIT`): how long to wait for a free slot before refusing.
- `--no-setup-bend`: skip installing Bend (the pinned version and sha256 come from `.github/actions/setup-bend/action.yml`).
- `scripts/boat-job.sh sweep`: delete sandboxes this tool started whose job is gone. `status` (or `status --json`, `status --refresh` to read Boat's limits first; the same view is kept in `status.json` after every ledger change, and the last limits read in `account.json`, for the Usage settings): jobs, their state, owner thread, size, runtime, reserved and actual credits, today's spend.

## Rules it keeps
- Off unless the repository's root is listed in `~/.local/state/backplane/boat/enabled`.
- The runner runs from a private copy of itself, so editing or rebasing the worktree during a job doesn't change it; any unexpected exit still deletes the sandbox.
- Fail closed. A job is refused (exit 75) and nothing is created when Boat's limits can't be read, the account can't start, no slot frees up within `--wait` (jobs still starting count as taken), compute is short, the size isn't offered, the daily budget would be exceeded, or an earlier delete was never verified.
- Budget: each job reserves its worst case (lifetime × rate) under a ledger lock, so jobs started together can't overspend. The real cost (`boat usage`) is recorded when it ends. Boat has no spend cap of its own, so this is the only one.
- Source: `git ls-files -co --exclude-standard` (tracked and untracked-not-ignored files), without `.env*`, keys and certificates, `auth.json`, `*.log`, `*.jsonl` outside `test/`, `build/`, `dist/`, `node_modules/`, `shots-snap/`, `.claude/` and `.backplane*/`. Nothing from the home directory.
- Sandboxes: `boat new --no-env` (none of the account's stored secrets), `--no-snapshots` (erased when stopped), a bounded `--ttl`.
- Cleanup: the sandbox is deleted, then checked gone in `boat list`, on success, failure and cancel (`work_cancel`). A job killed outright is cleaned up by the next job's sweep. Only sandboxes in the ledger are ever deleted. A delete that can't be verified exits 77 and blocks new jobs until a sweep removes it.
- Exit codes: the command's own; 75 refused, 76 setup failed (or a create with an unclear answer whose sandbox couldn't be identified: check `boat list`), 77 cleanup unverified, 143 cancelled. Boat's URLs are never printed or logged.

Test: `test/tools/boat_job_test.sh` (a fake `boat`, `test/tools/boat-fake`; no network).
