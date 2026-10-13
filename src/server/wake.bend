import Base
import ./host.bend as H
import ./gh.bend as GH
import ./proc.bend as P
import ../core/port.bend as PT
import ../core/wake.bend as WK

# Account selection and bounded gh invocation; no gh auth switch.
def WakeJob.pr(+target: String, +cwd: String) -> IO(P.Ran):
  GH.GhRun.remote("https://github.com/" ++ WK.Wake.pr.repo(target), cwd, "sh",
    PT.Port.timeout(["25", "gh", "pr", "view", WK.Wake.pr.num(target), "-R", WK.Wake.pr.repo(target), "--json", "number,title,state,mergedAt,mergeCommit,statusCheckRollup,files"]),
    PT.Port.timeout(["25", "gh", "pr", "view", WK.Wake.pr.num(target), "-R", WK.Wake.pr.repo(target), "--json", "number,title,state,mergedAt,mergeCommit,statusCheckRollup,files"]))

def WakeJob.stamp(r: Result<&1, &1, U32 & String, U32 & U32 & U32>) -> String:
  match r:
    case Done{(kind, (size, mtime))}:
      U32.show(kind) ++ ":" ++ U32.show(mtime) ++ ":" ++ U32.show(size)
    case Fail{_}:
      "missing"

def WakeJob.file(+path: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, U32 & U32 & U32>, String, H.FS.stat(path), r => IO.pure(String, WakeJob.stamp(r)))
