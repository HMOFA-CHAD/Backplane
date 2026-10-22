import Base
import ../../src/server/db.bend as D
import ../../src/server/argv.bend as A
import ../../src/core/json.bend as J
import ../../src/core/model.bend as M
import ../../src/core/codec.bend as C
import ../../src/core/storedb.bend as S
import ../../src/core/utf8.bend as U

# A stand-in for S1's store rebuild (Sto.*, not written yet), so the hot
# boot has a store.db to start from: HOME/store.db made from the first
# lines of HOME/events.jsonl (every line that starts before UPTO bytes;
# default the whole log), with S1's pure materializer's facts per line
# (S.Sdb.facts; search terms left out) and every record of the folded
# state at the end (S.Dump.ops), and meta codec/applied_seq/applied_off.
# The log is read in 8 MB chunks; the state is folded in memory as the
# full replay folds it. Run on a copy of a home only:
#   bend test/native/snap_build.bend HOME [UPTO]

type LN is Data:
  LN{len: Nat, text: String}

type Cut is Data:
  Cut{part: List<&2, U32>, n: Nat, done: List<&2, LN>}

def Cut.step(nl: Bool, +x: U32, c: Cut) -> Cut:
  match nl c:
    case True{} Cut{part, +n, done}:
      Cut{Nil{}, 0n, LN{n, U.Utf8.decode(List.reverse(&2, U32, part))} <> done}
    case False{} Cut{part, +n, done}:
      Cut{x <> part, 1n+n, done}

def Cut.go(bs: List<&2, U32>, c: Cut) -> Cut:
  match bs:
    case Nil{}:
      c
    case +x <> t:
      Cut.go(t, Cut.step(U32.is_eq(x, 10), x, c))

# the complete lines of a chunk, oldest first
def Cut.done(c: Cut) -> List<&2, LN>:
  match c:
    case Cut{_, _, done}:
      List.reverse(&2, LN, done)

def Cut.lines(bs: List<&2, U32>) -> List<&2, LN>:
  Cut.done(Cut.go(bs, Cut{Nil{}, 0n, Nil{}}))

# the fold so far: state, lines numbered, byte offset, next entry ordinal,
# statements to write (newest first)
type B is Data:
  B{st: M.State, seq: Nat, off: Nat, ord: Nat, items: List<&2, List<&2, String>>}

def B.off(b: B) -> Nat:
  match b:
    case B{_, _, o, _, _}:
      o

def Ops.sql(os: List<&2, S.Op>, acc: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match os:
    case Nil{}:
      acc
    case S.Put{+t, cols} <> rest:
      Ops.sql(rest, Bool.pick(List<&2, List<&2, String>>, String.eq(t, "term"), acc, S.Sql.of(S.Put{t, cols}) <> acc))
    case o <> rest:
      Ops.sql(rest, S.Sql.of(o) <> acc)

def B.change(m: Maybe<&2, M.Change>, +st: M.State, +seq: Nat, +off: Nat, +len: Nat, +ord: Nat, items: List<&2, List<&2, String>>) -> B:
  match m:
    case Some{+c}:
      B{M.State.apply(st, c), seq, Nat.add(off, 1n+len), S.Sdb.ord(c, ord), Ops.sql(S.Sdb.facts(st, S.At{seq, off, len, ord}, c), items)}
    case None{}:
      B{st, seq, Nat.add(off, 1n+len), ord, Ops.sql([S.F.line(S.At{seq, off, len, ord}, "")], items)}

def B.parsed(m: Maybe<&2, J.Json>, +len: Nat, b: B) -> B:
  match m b:
    case Some{+o} B{st, +seq, +off, +ord, items}:
      B.change(C.Change.decode(o), st, 1n+seq, off, len, ord, items)
    case None{} B{st, seq, +off, ord, items}:
      B{st, seq, Nat.add(off, 1n+len), ord, items}

def B.line(go: Bool, l: LN, b: B) -> B:
  match go l:
    case True{} LN{+len, +text}:
      B.parsed(J.Json.parse(text), len, b)
    case False{} _:
      b

# lines that start before end
def B.lines(ls: List<&2, LN>, +end: Nat, b: B) -> B:
  match ls:
    case Nil{}:
      b
    case l <> t:
      +b2 = b
      B.lines(t, end, B.line(Nat.is_lt(B.off(b2), end), l, b2))

def B.flush(b: B) -> B & List<&2, List<&2, String>>:
  match b:
    case B{st, seq, off, ord, items}:
      (B{st, seq, off, ord, Nil{}}, List.reverse(&2, List<&2, String>, items))

def Rd.done(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (f, res) = r
  do IO<List<&2, U32>>:
    File.close(f)
    return Result.default(&1, &1, U32 & String, List<&2, U32>, res, Nil{})

def Rd.at.k(r: Result<&1, &1, U32 & String, File>, +at: U32, +n: U32) -> IO(List<&2, U32>):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, List<&2, U32>, File.read_at(f, at, n), Rd.done)
    case Fail{_}:
      IO.pure(List<&2, U32>, Nil{})

def Rd.at(path: String, +at: U32, +n: U32) -> IO(List<&2, U32>):
  IO.bind(Result<&1, &1, U32 & String, File>, List<&2, U32>, File.open(path, "r"), r => Rd.at.k(r, at, n))

def Rd.size.done(r: File & Result<&1, &1, U32 & String, U32>) -> IO(U32):
  (f, res) = r
  do IO<U32>:
    File.close(f)
    return Result.default(&1, &1, U32 & String, U32, res, 0)

def Rd.size.k(r: Result<&1, &1, U32 & String, File>) -> IO(U32):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, U32, File.size(f), Rd.size.done)
    case Fail{_}:
      IO.pure(U32, 0)

