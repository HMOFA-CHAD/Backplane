import Base
import ../core/mailbody.bend as MB
import ../core/mail.bend as ML
import ../core/ref.bend as R
import ../core/model.bend as M
import ../core/utf8.bend as U
import ./host.bend as H
import ../core/bot.bend as BT

# All public results distinguish an absent body file from a failed operation.
type StoreResult<-A: Data> is Data:
  Stored{value: A}
  Missing{path: String}
  StoreError{path: String, reason: String}

# Base.close cannot report errors; finish owns truncate/write/close together.
# The new open also rejects symlinks and nonregular files (including FIFOs).
def MailFile.open(path: String, write: U32) -> IO(Result<&1, &1, U32 & String, File>):
  import "./effects/mailstore.c"
  import "./effects/mailstore.js"

def MailFile.finish(file: File, cut: U32, text: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effects/mailstore.c"
  import "./effects/mailstore.js"

def MailStore.error(-A: Data, path: String, e: U32 & String) -> StoreResult<A>:
  (code, msg) = e
  StoreError{path, U32.show(code) ++ ": " ++ msg}

def MailStore.absent(-A: Data, missing: Bool, path: String, e: U32 & String) -> StoreResult<A>:
  match missing:
    case True{}: Missing{path}
    case False{}: MailStore.error(A, path, e)

def MailStore.open_error(-A: Data, path: String, e: U32 & String) -> StoreResult<A>:
  (+code, msg) = e
  MailStore.absent(A, U32.is_eq(code, 2), path, (code, msg))

# Backward scan: skip the incomplete suffix without retaining it, then keep
# just the final complete row. IO is 16 KiB per step; no history scan.
type Tail is Data:
  Tail{pos: U32, cut: U32, found: Bool, done: Bool, row: List<&2, U32>}

def Tail.step.nl(nl: Bool, x: U32, t: Tail) -> Tail:
  match nl t:
    case _ Tail{pos, cut, found, True{}, row}: Tail{pos, cut, found, True{}, row}
    case True{} Tail{+pos, _, False{}, False{}, row}: Tail{U32.sub(pos, 1), pos, True{}, False{}, row}
    case True{} Tail{pos, cut, True{}, False{}, row}: Tail{U32.sub(pos, 1), cut, True{}, True{}, row}
    case False{} Tail{pos, cut, False{}, False{}, row}: Tail{U32.sub(pos, 1), cut, False{}, False{}, row}
    case False{} Tail{pos, cut, True{}, False{}, row}: Tail{U32.sub(pos, 1), cut, True{}, False{}, x <> row}

def Tail.step(+x: U32, t: Tail) -> Tail:
  Tail.step.nl(U32.is_eq(x, 10), x, t)

def Tail.bytes(bs: List<&2, U32>, t: Tail) -> Tail:
  match bs:
    case Nil{}: t
    case h <> rest: Tail.bytes(rest, Tail.step(h, t))

def MailStore.tail.chunk(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, t: Tail) -> IO(File & Result<&2, &2, String, Tail>):
  (file, got) = r
  match got:
    case Fail{(code, msg)}: IO.pure(File & Result<&2, &2, String, Tail>, (file, Fail{U32.show(code) ++ ": " ++ msg}))
    case Done{bs}: IO.pure(File & Result<&2, &2, String, Tail>, (file, Done{Tail.bytes(List.reverse(&2, U32, bs), t)}))

def MailStore.tail.next(r: File & Result<&2, &2, String, Tail>, k: File -> Tail -> IO(File & Result<&2, &2, String, Tail>)) -> IO(File & Result<&2, &2, String, Tail>):
  (file, got) = r
  match got:
    case Fail{e}: IO.pure(File & Result<&2, &2, String, Tail>, (file, Fail{e}))
    case Done{t}: k(file, t)

def MailStore.tail(fuel: Nat, file: File, t: Tail) -> IO(File & Result<&2, &2, String, Tail>):
  match fuel t:
    case _ Tail{0, cut, found, done, row}: IO.pure(File & Result<&2, &2, String, Tail>, (file, Done{Tail{0, cut, found, done, row}}))
    case _ Tail{pos, cut, found, True{}, row}: IO.pure(File & Result<&2, &2, String, Tail>, (file, Done{Tail{pos, cut, found, True{}, row}}))
    case 0n _: IO.pure(File & Result<&2, &2, String, Tail>, (file, Fail{"tail scan exhausted"}))
    case 1n+k Tail{+pos, cut, found, False{}, row}:
      do IO<File & Result<&2, &2, String, Tail>>:
        +start : U32 = U32.sub(pos, 16384)
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(file, start, U32.sub(pos, start))
        got : File & Result<&2, &2, String, Tail> <- MailStore.tail.chunk(r, Tail{pos, cut, found, False{}, row})
        MailStore.tail.next(got, f => t => MailStore.tail(k, f, t))

# A syntactically complete but bad row is never repaired away. A suffix
# without a newline is a crashed write and is truncated on the next append.
def MailStore.tail.valid(found: Bool, row: List<&2, U32>) -> Bool:
  match found:
    case False{}: True{}
    case True{}: Maybe.is_some(&2, MB.Body, MB.Body.parse(U.Utf8.decode(row)))

def MailStore.append.finished(path: String, repaired: Bool, r: Result<&1, &1, U32 & String, Unit>) -> StoreResult<Bool>:
  match r:
    case Fail{e}: MailStore.error(Bool, path, e)
    case Done{_}: Stored{repaired}

def MailStore.append.valid(ok: Bool, file: File, path: String, cut: U32, text: String, repaired: Bool) -> IO(StoreResult<Bool>):
  match ok:
    case False{}:
      do IO<StoreResult<Bool>>:
        File.close(file)
        return StoreError{path, "malformed final completed body record"}
    case True{}:
      do IO<StoreResult<Bool>>:
        r : Result<&1, &1, U32 & String, Unit> <- MailFile.finish(file, cut, text)
        return MailStore.append.finished(path, repaired, r)

def MailStore.append.tail(r: File & Result<&2, &2, String, Tail>, path: String, size: U32, text: String) -> IO(StoreResult<Bool>):
  (file, got) = r
  match got:
    case Fail{e}:
      do IO<StoreResult<Bool>>:
        File.close(file)
        return StoreError{path, e}
    case Done{Tail{_, +cut, found, _, row}}:
      MailStore.append.valid(MailStore.tail.valid(found, row), file, path, cut, text, U32.is_ne(cut, size))

def MailStore.append.size(r: File & Result<&1, &1, U32 & String, U32>, path: String, text: String) -> IO(StoreResult<Bool>):
  (file, got) = r
  match got:
    case Fail{e}:
      do IO<StoreResult<Bool>>:
        File.close(file)
        return MailStore.error(Bool, path, e)
    case Done{+size}:
      do IO<StoreResult<Bool>>:
        r : File & Result<&2, &2, String, Tail> <- MailStore.tail(1n+U32.to_nat(size), file, Tail{size, 0, False{}, False{}, Nil{}})
        MailStore.append.tail(r, path, size, text)

def MailStore.append.opened(r: Result<&1, &1, U32 & String, File>, +path: String, text: String) -> IO(StoreResult<Bool>):
  match r:
    case Fail{e}: IO.pure(StoreResult<Bool>, MailStore.error(Bool, path, e))
    case Done{file}:
      do IO<StoreResult<Bool>>:
        r : File & Result<&1, &1, U32 & String, U32> <- File.size(file)
        MailStore.append.size(r, path, text)

def MailStore.append.dir(r: Result<&1, &1, U32 & String, Unit>, +path: String, text: String) -> IO(StoreResult<Bool>):
  match r:
    case Fail{e}: IO.pure(StoreResult<Bool>, MailStore.error(Bool, path, e))
    case Done{_}:
      do IO<StoreResult<Bool>>:
        r : Result<&1, &1, U32 & String, File> <- MailFile.open(path, 1)
        MailStore.append.opened(r, path, text)

def MailStore.append.body(b: Maybe<&2, MB.Body>, +home: String) -> IO(StoreResult<Bool>):
  match b:
    case None{}: IO.pure(StoreResult<Bool>, StoreError{home ++ "/mail", "invalid body"})
    case Some{+b}:
      do IO<StoreResult<Bool>>:
        r : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(home ++ "/mail")
        MailStore.append.dir(r, MB.Body.path(home, ML.Conv.id(MB.Body.conv(b))), MB.Body.line(b))

# Success Bool says whether an incomplete final suffix was discarded.
# Only process-crash consistency: no fsync / power-loss durability promise.
def MailStore.append(home: String, +body: MB.Body) -> IO(StoreResult<Bool>):
  MailStore.append.body(MB.Body.decode(MB.Body.encode(body)), home)

# Only offsets survive the traversal for duplicate detection. A retry reads
# its first row on demand and compares the decoded record exactly, no hashes.
type BodyOffset is Data:
  BodyOffset{at: U32, size: U32}

type Scan is Data:
  Scan{conv: String, before: String, limit: Nat, page: List<&2, MB.Body>, offsets: Map<&2, BodyOffset>, at: U32, stopped: Bool, recovery: Bool, box: List<&2, ML.Box>, changes: List<&2, M.Change>}

def Scan.box(s: Scan) -> ML.Box:
  match s:
    case Scan{_, _, _, _, _, _, _, _, b, _}: Maybe.default(&2, ML.Box, List.head(&2, ML.Box, b), ML.Box.empty())

def Scan.page(s: Scan) -> List<&2, MB.Body>:
  match s:
    case Scan{_, _, _, page, _, _, _, _, _, _}: page

def Scan.changes(s: Scan) -> List<&2, M.Change>:
  match s:
    case Scan{_, _, _, _, _, _, _, _, _, cs}: List.reverse(&2, M.Change, cs)

def Scan.offsets(s: Scan) -> Map<&2, BodyOffset>:
  match s:
    case Scan{_, _, _, _, offsets, _, _, _, _, _}: offsets

def Scan.offset.got(r: Map<&2, BodyOffset> & Maybe<&2, BodyOffset>) -> Maybe<&2, BodyOffset>:
  (_, v) = r
  v

def Scan.offset(s: Scan, id: String) -> Maybe<&2, BodyOffset>:
  Scan.offset.got(Map.pop(&2, BodyOffset, Scan.offsets(s), id))

def Scan.byte_count(text: String, acc: U32) -> U32:
  match text:
    case SNil{}: acc
    case SCon{Chr{+c}, t}:
      Scan.byte_count(t, U32.add(acc, Bool.pick(U32, U32.is_lt(c, 128), 1, Bool.pick(U32, U32.is_lt(c, 2048), 2, Bool.pick(U32, U32.is_lt(c, 65536), 3, 4)))))

def Scan.advance(s: Scan, size: U32) -> Scan:
  match s:
    case Scan{c, b, n, p, os, at, stop, rec, box, cs}: Scan{c, b, n, p, os, U32.add(at, size), stop, rec, box, cs}

def Scan.fold(cs: List<&2, M.Change>, b: ML.Box) -> ML.Box:
  match cs:
    case Nil{}: b
    case M.ConvSet{id, subject, kind, parts, project, tags, at} <> rest:
      Scan.fold(rest, ML.Box.conv_set(b, id, subject, kind, BT.Room.members.of(parts), project, BT.Room.members.of(tags), at))
    case M.MailPosted{id, conv, from, to, kind, ref, want, head, size, at} <> rest:
      Scan.fold(rest, ML.Box.mail(b, ML.Mail{id, conv, from, to, kind, ref, want, head, size, at}))
    case _ <> rest: Scan.fold(rest, b)

def Scan.recovered(+s: Scan, +body: MB.Body) -> Scan:
  match s:
    case Scan{c, b, n, p, os, at, stop, rec, box, cs}:
      +old = Maybe.default(&2, ML.Box, List.head(&2, ML.Box, box), ML.Box.empty())
      +added = MB.Body.recover(body, old)
      Scan{c, b, n, p, os, at, stop, rec, [Scan.fold(added, old)], List.append(&2, M.Change, List.reverse(&2, M.Change, added), cs)}

def Scan.collected(stop: Bool, +s: Scan, body: MB.Body) -> Scan:
  match stop s:
    case True{} _: s
    case False{} Scan{c, +before, +n, page, os, at, _, rec, box, cs}:
      Scan{c, before, n, List.take(&2, MB.Body, body <> page, n), os, at, False{}, rec, box, cs}

def Scan.stopped(s: Scan) -> Bool:
  match s:
    case Scan{_, _, _, _, _, _, stop, _, _, _}: stop

def Scan.cursor(hit: Bool, s: Scan, body: MB.Body) -> Scan:
  match hit s:
    case True{} Scan{c, b, n, page, os, at, _, rec, box, cs}: Scan{c, b, n, page, os, at, True{}, rec, box, cs}
    case False{} +s:
      Scan.collected(Scan.stopped(s), s, body)

def Scan.before(s: Scan) -> String:
  match s:
    case Scan{_, b, _, _, _, _, _, _, _, _}: b

def Scan.apply(rec: Bool, +s: Scan, +body: MB.Body) -> Scan:
  match rec:
    case True{}: Scan.recovered(s, body)
    case False{}:
      Scan.cursor(String.eq(Scan.before(s), ML.Mail.id(MB.Body.mail(body))), s, body)

def Scan.conv(s: Scan) -> String:
  match s:
    case Scan{c, _, _, _, _, _, _, _, _, _}: c

def Scan.unique(s: Scan, +body: MB.Body, size: U32) -> Scan:
  match s:
    case Scan{c, b, n, page, os, +at, stop, +rec, box, cs}:
      Scan.apply(rec, Scan{c, b, n, page, Map.set(&2, BodyOffset, os, ML.Mail.id(MB.Body.mail(body)), BodyOffset{at, size}), U32.add(at, size), stop, rec, box, cs}, body)

def Scan.accept(valid: Bool, s: Scan, body: MB.Body, size: U32) -> Result<&2, &2, String, Scan>:
  match valid:
    case False{}: Fail{"record conversation does not match body filename"}
    case True{}: Done{Scan.unique(s, body, size)}

# Duplicate reads use bounded chunks as well; memory is at most one prior
# duplicate row in addition to the current row and requested page.
def MailStore.range.next(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, +left: U32, at: U32, acc: List<&2, U32>, k: File -> U32 -> U32 -> List<&2, U32> -> IO(File & Result<&2, &2, String, List<&2, U32>>)) -> IO(File & Result<&2, &2, String, List<&2, U32>>):
  (file, got) = r
  match got:
    case Fail{(code, msg)}: IO.pure(File & Result<&2, &2, String, List<&2, U32>>, (file, Fail{U32.show(code) ++ ": " ++ msg}))
    case Done{Nil{}}: IO.pure(File & Result<&2, &2, String, List<&2, U32>>, (file, Fail{"unexpected EOF during duplicate verification"}))
    case Done{+bytes}:
      +n = U32.from_nat(List.length(&2, U32, bytes))
      k(file, U32.sub(left, n), U32.add(at, n), List.append(&2, U32, List.reverse(&2, U32, bytes), acc))

def MailStore.range(fuel: Nat, file: File, left: U32, +at: U32, acc: List<&2, U32>) -> IO(File & Result<&2, &2, String, List<&2, U32>>):
  match fuel left:
    case _ 0: IO.pure(File & Result<&2, &2, String, List<&2, U32>>, (file, Done{List.reverse(&2, U32, acc)}))
    case 0n _: IO.pure(File & Result<&2, &2, String, List<&2, U32>>, (file, Fail{"duplicate range exhausted"}))
    case 1n+k +left:
      do IO<File & Result<&2, &2, String, List<&2, U32>>>:
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(file, at, Bool.pick(U32, U32.is_lt(left, 16384), left, 16384))
        MailStore.range.next(r, left, at, acc, f => l => a => bs => MailStore.range(k, f, l, a, bs))

def MailStore.duplicate.equal(equal: Bool, s: Scan, size: U32) -> Result<&2, &2, String, Scan>:
  match equal:
    case True{}: Done{Scan.advance(s, size)}
    case False{}: Fail{"conflicting duplicate mail id"}

def MailStore.duplicate.body(prior: Maybe<&2, MB.Body>, s: Scan, b: MB.Body, size: U32) -> Result<&2, &2, String, Scan>:
  match prior:
    case None{}: Fail{"invalid original duplicate record"}
    case Some{old}: MailStore.duplicate.equal(String.eq(MB.Body.line(old), MB.Body.line(b)), s, size)

def MailStore.duplicate.got(r: File & Result<&2, &2, String, List<&2, U32>>, s: Scan, b: MB.Body, size: U32) -> IO(File & Result<&2, &2, String, Scan>):
  (file, got) = r
  match got:
    case Fail{e}: IO.pure(File & Result<&2, &2, String, Scan>, (file, Fail{e}))
    case Done{bs}: IO.pure(File & Result<&2, &2, String, Scan>, (file, MailStore.duplicate.body(MB.Body.parse(U.Utf8.decode(bs)), s, b, size)))

def MailStore.record.offset(prior: Maybe<&2, BodyOffset>, file: File, +s: Scan, +b: MB.Body, size: U32) -> IO(File & Result<&2, &2, String, Scan>):
  match prior:
    case None{}: IO.pure(File & Result<&2, &2, String, Scan>, (file, Scan.accept(String.eq(Scan.conv(s), ML.Conv.id(MB.Body.conv(b))), s, b, size)))
    case Some{BodyOffset{at, +len}}:
      do IO<File & Result<&2, &2, String, Scan>>:
        r : File & Result<&2, &2, String, List<&2, U32>> <- MailStore.range(1n+U32.to_nat(len), file, len, at, Nil{})
        MailStore.duplicate.got(r, s, b, size)

def MailStore.record.body(b: Maybe<&2, MB.Body>, file: File, +s: Scan, size: U32) -> IO(File & Result<&2, &2, String, Scan>):
  match b:
    case None{}: IO.pure(File & Result<&2, &2, String, Scan>, (file, Fail{"malformed completed body record (JSON, version or schema)"}))
    case Some{+b}: MailStore.record.offset(Scan.offset(s, ML.Mail.id(MB.Body.mail(b))), file, s, b, size)

def MailStore.lines.next(r: File & Result<&2, &2, String, Scan>, k: File -> Scan -> IO(File & Result<&2, &2, String, Scan>)) -> IO(File & Result<&2, &2, String, Scan>):
  (file, got) = r
  match got:
    case Fail{e}: IO.pure(File & Result<&2, &2, String, Scan>, (file, Fail{e}))
    case Done{s}: k(file, s)

def MailStore.lines(lines: List<&2, String>, file: File, s: Scan) -> IO(File & Result<&2, &2, String, Scan>):
  match lines:
    case Nil{}: IO.pure(File & Result<&2, &2, String, Scan>, (file, Done{s}))
    case +h <> t:
      do IO<File & Result<&2, &2, String, Scan>>:
        r : File & Result<&2, &2, String, Scan> <- MailStore.record.body(MB.Body.parse(h), file, s, U32.add(Scan.byte_count(h, 0), 1))
        MailStore.lines.next(r, f => st => MailStore.lines(t, f, st))

def MailStore.stream.lines(r: File & Result<&2, &2, String, Scan>, carry: U.Lines, k: File -> U.Lines -> Scan -> IO(File & Result<&2, &2, String, Scan>)) -> IO(File & Result<&2, &2, String, Scan>):
  (file, got) = r
  match got:
    case Fail{e}: IO.pure(File & Result<&2, &2, String, Scan>, (file, Fail{e}))
    case Done{s}: k(file, carry, s)

def MailStore.stream.feed(pair: U.Lines & List<&2, String>, file: File, s: Scan, k: File -> U.Lines -> Scan -> IO(File & Result<&2, &2, String, Scan>)) -> IO(File & Result<&2, &2, String, Scan>):
  (carry, lines) = pair
  do IO<File & Result<&2, &2, String, Scan>>:
    r : File & Result<&2, &2, String, Scan> <- MailStore.lines(lines, file, s)
    MailStore.stream.lines(r, carry, k)

def MailStore.stream.got(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, carry: U.Lines, s: Scan, k: File -> U.Lines -> Scan -> IO(File & Result<&2, &2, String, Scan>)) -> IO(File & Result<&2, &2, String, Scan>):
  (file, got) = r
  match got:
    case Fail{(code, msg)}: IO.pure(File & Result<&2, &2, String, Scan>, (file, Fail{U32.show(code) ++ ": " ++ msg}))
    case Done{Nil{}}: IO.pure(File & Result<&2, &2, String, Scan>, (file, Done{s}))
    case Done{bs}: MailStore.stream.feed(U.Lines.feed(carry, bs), file, s, k)

def MailStore.stream(fuel: Nat, file: File, carry: U.Lines, s: Scan) -> IO(File & Result<&2, &2, String, Scan>):
  match fuel:
    case 0n: IO.pure(File & Result<&2, &2, String, Scan>, (file, Fail{"stream exhausted"}))
    case 1n+k:
      do IO<File & Result<&2, &2, String, Scan>>:
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 16384)
        MailStore.stream.got(r, carry, s, f => c => st => MailStore.stream(k, f, c, st))

