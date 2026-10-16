import Base
import ../core/json.bend as J
import ../core/order.bend as OR
import ./google.bend as GS
import ./proc.bend as P
import ./host.bend as H

# Ordering, the IO (core/order.bend; docs/order.md)
# ==================================================
# The order server is reached with curl, its URL, headers and form lines
# in a config file (google.bend's Gc.*), never on the command line. This
# install's id (a random word made once, <home>/secrets/install-id) goes
# with every request: the server's limits count it, nothing else does.

def Od.tmp(+home: String) -> String:
  home ++ "/secrets"

def Od.install.k(+old: String, +fresh: String, +path: String) -> IO(String):
  Bool.pick(IO(String), Nat.is_ge(String.length(String.trim(old)), 16n), IO.pure(String, String.trim(old)),
    IO.bind(Unit, String, GS.Gf.write(path, fresh), _ => IO.pure(String, fresh)))

def Od.install(+home: String) -> IO(String):
  do IO<String>:
    mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(Od.tmp(home))
    old : String <- GS.Gf.text(Od.tmp(home) ++ "/install-id")
    +fresh : String <- GS.Gf.nonce(6n)
    Od.install.k(old, fresh, Od.tmp(home) ++ "/install-id")

def Od.heads(+install: String) -> List<&2, String>:
  ["X-Backplane-Install: " ++ install, "Accept: application/json"]

# The project card
# ----------------
# fab.look: the intent, each *.fab.json found (not under extra/ or mfg/,
# no hidden folders), and, with estimates on, the server's "from" price of
# the bare parts.

def Od.find() -> String:
  "find . -maxdepth 5 -name '*.fab.json' -not -path './extra/*' -not -path './mfg/*' -not -path '*/.*' -not -path '*/node_modules/*' 2>/dev/null | LC_ALL=C sort | head -n 40 | sed 's|^\\./||'"

def Od.ran(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      out
    case P.Ran{_, _}:
      ""

def Od.line.k(blank: Bool, +l: String, rest: List<&2, String>) -> List<&2, String>:
  match blank:
    case True{}:
      rest
    case False{}:
      String.trim(l) <> rest

def Od.lines(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Od.line.k(String.is_empty(String.trim(l)), l, Od.lines(t))

def Od.read(ps: List<&2, String>, +cwd: String) -> IO(List<&2, OR.FabFile>):
  match ps:
    case Nil{}:
      IO.pure(List<&2, OR.FabFile>, Nil{})
    case +p <> t:
      do IO<List<&2, OR.FabFile>>:
        text : String <- GS.Gf.text(cwd ++ "/" ++ p)
        rest : List<&2, OR.FabFile> <- Od.read(t, cwd)
        return OR.FabFile{p, text} <> rest

# a part as the card lists it: name, kind and where its fab.json is
def Od.part.row(+p: J.Json) -> J.Json:
  J.Json.obj([J.KV{"name", J.Str{J.Json.get_str(p, "name", "")}}, J.KV{"kind", J.Str{J.Json.get_str(p, "kind", "")}}, J.KV{"path", J.Str{J.Json.get_str(p, "path", "")}}])

def Od.part.rows(ps: List<&2, J.Json>) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Od.part.row(p) <> Od.part.rows(t)

# what the server said, as the card's fields: the price's label, or why there is none
def Od.est.got(r: GS.GResp) -> J.Json:
  match r:
    case GS.GResp{+code, +body, +err}:
      Bool.pick(J.Json, GS.Gc.ok(code), Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}),
        J.Json.obj([J.KV{"error", J.Str{Bool.pick(String, String.eq(code, "000"), "the order server is not reachable" ++ Bool.pick(String, String.is_empty(err), "", ": " ++ err),
          J.Json.get_str(Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}), "error", "the order server said " ++ code))}}]))

def Od.est.k(ask: Bool, +home: String, +server: String, +install: String, +body: String) -> IO(J.Json):
  match ask:
    case True{}:
      IO.bind(GS.GResp, J.Json, GS.Gc.req(Od.tmp(home), server ++ "/v1/estimate", ["Content-Type: application/json", "X-Backplane-Install: " ++ install], body),
        r => IO.pure(J.Json, Od.est.got(r)))
    case False{}:
      IO.pure(J.Json, J.Null{})

# the card's answer: {thread, intent, goal, parts, boards, label, error, estimates}
def Od.card(+thread: String, +intent: String, ps: List<&2, J.Json>, +boards: String, +est: J.Json, +on: Bool) -> J.Json:
  J.Json.obj([J.KV{"thread", J.Str{thread}}, J.KV{"intent", J.Str{intent}}, J.KV{"goal", J.Str{OR.Intent.goal(intent)}},
    J.KV{"parts", J.Json.arr(Od.part.rows(ps))}, J.KV{"boards", J.Num{boards}}, J.KV{"label", J.Str{J.Json.get_str(est, "label", "")}},
    J.KV{"error", J.Str{J.Json.get_str(est, "error", "")}}, J.KV{"estimates", J.Flag{on}}])

