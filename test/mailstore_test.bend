import Base
import ./check.bend as C
import ./mailbody_test.bend as B
import ../src/server/mailstore.bend as S
import ../src/server/host.bend as H
import ../src/core/mailbody.bend as MB
import ../src/core/mail.bend as ML
import ../src/core/model.bend as M

# Tests use only a newly created BACKPLANE_HOME; never the person's home.
def home_result(r: Result<&1, &1, U32 & String, String>) -> IO(String):
  match r:
    case Done{SCon{c, t}}: IO.pure(String, SCon{c, t} ++ "/mailstore-test")
    case _: IO.die(String, 1, "mailstore_test needs a fresh temp BACKPLANE_HOME")

def home() -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env("BACKPLANE_HOME")
    home_result(r)

def status(-A: Data, r: S.StoreResult<A>) -> String:
  match r:
    case S.Stored{_}: "ok"
    case S.Missing{_}: "missing"
    case S.StoreError{_, _}: "error"

def repaired(r: S.StoreResult<Bool>) -> String:
  match r:
    case S.Stored{b}: Bool.show(b)
    case _: "error"

def ids(bs: List<&2, MB.Body>, acc: String) -> String:
  match bs:
    case Nil{}: acc
    case b <> t: ids(t, acc ++ ML.Mail.id(MB.Body.mail(b)) ++ ",")

def page(r: S.StoreResult<List<&2, MB.Body>>) -> String:
  match r:
    case S.Stored{bs}: ids(bs, "")
    case S.Missing{_}: "missing"
    case S.StoreError{_, e}: "error: " ++ e

def changes(r: S.StoreResult<List<&2, M.Change>>) -> List<&2, M.Change>:
  match r:
    case S.Stored{cs}: cs
    case _: Nil{}

def inject_close(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, got) = r
  do IO<Unit>:
    IO.try(Unit, IO.pure(Result<&1, &1, U32 & String, Unit>, got))
    File.close(f)

def inject(path: String, text: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "a"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, text)
    inject_close(r)

def app(+home: String, id: String, conv: String, text: String, at: Nat) -> IO(Unit):
  do IO<Unit>:
    r : S.StoreResult<Bool> <- S.MailStore.append(home, B.fixture(id, conv, text, at))
    C.Check.str("append " ++ id, status(Bool, r), "ok")

def main() -> IO(Unit):
  do IO<Unit>:
    +h : String <- home()
    r0 : S.StoreResult<List<&2, M.Change>> <- S.MailStore.recover(h, ML.Box.empty())
    C.Check.str("absent directory recovery", status(List<&2, M.Change>, r0), "ok")
    r1 : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(h, "absent", "", 10n)
    C.Check.str("absent read distinguished", status(List<&2, MB.Body>, r1), "missing")
    z : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read("/impossible/no-io", "c", "unknown", 0n)
    C.Check.str("zero page no IO", page(z), "")
    app(h, "a", "c", "雪😀\n\"{}", 1n)
    app(h, "b", "c", "B", 2n)
    app(h, "a", "c", "雪😀\n\"{}", 1n)
    app(h, "d", "c", "D", 0n)
    p : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(h, "c", "", 2n)
    C.Check.str("newest unique arrival order independent time", page(p), "d,b,")
    older : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(h, "c", "b", 50n)
    C.Check.str("strict before", page(older), "a,")
    oldest : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(h, "c", "a", 50n)
    C.Check.str("before oldest", page(oldest), "")
    unknown : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(h, "c", "unknown", 1n)
    C.Check.str("unknown cursor explicit", status(List<&2, MB.Body>, unknown), "error")
    inject(MB.Body.path(h, "c"), "{\"v\":1,\"text\":\"torn")
    torn : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(h, "c", "", 10n)
    C.Check.str("torn suffix ignored", page(torn), "d,b,a,")
    fixed : S.StoreResult<Bool> <- S.MailStore.append(h, B.fixture("e", "c", "E", 3n))
    C.Check.str("append reports torn repair", repaired(fixed), "True")
    after : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(h, "c", "", 10n)
    C.Check.str("complete A torn append B readable once", page(after), "e,d,b,a,")
    app(h, "evil", "../:|%雪;$(x)", "safe", 0n)
    safe : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(h, "../:|%雪;$(x)", "", 10n)
    C.Check.str("hostile conv real file", page(safe), "evil,")
    +rh : String = h ++ "/recovery"
    app(rh, "r1", "one", "one", 10n)
    app(rh, "r2", "two", "two", 20n)
    app(rh, "r3", "one", "three", 30n)
    app(rh, "r1", "one", "one", 10n)
    +rec : S.StoreResult<List<&2, M.Change>> <- S.MailStore.recover(rh, ML.Box.empty())
    C.Check.str("orphan recovery success", status(List<&2, M.Change>, rec), "ok")
    C.Check.str("two convs three unique headers", Nat.show(List.length(&2, M.Change, changes(rec))), "5")
    +box : ML.Box = S.Scan.fold(changes(rec), ML.Box.empty())
    C.Check.str("orphan header same id", Bool.show(ML.Box.has(box, "r3")), "True")
    again : S.StoreResult<List<&2, M.Change>> <- S.MailStore.recover(rh, box)
    C.Check.str("second recovery empty", Nat.show(List.length(&2, M.Change, changes(again))), "0")
    C.Check.str("recovery newest metadata last", Nat.show(ML.Conv.last(ML.Box.conv(box, "one"))), "30")
    app(h, "dup", "conflict", "first", 0n)
    app(h, "dup", "conflict", "second", 0n)
    conflict : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(h, "conflict", "", 10n)
    C.Check.str("conflicting duplicate error", status(List<&2, MB.Body>, conflict), "error")
    app(h, "bad", "bad", "first", 0n)
    inject(MB.Body.path(h, "bad"), "{}\n")
    bad : S.StoreResult<Bool> <- S.MailStore.append(h, B.fixture("bad2", "bad", "", 0n))
    C.Check.str("completed corruption append error", status(Bool, bad), "error")
    br : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(h, "bad", "", 10n)
    C.Check.str("completed corruption read error", status(List<&2, MB.Body>, br), "error")
    inject(MB.Body.path(h, "future"), "{\"v\":2}\n")
    future : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(h, "future", "", 10n)
    C.Check.str("unknown version visible", status(List<&2, MB.Body>, future), "error")
    inject(MB.Body.path(h, "invalid"), "not json\n")
    invalid : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(h, "invalid", "", 1n)
    C.Check.str("invalid JSON visible", status(List<&2, MB.Body>, invalid), "error")
    rr : S.StoreResult<List<&2, M.Change>> <- S.MailStore.recover(h, ML.Box.empty())
    C.Check.str("recovery corruption explicit", status(List<&2, M.Change>, rr), "error")
    inject(h ++ "/block", "file")
    fail : S.StoreResult<Bool> <- S.MailStore.append(h ++ "/block", B.fixture("noheader", "c", "", 0n))
    C.Check.str("filesystem append failure explicit no changes API", status(Bool, fail), "error")