def MailStore.scan.closed(r: Result<&2, &2, String, Scan>, path: String) -> StoreResult<Scan>:
  match r:
    case Fail{e}: StoreError{path, e}
    case Done{s}: Stored{s}

def MailStore.scan.done(r: File & Result<&2, &2, String, Scan>, path: String) -> IO(StoreResult<Scan>):
  (file, got) = r
  do IO<StoreResult<Scan>>:
    File.close(file)
    return MailStore.scan.closed(got, path)

def MailStore.scan.size(r: File & Result<&1, &1, U32 & String, U32>, path: String, s: Scan) -> IO(StoreResult<Scan>):
  (file, got) = r
  match got:
    case Fail{e}:
      do IO<StoreResult<Scan>>:
        File.close(file)
        return MailStore.error(Scan, path, e)
    case Done{size}:
      do IO<StoreResult<Scan>>:
        r : File & Result<&2, &2, String, Scan> <- MailStore.stream(2n+U32.to_nat(size), file, U.Lines.new(), s)
        MailStore.scan.done(r, path)

def MailStore.scan.opened(r: Result<&1, &1, U32 & String, File>, path: String, s: Scan) -> IO(StoreResult<Scan>):
  match r:
    case Fail{e}: IO.pure(StoreResult<Scan>, MailStore.open_error(Scan, path, e))
    case Done{file}:
      do IO<StoreResult<Scan>>:
        r : File & Result<&1, &1, U32 & String, U32> <- File.size(file)
        MailStore.scan.size(r, path, s)

