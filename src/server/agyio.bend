import Base
import ./proc.bend as P
import ./botnet.bend as BN
import ../core/port.bend as PT
import ../core/agy.bend as AGY

# Google Antigravity's IO (core/agy.bend): its folder <home>/antigravity
# (the agent's version folder, the runner script, the profiles, the last
# models the agent listed), the install, the probe the models info is
# made from, sign-out, and the way back from Google's sign-in delivered on
# this machine. No Google token is ever read here: the agent keeps its own.

def Agx.root(+home: String) -> String:
  home ++ "/antigravity"

# the runner script, written whole (renamed into place: turns may be
# starting from it)
def Agx.write.sh() -> String:
  "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$1/agy.sh.$$\" && chmod 755 \"$1/agy.sh.$$\" && mv \"$1/agy.sh.$$\" \"$1/agy.sh\""

def Agx.ok(r: P.Ran) -> Bool:
  match r:
    case P.Ran{c, _}:
      U32.is_eq(c, 0)

def Agx.write(+root: String) -> IO(Bool):
  IO.bind(P.Ran, Bool, P.Proc.run("sh", ["-c", Agx.write.sh(), "sh", root, AGY.Agy.run.sh()], "/"), r => IO.pure(Bool, Agx.ok(r)))

def Agx.out(r: P.Ran) -> String:
  match r:
    case P.Ran{_, o}:
      o

# BACKPLANE_AGY_SOURCE ("URL SIZE SHA256") replaces the pinned archive, for
# tests; unset, the pins in core/agy.bend
def Agx.source(+src: String) -> List<&2, String>:
  String.split(String.trim(src), ' ')

def Agx.install.args(+root: String, +src: String) -> List<&2, String>:
  PT.Port.timeout(List.append(&2, String, ["3600", "sh", "-c", AGY.Agy.install.sh(), "sh", root],
    Bool.pick(List<&2, String>, String.is_empty(String.trim(src)), Nil{}, Agx.source(src))))

# install the pinned agent: "" when it is in place, else why not
def Agx.install(+root: String) -> IO(String):
  do IO<String>:
    +src : String <- BN.Bf.env("BACKPLANE_AGY_SOURCE")
    w : Bool <- Agx.write(root)
    r : P.Ran <- P.Proc.run("sh", Agx.install.args(root, src), "/")
    return AGY.Agy.install.err(Agx.out(r))

# what is installed, the accounts and the models last listed
def Agx.probe(+root: String) -> IO(AGY.AgyInfo):
  IO.bind(P.Ran, AGY.AgyInfo, P.Proc.run("sh", ["-c", AGY.Agy.probe.sh(root), "sh", root], "/"), r => IO.pure(AGY.AgyInfo, AGY.Agy.info(Agx.out(r))))

# the models a sign-in listed (the cache's text, one line)
def Agx.models.save(+root: String, +cache: String) -> IO(Bool):
  do IO<Bool>:
    BN.Bf.dir(root)
    BN.Bf.secret(root ++ "/models.json", cache ++ "\n")

# sign an account out: the agent's stored token goes (its other files
# stay); "forget" removes the account's folder too
def Agx.signout.sh() -> String:
  "p=$1; rm -f \"$p/antigravity-acp/acp_token.json\"; [ \"$2\" = forget ] && rm -rf \"$p\"; exit 0"

def Agx.signout(+root: String, +acct: String, +forget: Bool) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", Agx.signout.sh(), "sh", AGY.Agy.profile(root, acct), Bool.pick(String, forget, "forget", "")], "/"), r => IO.pure(Unit, Unit{}))

# Google's way back, fetched here (the agent listens on this machine's
# loopback): no proxy, ten seconds; "" when it answered 2xx
def Agx.forward.sh() -> String:
  "c=$(curl -s --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 10 -- \"$1\"); case \"$c\" in 2*) exit 0;; *) echo \"the sign-in did not take the answer ($c)\"; exit 1;; esac"

def Agx.forwarded(r: P.Ran) -> String:
  match r:
    case P.Ran{c, o}:
      Bool.pick(String, U32.is_eq(c, 0), "", AGY.Agy.or(String.trim(o), "the sign-in did not take the answer"))

def Agx.forward(+url: String) -> IO(String):
  IO.bind(P.Ran, String, P.Proc.run("sh", ["-c", Agx.forward.sh(), "sh", url], "/"), r => IO.pure(String, Agx.forwarded(r)))

# the sign-in in progress (its process, so Cancel can stop it)
def Agx.pidfile(+root: String) -> String:
  root ++ "/signin.pid"

# stop the sign-in in progress: only the process its pid file names, and
# only while that is still this sign-in (its command names the runner),
# so a pid file left by a hub that stopped never reaches another process
def Agx.cancel.sh() -> String:
  "f=$1/signin.pid; [ -f \"$f\" ] || exit 0; p=$(cat \"$f\"); case \"$p\" in ''|*[!0-9]*) exit 0;; esac; ps -o args= -p \"$p\" 2>/dev/null | grep -q \"$1/agy.sh\" && kill \"$p\"; exit 0"

def Agx.cancel(+root: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", Agx.cancel.sh(), "sh", root], "/"), r => IO.pure(Unit, Unit{}))
