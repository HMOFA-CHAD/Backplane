import Base
import ./proc.bend as P
import ../core/json.bend as J
import ../core/hist.bend as HI
import ../core/codec.bend as C

# Design review's jobs (docs/design-review.md): what the hub asks of a
# thread's folder for comparisons, BOMs, checks and releases (core's
# hub.bend Rv.request, jobs "rv.…"). Each answers (ok, result); server.bend
# replies with it (RvJob.run), so this module never names the hub.

type Res is Data:
  Res{ok: Bool, result: J.Json}

def Res.err(+why: String) -> Res:
  Res{False{}, J.Json.obj([J.KV{"error", J.Str{why}}])}

# Any version by name
# -------------------
# A commit, branch or tag typed in, as the commit it names, with the git
# folder and top the viewer's version paths need (core/hist.bend's
# Hist.git). The text goes to git as an argument, never as shell text; one
# that starts with "-" is refused.

def RvJob.resolve.sh() -> String:
  String.join([
    "exec 2>/dev/null",
    "cd \"$1\" || exit 1",
    "top=$(git rev-parse --show-toplevel) || { echo 'not a git repository'; exit 1; }",
    "gd=$(cd \"$(git rev-parse --git-common-dir)\" && pwd) || exit 1",
    "c=$(git rev-parse --verify --quiet \"$2^{commit}\") || { echo \"no commit, branch or tag named $2\"; exit 1; }",
    "printf '%s\\n%s\\n%s\\n' \"$c\" \"$gd\" \"$top\""], "\n")

def RvJob.resolved(r: P.Ran, +thread: String, +side: String, +ref: String) -> Res:
  match r:
    case P.Ran{0, +out}:
      Res{True{}, J.Json.obj([J.KV{"resolved", J.Json.obj([J.KV{"thread", J.Str{thread}}, J.KV{"side", J.Str{side}}, J.KV{"ref", J.Str{ref}},
        J.KV{"commit", J.Str{String.trim(HI.Hist.at(String.split(out, '\n'), 0n))}}, J.KV{"git", J.Str{String.trim(HI.Hist.at(String.split(out, '\n'), 1n))}},
        J.KV{"top", J.Str{String.trim(HI.Hist.at(String.split(out, '\n'), 2n))}}])}])}
    case P.Ran{_, +out}:
      Res.err(Bool.pick(String, String.is_empty(String.trim(out)), "could not resolve " ++ ref, String.trim(out)))

def RvJob.resolve.k(bad: Bool, +thread: String, +cwd: String, +side: String, +ref: String) -> IO(Res):
  match bad:
    case True{}:
      IO.pure(Res, Res.err("no commit, branch or tag named " ++ ref))
    case False{}:
      IO.bind(P.Ran, Res, P.Proc.run("sh", ["-c", RvJob.resolve.sh(), "sh", cwd, ref], "/"), r => IO.pure(Res, RvJob.resolved(r, thread, side, ref)))

def RvJob.resolve(+thread: String, +cwd: String, +side: String, +ref: String) -> IO(Res):
  RvJob.resolve.k(Bool.or(String.is_empty(ref), Bool.or(String.starts_with(ref, "-"), String.is_empty(cwd))), thread, cwd, side, ref)

def RvJob.go(i: Nat, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Res):
  match i:
    case 0n:
      RvJob.resolve(thread, cwd, a, b)
    case _:
      IO.pure(Res, Res.err("unknown review job"))

def RvJob.names() -> List<&2, String>:
  ["rv.resolve"]

# a job by name ("rv.resolve", …)
def RvJob.run(+job: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Res):
  RvJob.go(C.Codec.pos(RvJob.names(), job), thread, cwd, a, b, home)