def MailStore.scan(+path: String, s: Scan) -> IO(StoreResult<Scan>):
  do IO<StoreResult<Scan>>:
    r : Result<&1, &1, U32 & String, File> <- MailFile.open(path, 0)
    MailStore.scan.opened(r, path, s)

def MailStore.read.cursor(ok: Bool, path: String, page: List<&2, MB.Body>) -> StoreResult<List<&2, MB.Body>>:
  match ok:
    case True{}: Stored{page}
    case False{}: StoreError{path, "unknown mail cursor"}

def MailStore.read.result(r: StoreResult<Scan>, path: String) -> StoreResult<List<&2, MB.Body>>:
  match r:
    case StoreError{p, e}: StoreError{p, e}
    case Missing{p}: Missing{p}
    case Stored{+s}:
      MailStore.read.cursor(Bool.or(String.is_empty(Scan.before(s)), Scan.stopped(s)), path, Scan.page(s))

# n=0 does no file IO; page limit is 200. Complete rows are validated even
# beyond the cursor; a single final unterminated suffix is ignored.
def MailStore.read(+home: String, +conv: String, before: String, n: Nat) -> IO(StoreResult<List<&2, MB.Body>>):
  match n:
    case 0n: IO.pure(StoreResult<List<&2, MB.Body>>, Stored{Nil{}})
    case 1n+k:
      do IO<StoreResult<List<&2, MB.Body>>>:
        +path : String = MB.Body.path(home, conv)
        r : StoreResult<Scan> <- MailStore.scan(path, Scan{conv, before, Bool.pick(Nat, Nat.is_lt(k, 200n), 1n+k, 200n), Nil{}, Map.new(&2, BodyOffset), 0, False{}, False{}, Nil{}, Nil{}})
        return MailStore.read.result(r, path)

