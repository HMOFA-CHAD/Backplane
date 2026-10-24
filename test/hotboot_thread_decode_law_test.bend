import Base
import ../src/core/snapshot.bend as S
import ../src/core/model.bend as M
import ../src/core/storedb.bend as DB
import ../src/core/json.bend as J
import ../src/server/hotboot.bend as H
import ./hotboot_test.bend as Fixture
import ./check.bend as C

# Reusing exactly the full thread map decoded from these rows gives the
# original complete snapshot, for arbitrary records and entry windows.
law snapshot_decoded_threads_exact:
  for +rows: S.SRows
  {S.Snap.state.threads(rows, S.Fill.threads(S.SRows.of(rows, "thread"), Map.new(&2, M.Thread))) == S.Snap.state(rows) : M.State}

def snapshot_decoded_threads_exact(rows):
  {==}

# SQL uses these ids as an IN set. Compare the complete set, independent
# of SQL row order versus the decoded map's order.
def ids.keys(xs: List<&2, Sigma<&2, &2, String, _ => Bool>>) -> String:
  match xs:
    case Nil{}: ""
    case (k, _) <> rest: k ++ "\n" ++ ids.keys(rest)

def ids.set(xs: List<&2, J.Json>) -> String:
  ids.keys(Map.to_list(&2, Bool, H.Hot.had(xs, Map.new(&2, Bool))))

def ids.rows(+rows: S.SRows) -> IO(Unit):
  C.Check.str("decoded full threads select the original open-window set",
    ids.set(H.Hot.ids.decoded(Map.to_list(&2, M.Thread, S.Fill.threads(S.SRows.of(rows, "thread"), Map.new(&2, M.Thread))), Nil{})),
    ids.set(H.Hot.ids.rows(S.SRows.of(rows, "thread"), Nil{})))

def ids.materialized(m: DB.Mat) -> IO(Unit):
  match m:
    case DB.Mat{_, fs, rs, _, _, _}: ids.rows(S.Snap.rows(fs, rs))

def ids.cut(n: Nat) -> IO(Unit):
  ids.materialized(DB.Mat.replay(List.take(&2, DB.LL, Fixture.lls(Fixture.lines()), n), DB.Mat.empty()))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("ok complete snapshot equals original with decoded thread map")
    ids.cut(0n)
    ids.cut(10n)
    ids.cut(20n)
    ids.cut(21n)
    ids.cut(22n)
    ids.cut(45n)
    ids.cut(List.length(&2, String, Fixture.lines()))
