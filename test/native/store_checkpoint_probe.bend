import Base
import ../../src/server/storeio.bend as S
import ../../src/server/db.bend as D
import ../../src/server/argv.bend as AV
import ../../src/server/perf.bend as P
import ../../src/server/jsloop.bend as LP

# Diagnostic only: pass a disposable consistent home copy, never a live home.
# Prints offsets/counts and phase time; no event text or session material.
def summary(rs: List<&2, List<&2, String>>) -> String:
  match rs:
    case Nil{}: ""
    case r <> t: String.join(r, "=") ++ " " ++ summary(t)

def run(+home: String) -> IO(Unit):
  do IO<Unit>:
    t0 : U32 <- P.Perf.us()
    +h : String <- S.Sto.open(home)
    t1 : U32 <- P.Perf.span("checkpoint.catchup", t0)
    rs : List<&2, List<&2, String>> <- D.Db.query(h, "SELECT k,v FROM meta WHERE k IN ('applied_seq','applied_off','ord','codec') ORDER BY k", [], 10)
    IO.print("checkpoint " ++ summary(rs))
    closed : String <- D.Db.close(h)
    IO.print(closed)
    stats : String <- P.Perf.take()
    IO.print(stats)
    IO.print("checkpoint complete")

def main() -> IO(Unit):
  do IO<Unit>:
    loop : String <- LP.Rt.loop()
    args : List<String> <- AV.Argv.args()
    run(Maybe.default(&1, String, List.head(&1, String, args), "/nonexistent-private-fixture"))