# Recovery visits only encoded, direct child .jsonl files, one at a time.
# No bodies survive into the returned list; the working Box deduplicates
# headers before the lead's eventual event commit.
def MailStore.recover.file(name: String) -> Bool:
  Bool.and(String.ends_with(name, ".jsonl"), Bool.not(String.contains(name, "/")))

def MailStore.recover.next(r: StoreResult<Scan>, k: ML.Box -> List<&2, M.Change> -> IO(StoreResult<List<&2, M.Change>>)) -> IO(StoreResult<List<&2, M.Change>>):
  match r:
    case StoreError{p, e}: IO.pure(StoreResult<List<&2, M.Change>>, StoreError{p, e})
    case Missing{p}: IO.pure(StoreResult<List<&2, M.Change>>, StoreError{p, "body file vanished during recovery"})
    case Stored{+s}: k(Scan.box(s), Scan.changes(s))

def MailStore.recover.one(yes: Bool, +home: String, +name: String, box: ML.Box, changes: List<&2, M.Change>, k: ML.Box -> List<&2, M.Change> -> IO(StoreResult<List<&2, M.Change>>)) -> IO(StoreResult<List<&2, M.Change>>):
  match yes:
    case False{}: k(box, changes)
    case True{}:
      do IO<StoreResult<List<&2, M.Change>>>:
        r : StoreResult<Scan> <- MailStore.scan(home ++ "/mail/" ++ name, Scan{R.Ref.unpct(String.take(name, Nat.sub(String.length(name), 6n))), "", 0n, Nil{}, Map.new(&2, BodyOffset), 0, False{}, True{}, [box], List.reverse(&2, M.Change, changes)})
        MailStore.recover.next(r, k)

