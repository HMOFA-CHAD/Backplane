# Boat jobs

Heavy commands (checks, proofs, tests, builds) can run on a disposable
[Boat](https://boat.dev) sandbox instead of this machine, so they don't
take the local "bend" lock or its memory.

```
work_run {lock: "boat", note: "check on Boat",
          command: "scripts/boat-job.sh --size default --timeout 900 -- scripts/check.sh"}
```

Run it from the worktree whose source should be checked. The outcome
arrives like any work: the command's exit code and the end of its output.
Every job's files are in `~/.local/state/backplane/boat/jobs/<job>/`:
`job.log` (the full output), `setup.log`, `manifest.sha256`,
`artifacts/` + `artifacts.sha256`, and `provenance.json` (revision, dirty
flag, manifest hash, Bend version and sha256, sandbox, size, command, exit).

## Options
- `--size small|default`: 2 vCPU / 4 GB at half rate, or 4 vCPU / 8 GB. Larger sizes are refused (they need a paid plan).
- `--timeout SECS` (default 1800): the command's limit; the sandbox lives at most that + 10 min, and never more than 2 h.
- `--artifact PATH` (repeat): copied back from the sandbox before it is deleted.
- `--exclude GLOB` (repeat): more files to keep out of the upload.
- `--budget-usd X` (default 0.50, or `BOAT_JOB_BUDGET_USD`): the daily cap.
- `--no-setup-bend`: skip installing Bend (the pinned version and sha256 come from `.github/actions/setup-bend/action.yml`).
- `scripts/boat-job.sh sweep`: delete sandboxes this tool started whose job is gone. `status`: open jobs and today's spend.

## Rules it keeps
- Off unless the repository's root is listed in `~/.local/state/backplane/boat/enabled`.
- Fail closed. A job is refused (exit 75) and nothing is created when Boat's limits can't be read, the account can't start, all sandboxes are taken (counting jobs still starting), compute is short, the size isn't offered, the daily budget would be exceeded, or an earlier delete was never verified.
- Budget: each job reserves its worst case (lifetime × rate) under a ledger lock, so jobs started together can't overspend. The real cost (`boat usage`) is recorded when it ends. Boat has no spend cap of its own, so this is the only one.
- Source: `git ls-files -co --exclude-standard` (tracked and untracked-not-ignored files), without `.env*`, keys and certificates, `auth.json`, `*.log`, `*.jsonl` outside `test/`, `build/`, `dist/`, `node_modules/`, `shots-snap/`, `.claude/` and `.backplane*/`. Nothing from the home directory.
- Sandboxes: `boat new --no-env` (none of the account's stored secrets), `--no-snapshots` (erased when stopped), a bounded `--ttl`.
- Cleanup: the sandbox is deleted, then checked gone in `boat list`, on success, failure and cancel (`work_cancel`). A job killed outright is cleaned up by the next job's sweep. Only sandboxes in the ledger are ever deleted. A delete that can't be verified exits 77 and blocks new jobs until a sweep removes it.
- Exit codes: the command's own; 75 refused, 76 setup failed, 77 cleanup unverified, 143 cancelled. Boat's URLs are never printed or logged.

Test: `test/tools/boat_job_test.sh` (a fake `boat`, `test/tools/boat-fake`; no network).
