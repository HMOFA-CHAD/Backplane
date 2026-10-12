import Base
import ./proc.bend as P
import ../core/json.bend as J
import ../core/hist.bend as HI
import ../core/codec.bend as C
import ../core/hier.bend as HR
import ../core/bom.bend as BM
import ./host.bend as H
import ./kicad.bend as K
import ./git.bend as GT
import ./gh.bend as GH

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

# BOMs (core/bom.bend)
# --------------------
# A version's schematic, every sheet it reaches with its bytes (the root
# first read, at most 64 files), parsed in a child process (`backplane
# --review bom OLD NEW`), never in the hub: OLD "" is one BOM of NEW,
# else what changed from OLD to NEW. Versions are hist.bend's paths: a
# live file or a file in a commit.

def Rvc.next(todo: List<&2, String>, +tab: List<&2, HR.Kids>, acc: List<&2, BM.Sheet>, k: List<&2, HR.Kids> -> List<&2, String> -> List<&2, BM.Sheet> -> IO(List<&2, BM.Sheet>)) -> IO(List<&2, BM.Sheet>):
  match todo:
    case Nil{}:
      IO.pure(List<&2, BM.Sheet>, acc)
    case +p <> rest:
      do IO<List<&2, BM.Sheet>>:
        +bs : List<&2, U32> <- GT.Git.version(p)
        +kd : HR.Kids = HR.Hier.kids(p, bs)
        k(kd <> tab, HR.Hier.todo(HR.Hier.kids.sheets(kd), kd <> tab, rest), BM.Sheet{p, bs} <> acc)

def Rvc.load(fuel: Nat, +todo: List<&2, String>, +tab: List<&2, HR.Kids>, acc: List<&2, BM.Sheet>) -> IO(List<&2, BM.Sheet>):
  match fuel:
    case 0n:
      IO.pure(List<&2, BM.Sheet>, acc)
    case 1n+f:
      Rvc.next(todo, tab, acc, t2 => d2 => a2 => Rvc.load(f, d2, t2, a2))

def Rvc.parts(+root: String) -> IO(List<&2, BM.Part>):
  Bool.pick(IO(List<&2, BM.Part>), String.is_empty(root), IO.pure(List<&2, BM.Part>, Nil{}),
    IO.bind(List<&2, BM.Sheet>, List<&2, BM.Part>, Rvc.load(64n, [root], Nil{}, Nil{}), shs => IO.pure(List<&2, BM.Part>, BM.Bom.parts("", List.reverse(&2, BM.Sheet, shs)))))

def Rvc.finding(f: BM.Fnd) -> String:
  match f:
    case BM.Fnd{_, +sev, +ref, +msg}:
      "- **" ++ ref ++ "** " ++ msg ++ " _(" ++ sev ++ ")_"

def Rvc.findings(fs: List<&2, BM.Fnd>) -> List<&2, String>:
  match fs:
    case Nil{}:
      Nil{}
    case f <> t:
      Rvc.finding(f) <> Rvc.findings(t)

def Rvc.checks(+fs: List<&2, BM.Fnd>) -> String:
  Bool.pick(String, List.is_empty(&2, BM.Fnd, fs), "", "\n\nChecks\n\n" ++ String.join(Rvc.findings(fs), "\n"))

# one BOM: how many parts in how many lines, the lines, what the BOM rules
# found
def Rvc.one(+ps: List<&2, BM.Part>) -> String:
  Bool.pick(String, List.is_empty(&2, BM.Part, ps), "No parts.",
    Nat.show(List.length(&2, BM.Part, ps)) ++ " parts in " ++ Nat.show(List.length(&2, BM.Line, BM.Bom.group(ps))) ++ " lines\n\n" ++ BM.Bom.md(BM.Bom.group(ps)) ++ Rvc.checks(BM.Bom.rules(ps)))

def Rvc.bom.k(one: Bool, +a: String, +b: String) -> IO(String):
  match one:
    case True{}:
      IO.bind(List<&2, BM.Part>, String, Rvc.parts(b), ps => IO.pure(String, Rvc.one(ps)))
    case False{}:
      do IO<String>:
        +os : List<&2, BM.Part> <- Rvc.parts(a)
        +ns : List<&2, BM.Part> <- Rvc.parts(b)
        return BM.Bom.diff.md(os, ns)

def Rvc.bom(+a: String, +b: String) -> IO(Unit):
  IO.bind(String, Unit, Rvc.bom.k(String.is_empty(a), a, b), md => IO.print(md))