def MailStore.recover.files(names: List<String>, +home: String, box: ML.Box, changes: List<&2, M.Change>) -> IO(StoreResult<List<&2, M.Change>>):
  match names:
    case Nil{}: IO.pure(StoreResult<List<&2, M.Change>>, Stored{changes})
    case +h <> t:
      MailStore.recover.one(MailStore.recover.file(h), home, h, box, changes, b => cs => MailStore.recover.files(t, home, b, cs))

def MailStore.recover.missing(absent: Bool, home: String, e: U32 & String) -> StoreResult<List<&2, M.Change>>:
  match absent:
    case True{}: Stored{Nil{}}
    case False{}: MailStore.error(List<&2, M.Change>, home ++ "/mail", e)

def MailStore.recover.list(r: Result<&1, &1, U32 & String, List<String>>, +home: String, box: ML.Box) -> IO(StoreResult<List<&2, M.Change>>):
  match r:
    case Fail{(+code, msg)}:
      IO.pure(StoreResult<List<&2, M.Change>>, MailStore.recover.missing(U32.is_eq(code, 2), home, (code, msg)))
    case Done{names}: MailStore.recover.files(names, home, box, Nil{})

def MailStore.recover(+home: String, box: ML.Box) -> IO(StoreResult<List<&2, M.Change>>):
  do IO<StoreResult<List<&2, M.Change>>>:
    r : Result<&1, &1, U32 & String, List<String>> <- H.FS.list(home ++ "/mail")
    MailStore.recover.list(r, home, box)