def Rd.size(path: String) -> IO(U32):
  IO.bind(Result<&1, &1, U32 & String, File>, U32, File.open(path, "r"), Rd.size.k)

def Chunk() -> Nat:
  8388608n

def Write.ok.k(fine: Bool, +r: String, +what: String) -> IO(Unit):
  match fine:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "snap_build: " ++ what ++ ": " ++ r)

def Write.ok(+r: String, +what: String) -> IO(Unit):
  Write.ok.k(String.starts_with(r, "ok"), r, what)

def Build.write(r: B & List<&2, List<&2, String>>, +h: String, k: B -> IO(B)) -> IO(B):
  (b, items) = r
  do IO<B>:
    w : String <- D.Db.script(h, items)
    Write.ok(w, "facts")
    k(b)

def Build.chunk(more: Bool, +h: String, +path: String, +end: Nat, +size: Nat, b: B, k: B -> IO(B)) -> IO(B):
  match more:
    case False{}:
      IO.pure(B, b)
    case True{}:
      do IO<B>:
        +off : Nat = B.off(b)
        bs : List<&2, U32> <- Rd.at(path, U32.from_nat(off), U32.from_nat(Bool.pick(Nat, Nat.is_lt(Nat.sub(size, off), Chunk()), Nat.sub(size, off), Chunk())))
        +b2 : B = B.lines(Cut.lines(bs), end, b)
        IO.print("  at byte " ++ Nat.show(B.off(b2)))
        Build.stuck(Nat.is_eq(B.off(b2), off), h, b2, k)

def Build.stuck(same: Bool, +h: String, b: B, k: B -> IO(B)) -> IO(B):
  match same:
    case True{}:
      IO.pure(B, b)
    case False{}:
      Build.write(B.flush(b), h, k)

def Build.loop(fuel: Nat, +h: String, +path: String, +end: Nat, +size: Nat, b: B) -> IO(B):
  match fuel:
    case 0n:
      IO.pure(B, b)
    case 1n+f:
      +b2 = b
      Build.chunk(Nat.is_lt(B.off(b2), end), h, path, end, size, b2, x => Build.loop(f, h, path, end, size, x))

def Dump.sql(os: List<&2, S.Op>, acc: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match os:
    case Nil{}:
      List.reverse(&2, List<&2, String>, acc)
    case o <> t:
      Dump.sql(t, S.Sql.of(o) <> acc)

def Build.finish(b: B, +h: String) -> IO(Unit):
  match b:
    case B{+st, +seq, +off, _, _}:
      do IO<Unit>:
        w : String <- D.Db.script(h, Dump.sql(S.Dump.ops(st), Nil{}))
        Write.ok(w, "records")
        m : String <- D.Db.script(h, [["INSERT OR REPLACE INTO meta(k, v) VALUES (?, ?)", "schema", "1"], ["INSERT OR REPLACE INTO meta(k, v) VALUES (?, ?)", "codec", Nat.show(S.Sdb.codec())],
          ["INSERT OR REPLACE INTO meta(k, v) VALUES (?, ?)", "applied_seq", Nat.show(seq)], ["INSERT OR REPLACE INTO meta(k, v) VALUES (?, ?)", "applied_off", Nat.show(off)],
          ["INSERT OR REPLACE INTO meta(k, v) VALUES (?, ?)", "build", "snap_build"]])
        Write.ok(m, "meta")
        D.Db.close(h)
        IO.print("store.db: " ++ Nat.show(seq) ++ " lines, applied_off " ++ Nat.show(off) ++ ", state seq " ++ Nat.show(M.State.seq(st)))

def Args.copy(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> Args.copy(t)

def Args.home(+xs: List<&2, String>) -> String:
  match xs:
    case h <> _:
      h
    case Nil{}:
      ""

def Args.upto(+xs: List<&2, String>) -> String:
  match xs:
    case _ <> u <> _:
      u
    case _:
      ""

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- A.Argv.args()
    +args : List<&2, String> = Args.copy(xs)
    +home : String = Args.home(args)
    +path : String = home ++ "/events.jsonl"
    sz : U32 <- Rd.size(path)
    +size : Nat = U32.to_nat(sz)
    +u : String = Args.upto(args)
    +end : Nat = Bool.pick(Nat, String.is_empty(u), size, M.Switch.num(u, 0n))
    rm : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("rm", ["-f", home ++ "/store.db", home ++ "/store.db-wal", home ++ "/store.db-shm"], "", 4096, 10000)
    +o : String <- D.Db.open(home ++ "/store.db")
    Write.ok(o, "open")
    +h : String = String.drop(o, 3n)
    s : String <- D.Db.exec(h, S.Sdb.schema())
    Write.ok(s, "schema")
    b : B <- Build.loop(1000000n, h, path, end, size, B{M.State.empty(), 0n, 0n, 1n, Nil{}})
    Build.finish(b, h)