def Rvc.args.copy(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> Rvc.args.copy(t)

def Rvc.args.back(xs: List<&2, String>) -> List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> Rvc.args.back(t)

def Rvc.main.k(xs: List<&2, String>, go: List<String> -> IO(Unit)) -> IO(Unit):
  match xs:
    case "--review" <> "bom" <> a <> b <> _:
      Rvc.bom(a, b)
    case +x:
      go(Rvc.args.back(x))

# the program's arguments: a --review child's, or the program's own (go)
def Rvc.main(xs: List<String>, go: List<String> -> IO(Unit)) -> IO(Unit):
  Rvc.main.k(Rvc.args.copy(xs), go)

# the child, run from the hub: its Markdown, or why it failed
def Rvc.run(+args: List<&2, String>) -> IO(P.Ran):
  IO.bind(String, P.Ran, H.Sys.exe_path(), exe => P.Proc.run(exe, args, "/"))

def Rvc.sch(f: K.Files) -> String:
  match f:
    case K.Files{_, _, +sch, _}:
      sch

def RvJob.report(r: P.Ran, +thread: String, +page: String) -> Res:
  match r:
    case P.Ran{0, +out}:
      Res{True{}, J.Json.obj([J.KV{"report", J.Json.obj([J.KV{"thread", J.Str{thread}}, J.KV{"page", J.Str{page}}, J.KV{"md", J.Str{String.trim_end(out)}}])}])}
    case P.Ran{_, +out}:
      Res{True{}, J.Json.obj([J.KV{"report", J.Json.obj([J.KV{"thread", J.Str{thread}}, J.KV{"page", J.Str{page}}, J.KV{"md", J.Str{""}},
        J.KV{"err", J.Str{Bool.pick(String, String.is_empty(String.trim(out)), "could not read the schematic", String.trim(out))}}])}])}

def RvJob.bom.k(+sch: String, +thread: String, +a: String, +b: String) -> IO(Res):
  Bool.pick(IO(Res), String.is_empty(sch), IO.pure(Res, Res{True{}, J.Json.obj([J.KV{"report", J.Json.obj([J.KV{"thread", J.Str{thread}}, J.KV{"page", J.Str{"bom"}}, J.KV{"md", J.Str{""}}, J.KV{"err", J.Str{"This project has no schematic."}}])}])}),
    IO.bind(P.Ran, Res, Rvc.run(["--review", "bom", Bool.pick(String, String.is_empty(a), "", HI.Hist.rebase(a, sch)), Bool.pick(String, String.is_empty(b), sch, HI.Hist.rebase(b, sch))]),
      r => IO.pure(Res, RvJob.report(r, thread, "bom"))))

# review.bom {thread, a, b}: the BOM of b (a "": one BOM; b "": the working
# copy), or what changed from a to b; a and b are versions of any file of
# the project (the one on show), read at its root schematic
def RvJob.bom(+thread: String, +cwd: String, +a: String, +b: String) -> IO(Res):
  IO.bind(K.Files, Res, K.Files.read(cwd), f => RvJob.bom.k(Rvc.sch(f), thread, a, b))

# A pull request's parts change
# -----------------------------
# After Backplane opens a pull request, its BOM change (where the branch
# left main to what it pushed) goes on it as a comment, when there is one.

def RvJob.pr.sh() -> String:
  String.join([
    "exec 2>/dev/null",
    "cd \"$1\" || exit 1",
    "top=$(git rev-parse --show-toplevel) || exit 1",
    "gd=$(cd \"$(git rev-parse --git-common-dir)\" && pwd) || exit 1",
    "h=$(git rev-parse HEAD) || exit 1",
    "for b in origin/HEAD origin/main origin/master main master; do",
    "  m=$(git merge-base HEAD \"$b\") || continue",
    "  [ \"$m\" != \"$h\" ] && { printf '%s\\n%s\\n%s\\n%s\\n' \"$gd\" \"$top\" \"$m\" \"$h\"; exit 0; }",
    "done",
    "exit 1"], "\n")

def RvJob.pr.spec(+ls: List<&2, String>, +c: String, +sch: String) -> String:
  HI.Hist.git(HI.Hist.at(ls, 0n), c, HI.Hist.at(ls, 1n), String.drop(sch, 1n+String.length(HI.Hist.at(ls, 1n))))

def Rvc.ok(r: P.Ran) -> Bool:
  match r:
    case P.Ran{c, _}:
      U32.is_eq(c, 0)

def RvJob.pr.post(r: P.Ran, +cwd: String, +url: String) -> IO(String):
  match r:
    case P.Ran{0, +md}:
      Bool.pick(IO(String), Bool.or(String.is_empty(String.trim(md)), String.starts_with(md, "No changes")), IO.pure(String, ""),
        IO.bind(P.Ran, String, GH.GhRun.gh(cwd, ["pr", "comment", url, "--body", "**Parts changed**\n\n" ++ String.trim_end(md)]),
          g => IO.pure(String, Bool.pick(String, Rvc.ok(g), "parts change posted on the pull request", ""))))
    case _:
      IO.pure(String, "")

def RvJob.pr.k(r: P.Ran, +sch: String, +cwd: String, +url: String) -> IO(String):
  match r:
    case P.Ran{0, +out}:
      +ls = String.split(String.trim(out), '\n')
      Bool.pick(IO(String), Bool.or(String.is_empty(sch), Bool.not(String.starts_with(sch, HI.Hist.at(ls, 1n) ++ "/"))), IO.pure(String, ""),
        IO.bind(P.Ran, String, Rvc.run(["--review", "bom", RvJob.pr.spec(ls, HI.Hist.at(ls, 2n), sch), RvJob.pr.spec(ls, HI.Hist.at(ls, 3n), sch)]), m => RvJob.pr.post(m, cwd, url)))
    case _:
      IO.pure(String, "")

# the parts change of the branch in cwd, posted on its pull request (url);
# what to tell the thread ("" nothing)
def RvJob.pr(+cwd: String, +url: String) -> IO(String):
  do IO<String>:
    f : K.Files <- K.Files.read(cwd)
    r : P.Ran <- P.Proc.run("sh", ["-c", RvJob.pr.sh(), "sh", cwd], "/")
    out : String <- RvJob.pr.k(r, Rvc.sch(f), cwd, url)
    return out

def RvJob.go(i: Nat, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Res):
  match i:
    case 0n:
      RvJob.resolve(thread, cwd, a, b)
    case 1n:
      RvJob.bom(thread, cwd, a, b)
    case _:
      IO.pure(Res, Res.err("unknown review job"))

def RvJob.names() -> List<&2, String>:
  ["rv.resolve", "rv.bom"]

# a job by name ("rv.resolve", …)
def RvJob.run(+job: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Res):
  RvJob.go(C.Codec.pos(RvJob.names(), job), thread, cwd, a, b, home)
