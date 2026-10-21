import Base
import ../src/core/telemetry.bend as T
import ../src/server/telemetry.bend as TI
import ./check.bend as C

def Activity.state() -> T.TmState:
  T.TmState{"7d0c2f6e-3b1a-4f7e-9a51-2c8e0d4b6f10", "0.11.3", "", True{}, "0", Nil{}, 0n, 0n, True{}}

def Activity.view(share: Bool, asked: Bool, day: String) -> T.TmView:
  T.TmView{share, asked, "0", "0.11.3", "release", "linux", "x64", day, 100n}

def Activity.state.of(p: T.TmPlan) -> T.TmState:
  match p:
    case T.TmPlan{st, _}: st

def Activity.plan(st: T.TmState, v: T.TmView, action: String) -> T.TmState:
  Activity.state.of(T.Tm.plan.activity(st, v, "00000000-0000-4000-8000-000000000000", action))

def Activity.run(st: T.TmState, +day: String, action: String) -> T.TmState:
  Activity.plan(st, Activity.view(True{}, True{}, day), action)

def Activity.count(st: T.TmState) -> String:
  Nat.show(List.length(&2, T.TmEv, List.filter(~T.TmEv, ~(e => String.eq(T.TmEv.e(e), "active")), T.TmState.queue(st))))

def Activity.first() -> T.TmState:
  Activity.run(Activity.state(), "2026-10-20", "2026-10-20")

def Activity.delivered(+st: T.TmState) -> T.TmState:
  T.Tm.sent(st, T.TmState.queue(st), 202n, 0n, 100n)

def Activity.cfg() -> List<&2, TI.TmCfg>:
  TI.Tio.plat.cfg(("linux", "x64"), True{}, False{}, "", "", "", 0n, "release")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("idle initial worker", Activity.count(Activity.run(Activity.state(), "2026-10-20", "")), "0")
    C.Check.str("idle headless day rollover", Activity.count(Activity.run(Activity.run(Activity.state(), "2026-10-20", ""), "2026-10-21", "")), "0")
    C.Check.str("real eligible action", Activity.count(Activity.first()), "1")
    C.Check.str("repeat action same day after delivery", Activity.count(Activity.run(Activity.delivered(Activity.first()), "2026-10-20", "2026-10-20")), "0")
    C.Check.str("idle after real action next day", Activity.count(Activity.run(Activity.delivered(Activity.first()), "2026-10-21", "")), "0")
    C.Check.str("next day eligible action", Activity.count(Activity.run(Activity.delivered(Activity.first()), "2026-10-21", "2026-10-21")), "1")
    C.Check.str("action before midnight retains actual day", T.TmState.today(Activity.run(Activity.state(), "2026-10-21", "2026-10-20")), "2026-10-20")
    C.Check.str("opted out action", Activity.count(Activity.plan(Activity.state(), Activity.view(False{}, True{}, "2026-10-20"), "2026-10-20")), "0")
    C.Check.str("unanswered action", Activity.count(Activity.plan(Activity.state(), Activity.view(True{}, False{}, "2026-10-20"), "2026-10-20")), "0")
    C.Check.str("invalid action date", Activity.count(Activity.run(Activity.state(), "2026-10-20", "private-payload")), "0")
    C.Check.str("new config has no activity", TI.Tio.human.day(Activity.cfg()), "")
    C.Check.str("disabled config ignores action", TI.Tio.human.day(TI.Tio.human(TI.Tio.empty(False{}), 86400n)), "")
    C.Check.str("action stores UTC day only", TI.Tio.human.day(TI.Tio.human(Activity.cfg(), 86400n)), "1970-01-02")
    C.Check.str("busy and done retain later activity", TI.Tio.human.day(TI.Tio.done(TI.Tio.human(TI.Tio.busy(Activity.cfg(), 1n), 86400n), 1n, "")), "1970-01-02")
    C.Check.str("opt-out scrub clears action", TI.Tio.human.day(TI.Tio.id.clear(TI.Tio.human(Activity.cfg(), 86400n))), "")
    C.Check.str("privacy change clears action before id exists", TI.Tio.human.day(TI.Tio.human.clear(TI.Tio.human(Activity.cfg(), 86400n))), "")
    C.Check.str("state remains decodable", T.Tm.state.json(T.Tm.state.parse(T.Tm.state.json(Activity.first()))), T.Tm.state.json(Activity.first()))
    C.Check.str("activity sends action day", T.Tm.body(100n, "0123456789abcdef", T.TmState.queue(Activity.first())), "{\"v\":1,\"ts\":100,\"nonce\":\"0123456789abcdef\",\"events\":[{\"e\":\"active\",\"day\":\"2026-10-20\",\"id\":\"7d0c2f6e-3b1a-4f7e-9a51-2c8e0d4b6f10\",\"share\":true,\"ver\":\"0.11.3\",\"ch\":\"release\",\"os\":\"linux\",\"arch\":\"x64\"}]}")
