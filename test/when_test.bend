import Base
import ./check.bend as C
import ../src/core/tz.bend as Z
import ../src/core/when.bend as W

def wp.r(m: Maybe<&2, Nat>) -> String:
  match m:
    case None{}:
      "none"
    case Some{n}:
      Nat.show(n)

def wp.m(m: Maybe<&2, Z.TzRule>, +t: String, +now: Nat) -> String:
  match m:
    case None{}:
      "no rule"
    case Some{r}:
      wp.r(W.When.parse(t, now, r))

# the instant a phrase means in Helsinki, or none
def wp(t: String, now: Nat) -> String:
  wp.m(Z.Tz.parse("EET-2EEST,M3.5.0/3,M10.5.0/4"), t, now)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("parse 2026-10-14T12:00:00+03:00 @1791957600", wp("2026-10-14T12:00:00+03:00", 1791957600n), "1791968400")
    C.Check.str("parse 2026-10-14T09:00Z @1791957600", wp("2026-10-14T09:00Z", 1791957600n), "1791968400")
    C.Check.str("parse 2026-10-14 15:00+0300 @1791957600", wp("2026-10-14 15:00+0300", 1791957600n), "1791979200")
    C.Check.str("parse 2026-10-14T15:00:30-05:00 @1791957600", wp("2026-10-14T15:00:30-05:00", 1791957600n), "1792008030")
    C.Check.str("parse 2026-10-14T18:00 @1791957600", wp("2026-10-14T18:00", 1791957600n), "1791990000")
    C.Check.str("parse 2026-10-14 18:00 @1791957600", wp("2026-10-14 18:00", 1791957600n), "1791990000")
    C.Check.str("parse 2026-10-15 @1791957600", wp("2026-10-15", 1791957600n), "1792044000")
    C.Check.str("parse 2026-10-13T09:00 @1791957600", wp("2026-10-13T09:00", 1791957600n), "none")
    C.Check.str("parse 2026-10-14T05:00Z @1791957600", wp("2026-10-14T05:00Z", 1791957600n), "none")
    C.Check.str("parse 2026-02-30 @1791957600", wp("2026-02-30", 1791957600n), "none")
    C.Check.str("parse in 20m @1791957600", wp("in 20m", 1791957600n), "1791958800")
    C.Check.str("parse in 2h @1791957600", wp("in 2h", 1791957600n), "1791964800")
    C.Check.str("parse in 1h30m @1791957600", wp("in 1h30m", 1791957600n), "1791963000")
    C.Check.str("parse in 3d @1791957600", wp("in 3d", 1791957600n), "1792216800")
    C.Check.str("parse in 90 minutes @1791957600", wp("in 90 minutes", 1791957600n), "1791963000")
    C.Check.str("parse in 2 hours @1791957600", wp("in 2 hours", 1791957600n), "1791964800")
    C.Check.str("parse in 1 day @1791957600", wp("in 1 day", 1791957600n), "1792044000")
    C.Check.str("parse in 0m @1791957600", wp("in 0m", 1791957600n), "none")
    C.Check.str("parse in @1791957600", wp("in", 1791957600n), "none")
    C.Check.str("parse in xyz @1791957600", wp("in xyz", 1791957600n), "none")
    C.Check.str("parse in 5 @1791957600", wp("in 5", 1791957600n), "none")
    C.Check.str("parse today 17:30 @1791957600", wp("today 17:30", 1791957600n), "1791988200")
    C.Check.str("parse today 08:00 @1791957600", wp("today 08:00", 1791957600n), "none")
    C.Check.str("parse tomorrow 9am @1791957600", wp("tomorrow 9am", 1791957600n), "1792044000")
    C.Check.str("parse tomorrow 09:00 @1791957600", wp("tomorrow 09:00", 1791957600n), "1792044000")
    C.Check.str("parse tomorrow @1791957600", wp("tomorrow", 1791957600n), "1792044000")
    C.Check.str("parse monday 9am @1791957600", wp("monday 9am", 1791957600n), "1792389600")
    C.Check.str("parse wed 18:00 @1791957600", wp("wed 18:00", 1791957600n), "1791990000")
    C.Check.str("parse wed 8am @1791957600", wp("wed 8am", 1791957600n), "1792558800")
    C.Check.str("parse mon 09:30 @1791957600", wp("mon 09:30", 1791957600n), "1792391400")
    C.Check.str("parse Friday @1791957600", wp("Friday", 1791957600n), "1792130400")
    C.Check.str("parse 9am @1791957600", wp("9am", 1791957600n), "1792044000")
    C.Check.str("parse 21:00 @1791957600", wp("21:00", 1791957600n), "1792000800")
    C.Check.str("parse 9:30pm @1791957600", wp("9:30pm", 1791957600n), "1792002600")
    C.Check.str("parse 12am @1791957600", wp("12am", 1791957600n), "1792011600")
    C.Check.str("parse 12pm @1791957600", wp("12pm", 1791957600n), "1791968400")
    C.Check.str("parse   Tomorrow   9AM  @1791957600", wp("  Tomorrow   9AM ", 1791957600n), "1792044000")
    C.Check.str("parse tomorrow at 9am @1791957600", wp("tomorrow at 9am", 1791957600n), "1792044000")
    C.Check.str("parse tomorrow 9am @1792843200", wp("tomorrow 9am", 1792843200n), "1792911600")
    C.Check.str("parse tomorrow 03:30 @1792843200", wp("tomorrow 03:30", 1792843200n), "1792888200")
    C.Check.str("parse tomorrow 03:30 @1774699200", wp("tomorrow 03:30", 1774699200n), "1774747800")
    C.Check.str("parse  @1791957600", wp("", 1791957600n), "none")
    C.Check.str("parse banana @1791957600", wp("banana", 1791957600n), "none")
    C.Check.str("parse tomorrow banana @1791957600", wp("tomorrow banana", 1791957600n), "none")
    C.Check.str("parse 25:00 @1791957600", wp("25:00", 1791957600n), "none")
    C.Check.str("parse 9 @1791957600", wp("9", 1791957600n), "none")
    C.Check.str("parse 13pm @1791957600", wp("13pm", 1791957600n), "none")
    C.Check.str("parse today 9am tomorrow @1791957600", wp("today 9am tomorrow", 1791957600n), "none")
