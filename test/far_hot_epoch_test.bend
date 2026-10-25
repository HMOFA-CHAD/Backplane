import Base
import ./check.bend as C
import ./hotboot_test.bend as F
import ../src/server/hotboot.bend as HB
import ../src/server/server.bend as H
import ../src/core/store.bend as ST
import ../src/core/storedb.bend as S
import ../src/core/model.bend as M

# Exercise the actual store-based loader, including a checkpoint with a
# replayed tail. Peer history identity must agree with a cold replay and
# survive a second load of the same store. No real hub or peer is started.
def epoch.cut(+cut: Nat) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- F.home(cut, Nat.show(S.Sdb.codec()), F.log.id())
    +a : HB.Hot <- HB.Hot.load(dir)
    +b : HB.Hot <- HB.Hot.load(dir)
    C.Check.str("hot epoch cut " ++ Nat.show(cut) ++ ": used checkpoint", Bool.show(HB.Hot.ok(a)), "True")
    C.Check.str("hot epoch cut " ++ Nat.show(cut) ++ ": oldest durable line", Maybe.default(&2, String, List.last(&2, String, HB.Hot.ls(a)), "missing"), Maybe.default(&2, String, List.last(&2, String, ST.Loaded.wire(F.full())), "missing-cold"))
    C.Check.str("hot epoch cut " ++ Nat.show(cut) ++ ": far equals cold replay", H.Far.history.at(HB.Hot.ls(a), M.State.seq(HB.Hot.st(a))), H.Far.history.at(ST.Loaded.wire(F.full()), M.State.seq(ST.Loaded.st(F.full()))))
    C.Check.str("hot epoch cut " ++ Nat.show(cut) ++ ": far survives reload", H.Far.history.at(HB.Hot.ls(a), M.State.seq(HB.Hot.st(a))), H.Far.history.at(HB.Hot.ls(b), M.State.seq(HB.Hot.st(b))))
    C.Check.str("hot epoch cut " ++ Nat.show(cut) ++ ": client origin equals cold", H.Hub.origin(HB.Hot.ls(a)), H.Hub.origin(ST.Loaded.wire(F.full())))
    rm : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("rm", ["-rf", dir], "", 4096, 10000)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    epoch.cut(20n)
    epoch.cut(List.length(&2, String, F.lines()))