# KiCad boards in the project, for a card with no fab files yet
def Od.boards() -> String:
  "find . -maxdepth 4 -name '*.kicad_pcb' -not -path '*/.*' -not -path './extra/*' -not -path './mfg/*' -not -path '*backup*' -not -path '*/node_modules/*' 2>/dev/null | head -n 20 | wc -l | tr -d ' '"

def Od.count(r: P.Ran) -> String:
  match r:
    case P.Ran{0, +out}:
      Bool.pick(String, String.is_empty(String.trim(out)), "0", String.trim(out))
    case P.Ran{_, _}:
      "0"

# with no fab files but a board, the server is only asked whether it is there
def Od.health.k(ask: Bool, +home: String, +server: String) -> IO(J.Json):
  match ask:
    case True{}:
      IO.bind(GS.GResp, J.Json, GS.Gc.req(Od.tmp(home), server ++ "/v1/health", ["Accept: application/json"], ""), r => IO.pure(J.Json, Od.est.got(r)))
    case False{}:
      IO.pure(J.Json, J.Null{})

def Od.look.ps(ps: List<&2, J.Json>, +home: String, +cwd: String, +thread: String, +intent: String, +on: Bool, +server: String) -> IO(J.Json):
  match ps:
    case Nil{}:
      do IO<J.Json>:
        r : P.Ran <- P.Proc.run("sh", ["-c", Od.boards()], cwd)
        +n : String = Od.count(r)
        est : J.Json <- Od.health.k(Bool.and(on, Bool.not(String.eq(n, "0"))), home, server)
        return Od.card(thread, intent, Nil{}, n, est, on)
    case +p <> +t:
      do IO<J.Json>:
        +install : String <- Od.install(home)
        est : J.Json <- Od.est.k(on, home, server, install, OR.Order.est.body(p <> t))
        return Od.card(thread, intent, p <> t, "0", est, on)

# where the first newline is (the length when there is none)
def Od.nl(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+c}, t}:
      Bool.pick(Nat, U32.is_eq(c, 10), 0n, 1n+Od.nl(t))

# opts: "on|off\n<server>" (hub.bend's Buy.look)
def Od.look(+home: String, +cwd: String, +thread: String, +opts: String) -> IO(J.Json):
  do IO<J.Json>:
    intent : String <- GS.Gf.text(cwd ++ "/.backplane/intent.md")
    r : P.Ran <- P.Proc.run("sh", ["-c", Od.find()], cwd)
    fs : List<&2, OR.FabFile> <- Od.read(Od.lines(String.lines(Od.ran(r))), cwd)
    Od.look.ps(OR.Order.parts(fs), home, cwd, thread, String.trim(intent), Bool.not(String.starts_with(opts, "off")),
      String.trim(String.drop(opts, Nat.add(1n, Od.nl(opts)))))

# fab.intent: the person's own words for .backplane/intent.md, then the card
def Od.intent(+home: String, +cwd: String, +thread: String, +opts: String, text: String) -> IO(J.Json):
  do IO<J.Json>:
    mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(cwd ++ "/.backplane")
    GS.Gf.write(cwd ++ "/.backplane/intent.md", String.trim(text) ++ "\n")
    m : Result<&1, &1, U32 & String, Unit> <- H.FS.chmod(cwd ++ "/.backplane/intent.md", 420)
    Od.look(home, cwd, thread, opts)

# Quotes
# ------
# order_quote: the manifest's files (paths inside the order's folder, plain
# characters only), sent as one multipart request; then the quote is
# polled until it is worked out. The token stays with the hub: in
# <home>/orders/<quote>.json (0600) and in the Pay link it posts.

def Od.safe.c(+c: U32) -> Bool:
  Bool.and(U32.is_ge(c, 32), Bool.not(Bool.or(Bool.or(U32.is_eq(c, 34), U32.is_eq(c, 92)), Bool.or(U32.is_eq(c, 59), U32.is_eq(c, 127)))))

