import Base
import ./check.bend as T
import ../src/server/storeio.bend as S
import ../src/server/db.bend as D
import ../src/server/hotboot.bend as H
import ../src/server/stobuild.bend as B
import ../src/core/storedb.bend as C
import ../src/core/store.bend as ST
import ../src/core/codec.bend as CO
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/snapshot.bend as SN

def write.done(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, _) = r
  File.close(f)

def write(+path: String, mode: String, text: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.bind(Result<&1, &1, U32 & String, File>, File, File.open(path, mode), B.Stb.file)
    IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(f, text), write.done)

def lines(cs: List<&2, M.Change>) -> List<&2, String>:
  match cs:
    case Nil{}: Nil{}
    case c <> t: J.Json.show(CO.Change.encode(c)) <> lines(t)

def temp(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Done{(_, (out, _))}: String.trim(out)
    case Fail{_}: ""

def meta(+h: String, key: String) -> IO(String):
  do IO<String>:
    rs : List<&2, List<&2, String>> <- D.Db.query(h, "SELECT v FROM meta WHERE k=?", [key], 1)
    return SN.Snap.col(Maybe.default(&2, List<&2, String>, List.head(&2, List<&2, String>, rs), Nil{}), 0n)

def newentry() -> M.Change:
  M.MessagePosted{"checkpoint-thread", "checkpoint-message", M.User{}, "Unsent 日本語 is still exact", 30n}

def pad(n: Nat, text: String) -> String:
  match n:
    case 0n: text
    case 1n+t: pad(t, "checkpoint padding " ++ text)

def updated.result(x: S.Updated) -> String:
  match x:
    case S.Updated{_, result}: result

def ordinal(cs: List<&2, M.Change>, ord: Nat) -> Nat:
  match cs:
    case Nil{}: ord
    case c <> t: ordinal(t, C.Sdb.ord(c, ord))

def main() -> IO(Unit):
  do IO<Unit>:
    made : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("mktemp", ["-d"], "", 4096, 10000)
    +home : String = temp(made)
    +path : String = home ++ "/events.jsonl"
    +initial : List<&2, String> = lines(List.append(&2, M.Change, List.take(&2, M.Change, C.Demo.changes(), 12n), [M.SettingSet{"checkpoint.pad", pad(300n, ""), 20n}]))
    write(path, "w", ST.Store.text(initial))
    +h : String <- S.Sto.open(home)
    seq : String <- meta(h, "applied_seq")
    T.Check.str("new store checkpoint includes every line", seq, "13")
    cl : String <- D.Db.close(h)
    # A process died after its log append, before its checkpoint transaction.
    +tail : List<&2, String> = lines(List.take(&2, M.Change, List.drop(&2, M.Change, C.Demo.changes(), 12n), 8n))
    write(path, "a", ST.Store.text(tail))
    +h2 : String <- S.Sto.open(home)
    seq2 : String <- meta(h2, "applied_seq")
    T.Check.str("crash tail advances atomically on next boot", seq2, "21")
    ord : String <- meta(h2, "ord")
    T.Check.str("ordinal checkpoint equals full fold, without decimal prefix", ord, Nat.show(ordinal(List.take(&2, M.Change, C.Demo.changes(), 20n), 1n)))
    +off : String <- meta(h2, "applied_off")
    +hot : H.Hot <- H.Hot.load(home)
    T.Check.str("current store is accepted by hot boot", H.Hot.why(hot), "")
    +append : List<&2, String> = lines([newentry()])
    write(path, "a", ST.Store.text(append))
    updated : S.Updated <- S.Sto.commit(h2, home, H.Hot.st(hot), append, SN.Snap.num(off, 0n))
    T.Check.str("normal append checkpoint committed", String.take(updated.result(updated), 2n), "ok")
    seq3 : String <- meta(h2, "applied_seq")
    T.Check.str("normal append increments durable sequence", seq3, "22")
    +before : String <- meta(h2, "applied_off")
    countBefore : List<&2, List<&2, String>> <- D.Db.query(h2, "SELECT count(*) FROM line", [], 1)
    trigger : String <- D.Db.exec(h2, "CREATE TRIGGER injected BEFORE INSERT ON meta WHEN NEW.k='applied_off' BEGIN SELECT RAISE(ABORT, 'injected checkpoint failure'); END")
    +again : H.Hot <- H.Hot.load(home)
    write(path, "a", ST.Store.text(append))
    failure : S.Updated <- S.Sto.commit(h2, home, H.Hot.st(again), append, SN.Snap.num(before, 0n))
    T.Check.str("failed transaction returns failure", String.take(updated.result(failure), 4n), "fail")
    after : String <- meta(h2, "applied_off")
    T.Check.str("failed transaction never advances checkpoint", after, before)
    countAfter : List<&2, List<&2, String>> <- D.Db.query(h2, "SELECT count(*) FROM line", [], 1)
    T.Check.str("late transaction failure rolls back already written facts", SN.Snap.col(Maybe.default(&2, List<&2, String>, List.head(&2, List<&2, String>, countAfter), Nil{}), 0n), SN.Snap.col(Maybe.default(&2, List<&2, String>, List.head(&2, List<&2, String>, countBefore), Nil{}), 0n))
    drop : String <- D.Db.exec(h2, "DROP TRIGGER injected")
    close2 : String <- D.Db.close(h2)
    +h3 : String <- S.Sto.open(home)
    seq4 : String <- meta(h3, "applied_seq")
    T.Check.str("failed transaction tail is recoverable without duplicate facts", seq4, "23")
    bad : String <- D.Db.exec(h3, "UPDATE meta SET v='0' WHERE k='codec'")
    close3 : String <- D.Db.close(h3)
    +h4 : String <- S.Sto.open(home)
    codec : String <- meta(h4, "codec")
    T.Check.str("schema mismatch makes a fresh versioned snapshot", codec, Nat.show(C.Sdb.codec()))
    seq5 : String <- meta(h4, "applied_seq")
    T.Check.str("schema fallback preserves complete event history", seq5, "23")
    close4 : String <- D.Db.close(h4)
    write(path, "a", "{torn")
    +h5 : String <- S.Sto.open(home)
    seq6 : String <- meta(h5, "applied_seq")
    T.Check.str("torn unnumbered tail is retained without a false event", seq6, "23")
    +last : H.Hot <- H.Hot.load(home)
    T.Check.str("repaired torn tail remains loadable", H.Hot.why(last), "")
    close5 : String <- D.Db.close(h5)
    +h6 : String <- S.Sto.open(home)
    seq7 : String <- meta(h6, "applied_seq")
    T.Check.str("normal closed current checkpoint needs no replay", seq7, "23")
    close6 : String <- D.Db.close(h6)
    # Replacement log, not the checkpoint's log: never accept stale records.
    write(path, "w", ST.Store.text(lines([M.ProjectCreated{"other", "Other log", "/tmp/other", 100n}])))
    +h7 : String <- S.Sto.open(home)
    seq8 : String <- meta(h7, "applied_seq")
    T.Check.str("different or shortened log cannot reuse stale checkpoint", seq8, "1")
    +replacement : H.Hot <- H.Hot.load(home)
    T.Check.str("replacement log rebuild is current", H.Hot.why(replacement), "")
    close7 : String <- D.Db.close(h7)
    IO.print("checkpoint fixture: " ++ home)
