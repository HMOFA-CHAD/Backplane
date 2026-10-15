import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/usage.bend as UZ

# Settings > Usage from a replayed log: readings are listed fullest first,
# never added up; a Codex thread says ctx n/a; archived threads are left
# out; a reading's missing part (0) keeps the last one.

def log() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "demo", "/tmp/demo", 1n},
   M.ThreadCreated{"t1", "p1", "Small", M.Local{}, "", "", "claude", "claude-opus-5-5", 1n},
   M.ThreadCreated{"t2", "p1", "Big", M.Local{}, "", "", "claude", "claude-sonnet-5-5", 1n},
   M.ThreadCreated{"t3", "p1", "Codex", M.Local{}, "", "", "codex", "gpt-6.1-sol", 1n},
   M.ThreadCreated{"t4", "p1", "Old", M.Local{}, "", "", "claude", "", 1n},
   M.UsageSet{"t1", 0n, 1000000n, 2n},
   M.UsageSet{"t1", 50000n, 0n, 3n},
   M.UsageSet{"t2", 150000n, 200000n, 4n},
   M.UsageSet{"t4", 9000n, 0n, 5n},
   M.ThreadArchived{"t4", True{}, 6n}]

def show(rs: List<&2, UZ.URow>) -> String:
  match rs:
    case Nil{}:
      ""
    case r <> t:
      UZ.URow.label(r) ++ " | " ++ UZ.URow.note(r) ++ "\n" ++ show(t)

def main() -> IO(Unit):
  do IO<Unit>:
    +st : M.State = M.State.replay(log(), M.State.empty())
    C.Check.str("rows", show(U.Usage.rows(st)),
      "Context now | 2 of 3 open threads have a reading. Only Claude reports one; others show ctx n/a.\n" ++
      "Big | claude-sonnet-5-5 · 150k of 200k held (75%)\n" ++
      "Small | claude-opus-5-5 · 50k of 1M held (5%)\n" ++
      "Tokens and cost | Not recorded yet. A reading is what a session holds now, not what it has used, so readings are not added up.\n")
    C.Check.str("chip claude", U.Usage.tail(st, "t1"), " · ctx 5% of 1M")
    C.Check.str("chip codex", U.Usage.tail(st, "t3"), " · ctx n/a")
    C.Check.str("empty", show(U.Usage.rows(M.State.empty())),
      "Context now | 0 of 0 open threads have a reading. Only Claude reports one; others show ctx n/a.\n" ++
      "Tokens and cost | Not recorded yet. A reading is what a session holds now, not what it has used, so readings are not added up.\n")