def Od.safe.chars(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(Od.safe.c(c), Od.safe.chars(t))

# a path from the order's folder that stays inside it
def Od.safe(+p: String) -> Bool:
  Bool.and(Bool.and(Bool.not(String.is_empty(p)), Bool.not(String.starts_with(p, "/"))),
    Bool.and(Bool.not(String.contains(p, "..")), Od.safe.chars(p)))

def Od.keys(fs: J.Json) -> List<&2, String>:
  match fs:
    case J.Field{+k, _, t}:
      k <> Od.keys(t)
    case _:
      Nil{}

def Od.files.k(o: J.Json) -> List<&2, String>:
  match o:
    case J.Obj{fs}:
      Od.keys(fs)
    case _:
      Nil{}

# the files a manifest lists ("files": {path: sha256})
def Od.files(+m: J.Json) -> List<&2, String>:
  Od.files.k(J.Json.get_obj(m, "files"))

def Od.all.safe(ps: List<&2, String>) -> Bool:
  match ps:
    case Nil{}:
      True{}
    case +p <> t:
      Bool.and(Od.safe(p), Od.all.safe(t))

def Od.forms(ps: List<&2, String>, +dir: String) -> String:
  match ps:
    case Nil{}:
      ""
    case +p <> t:
      "form = " ++ GS.Gc.q("file=@\"" ++ p ++ "\";filename=\"" ++ p ++ "\"") ++ "\n" ++ Od.forms(t, dir)

def Od.upload.cfg(+url: String, +install: String, +dir: String, ps: List<&2, String>, +out: String) -> String:
  "url = " ++ GS.Gc.q(url) ++ "\n" ++ GS.Gc.headers(Od.heads(install)) ++ "form = " ++ GS.Gc.q("manifest=<manifest.json") ++ "\n"
    ++ Od.forms(ps, dir) ++ "output = " ++ GS.Gc.q(out) ++ "\n" ++ "write-out = \"%{http_code}\"\n"

# the server's answer to an upload: {id, token} or {error} (curl runs in the
# order's folder and names every file from there, by the checked relative paths)
def Od.upload(+home: String, +server: String, +install: String, +dir: String, ps: List<&2, String>) -> IO(J.Json):
  do IO<J.Json>:
    +name : String <- GS.Gf.nonce(3n)
    +cfg : String = Od.tmp(home) ++ "/o-" ++ name ++ ".curl"
    +out : String = Od.tmp(home) ++ "/o-" ++ name ++ ".out"
    GS.Gf.write(cfg, Od.upload.cfg(server ++ "/v1/quotes", install, dir, ps, out))
    r : P.Ran <- P.Proc.run("curl", ["-sS", "--max-time", "300", "-K", cfg], dir)
    +said : String = GS.Gc.ran(r)
    text : String <- GS.Gf.text(out)
    GS.Gf.rm(cfg)
    GS.Gf.rm(out)
    return Od.est.got(GS.GResp{GS.Gc.code(said), text, GS.Gc.said(said)})

def Od.get(+home: String, +server: String, +install: String, +qid: String, +token: String) -> IO(J.Json):
  IO.bind(GS.GResp, J.Json, GS.Gc.req(Od.tmp(home), server ++ "/v1/quotes/" ++ qid, ["Authorization: Bearer " ++ token, "X-Backplane-Install: " ++ install], ""),
    r => IO.pure(J.Json, Od.est.got(r)))

def Od.pending(+q: J.Json) -> Bool:
  Bool.or(String.eq(J.Json.get_str(q, "status", ""), "received"), String.eq(J.Json.get_str(q, "status", ""), "analysing"))

def Od.poll.k(+q: J.Json, again: Unit -> IO(J.Json)) -> IO(J.Json):
  Bool.pick(IO(J.Json), Od.pending(q), again(Unit{}), IO.pure(J.Json, q))

# at most n polls, 3 s apart
def Od.poll(n: Nat, +home: String, +server: String, +install: String, +qid: String, +token: String) -> IO(J.Json):
  match n:
    case 0n:
      IO.pure(J.Json, J.Json.obj([J.KV{"error", J.Str{"the quote is taking long; ask order_status in a few minutes"}}]))
    case 1n+m:
      IO.bind(Unit, J.Json, IO.sleep(3000), _ =>
        IO.bind(J.Json, J.Json, Od.get(home, server, install, qid, token), q => Od.poll.k(q, u => Od.poll(m, home, server, install, qid, token))))

# the record a quote leaves: what the hub needs to follow it
def Od.record(+qid: String, +token: String, +thread: String, +server: String, +status: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"id", J.Str{qid}}, J.KV{"token", J.Str{token}}, J.KV{"thread", J.Str{thread}}, J.KV{"server", J.Str{server}}, J.KV{"status", J.Str{status}}]))

def Od.orders(+home: String) -> String:
  home ++ "/orders"

def Od.keep(+home: String, +qid: String, +token: String, +thread: String, +server: String, +status: String) -> IO(Unit):
  do IO<Unit>:
    mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(Od.orders(home))
    GS.Gf.write(Od.orders(home) ++ "/" ++ qid ++ ".json", Od.record(qid, token, thread, server, status))

# the Pay link: the quote's page on the server, with its token
def Od.pay(+server: String, +qid: String, +token: String) -> String:
  server ++ "/q/" ++ qid ++ "?t=" ++ token
