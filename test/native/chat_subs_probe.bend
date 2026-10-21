import Base
import ./memo_replay.bend as R
import ../index_rename_test.bend as F
import ../../src/core/client.bend as U
import ../../src/core/model.bend as M
import ../../src/core/subs.bend as SB
import ../../src/core/json.bend as J
import ../../src/core/utf8.bend as U8
import ../../src/server/argv.bend as AV
import ../../src/server/perf.bend as P

# Diagnostic only. Fresh production rows are the independent oracle; no
# production layout or invalidation is modified by this experiment.
def sparse(ix: U.SIx) -> U.SIx:
  match ix:
    case U.SIx{_, asks, kids, work}:
      U.SIx{Map.new(&2, List<&2, M.Thread>), asks, kids, work}

def children(on: Bool, +ts: List<&2, M.Task>, +ids: List<&2, String>, +st: M.State, +now: Nat, +ix: U.SIx) -> List<&2, SB.SubRow>:
  match on:
    case False{}: Nil{}
    case True{}:
      List.append(&2, SB.SubRow, SB.Subs.tasks(ts, st, now, ix), SB.Subs.launch.go(List.reverse(&2, String, ids), st, now, ix))

def indexed(+u: U.Ui, +ix: U.SIx) -> List<&2, SB.SubRow>:
  +st = U.Ui.state(u)
  +th = U.Ui.sel(u)
  +now = U.Side.now(u)
  +info = U.Ui.infos(u)
  +ts = U.Tasks.of(st, th)
  +ids = M.Launch.of(st, th)
  SB.Subs.group(List.concat(&2, SB.SubRow, [children(Bool.or(Bool.not(List.is_empty(&2, M.Task, ts)), Bool.not(List.is_empty(&2, String, ids))), ts, ids, st, now, ix),
    SB.Subs.wakes(st, th), SB.Subs.locks.go(M.Locks.names(st), st, th), SB.Subs.agents(st, info, th, now)]), info, th)

def steps(ss: List<&2, SB.SubStep>) -> String:
  match ss:
    case Nil{}: ""
    case SB.SubStep{k, t} <> rest:
      F.Fp.q(k) ++ F.Fp.q(t) ++ steps(rest)

def rows(rs: List<&2, SB.SubRow>) -> String:
  match rs:
    case Nil{}: ""
    case SB.SubRow{k, a, ti, who, word, doing, live, opened, n, ss} <> rest:
      F.Fp.q(k) ++ F.Fp.b(a) ++ F.Fp.q(ti) ++ F.Fp.q(who) ++ F.Fp.q(word) ++ F.Fp.q(doing) ++ F.Fp.b(live) ++ F.Fp.b(opened) ++ Nat.show(n) ++ steps(ss) ++ ";" ++ rows(rest)

type Input is Data:
  Input{us: List<&2, U.Ui>, indexes: List<&2, U.SIx>, expected: String, index_expected: String}

def ui(input: Input) -> U.Ui:
  match input:
    case Input{u <> _, _, _, _}: u
    case _: U.Ui.init(0n)

def ix(input: Input) -> U.SIx:
  match input:
    case Input{_, x <> _, _, _}: x
    case _: U.Side.ix(U.Ui.state(U.Ui.init(0n)))

def expected(input: Input, index_only: Bool) -> String:
  match input:
    case Input{_, _, r, i}: Bool.pick(String, index_only, i, r)

def result(index_only: Bool, +old: Bool, +input: Input) -> String:
  match index_only old:
    case True{} True{}: F.Fp.ix(SB.Subs.index(U.Ui.state(ui(input))))
    case True{} False{}: F.Fp.ix(sparse(ix(input)))
    case False{} True{}: rows(SB.Subs.rows(U.Ui.state(ui(input)), U.Ui.infos(ui(input)), U.Ui.sel(ui(input)), U.Side.now(ui(input))))
    case False{} False{}: rows(indexed(ui(input), ix(input)))

def check(ok: Bool, msg: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "FAIL " ++ msg)

def sample(+input: Input, +index_only: Bool, +old: Bool, +n: Nat) -> IO(Unit):
  do IO<Unit>:
    a : U32 <- P.Perf.us()
    +text : String = result(index_only, old, input)
    +forced : Nat = String.length(text)
    P.Perf.add("probe.forced", U32.from_nat(forced))
    b : U32 <- P.Perf.us()
    check(String.eq(text, expected(input, index_only)), "every field of fresh rows/index")
    IO.print("sample index=" ++ Bool.show(index_only) ++ " old=" ++ Bool.show(old) ++ " n=" ++ Nat.show(n) ++ " us=" ++ U32.show(U32.sub(b, a)) ++ " forced=" ++ Nat.show(forced))

def samples(+fuel: Nat, +input: Input, +index_only: Bool, +old: Bool) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        sample(input, index_only, old, fuel)
        samples(k, input, index_only, old)

def abba(+input: Input, +index_only: Bool) -> IO(Unit):
  do IO<Unit>:
    samples(12n, input, index_only, True{})
    samples(12n, input, index_only, False{})
    samples(12n, input, index_only, False{})
    samples(12n, input, index_only, True{})

def bench(+input: Input) -> IO(Unit):
  do IO<Unit>:
    check(String.eq(result(True{}, True{}, input), result(True{}, False{}, input)), "fresh and supplied phase indexes")
    check(String.eq(result(False{}, True{}, input), result(False{}, False{}, input)), "fresh and supplied complete subagent rows")
    P.Perf.add("probe.warm", U32.from_nat(String.length(expected(input, False{}))))
    P.Perf.add("probe.warm", U32.from_nat(String.length(F.Fp.ix(ix(input)))))
    IO.print("PASS exact fresh rows and phase-index oracle before timing")
    abba(input, True{})
    abba(input, False{})
    IO.print("PASS96samebinary samples; component forcing/serialization included, no whole-app FPS claim")

def prepare(+u: U.Ui) -> Input:
  Input{[u], [U.Side.ix(U.Ui.state(u))], rows(SB.Subs.rows(U.Ui.state(u), U.Ui.infos(u), U.Ui.sel(u), U.Side.now(u))), F.Fp.ix(SB.Subs.index(U.Ui.state(u)))}

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- AV.Argv.args()
    +as : List<&2, String> = R.copy(args)
    bytes : List<&2, U32> <- R.read(R.arg(as, 0n))
    bench(prepare(U.Ui.tick(R.real(R.items(R.lines(U8.Lines.feed(U8.Lines.new(), bytes)), Nil{}), R.arg(as, 1n)), 1792433893n)))
