import Base
import ./model.bend as M
import ./cron.bend as CR
import ./tz.bend as TZ

# Times people write
# ------------------
# When.parse reads a moment from a phrase, in the zone `rule`, strictly after
# `now` (None otherwise): ISO 8601 with or without an offset ("2026-10-14T09:00+03:00",
# "2026-10-14 09:00", "2026-10-14" = 09:00), "in 20m", "in 1h30m", "in 90 minutes",
# "in 3d", "today 17:30", "tomorrow 9am", "monday 09:00", "mon 9:30pm", a bare
# time ("9am", "21:00": today if still ahead, else tomorrow). A day word
# with no time means 09:00.

type UK is Data:
  UK{k: String, v: Nat}

# a wall time and, when the text gave one, its offset
type WT is Data:
  WT{wall: Nat, has: Bool, east: Bool, off: Nat}

type WS is Data:
  WS{secs: Nat, rest: String}

type WOff is Data:
  WOff{has: Bool, east: Bool, off: Nat}

# runs of digits and of letters
type RS is Data:
  RS{acc: List<&2, String>, cur: String, kind: Nat, bad: Bool}

def When.text() -> String:
  "I can read: 2026-10-14T09:00+03:00, 2026-10-14 09:00, in 20m, in 1h30m, in 3d, today 17:30, tomorrow 9am, monday 09:00, or just 9am."

def When.default() -> Nat:
  32400n

# exactly k digits
def When.n.k(ok: Bool, s: String) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      CR.Cron.num(s)
    case False{}:
      None{}

def When.n(+s: String, +k: Nat) -> Maybe<&2, Nat>:
  When.n.k(Nat.is_eq(String.length(s), k), s)

def When.char.at.k(m: Maybe<&2, Char>, +c: Char) -> Bool:
  match m:
    case Some{x}:
      Char.is_eq(x, c)
    case None{}:
      False{}

def When.char.at(+s: String, +i: Nat, +c: Char) -> Bool:
  When.char.at.k(String.get(s, i), c)

def When.date.same(a: CR.Ymd, +y: Nat, +m: Nat, +d: Nat) -> Bool:
  match a:
    case CR.Ymd{ay, am, ad}:
      Bool.and(Nat.is_eq(ay, y), Bool.and(Nat.is_eq(am, m), Nat.is_eq(ad, d)))

def When.date.real(ok: Bool, +day: Nat) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      Some{Nat.mul(day, 86400n)}
    case False{}:
      None{}

def When.date.ok(ok: Bool, +y: Nat, +m: Nat, +d: Nat) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      When.date.real(When.date.same(CR.Cron.civil(CR.Cron.days(y, m, d)), y, m, d), CR.Cron.days(y, m, d))
    case False{}:
      None{}

# Date: YYYY-MM-DD as the wall seconds of its midnight
def When.date.k(y: Maybe<&2, Nat>, m: Maybe<&2, Nat>, d: Maybe<&2, Nat>, dashes: Bool) -> Maybe<&2, Nat>:
  match y m d:
    case Some{+y} Some{+m} Some{+d}:
      When.date.ok(Bool.and(dashes, Bool.and(Bool.and(Nat.is_ge(m, 1n), Nat.is_le(m, 12n)), Bool.and(Nat.is_ge(d, 1n), Nat.is_le(d, 31n)))), y, m, d)
    case _ _ _:
      None{}

def When.date(+j: String) -> Maybe<&2, Nat>:
  When.date.k(When.n(String.take(j, 4n), 4n), When.n(String.take(String.drop(j, 5n), 2n), 2n), When.n(String.take(String.drop(j, 8n), 2n), 2n),
    Bool.and(When.char.at(j, 4n, '-'), Bool.and(When.char.at(j, 7n, '-'), Nat.is_eq(String.length(j), 10n))))

def When.sec.ok(ok: Bool, secs: Nat, rest: String) -> Maybe<&2, WS>:
  match ok:
    case True{}:
      Some{WS{secs, rest}}
    case False{}:
      None{}

def When.sec.v(s: Maybe<&2, Nat>, rest: String, +secs: Nat) -> Maybe<&2, WS>:
  match s:
    case Some{+s}:
      When.sec.ok(Nat.is_le(s, 59n), Nat.add(secs, s), rest)
    case None{}:
      None{}

# seconds after HH:MM, and what follows
def When.sec.k(colon: Bool, c: Char, +t: String, +secs: Nat) -> Maybe<&2, WS>:
  match colon:
    case True{}:
      When.sec.v(When.n(String.take(t, 2n), 2n), String.drop(t, 2n), secs)
    case False{}:
      Some{WS{secs, SCon{c, t}}}

def When.sec(tail: String, +secs: Nat) -> Maybe<&2, WS>:
  match tail:
    case SNil{}:
      Some{WS{secs, ""}}
    case SCon{+c, t}:
      When.sec.k(Char.is_eq(c, ':'), c, t, secs)

def When.strip(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+c, +t}:
      Bool.pick(String, Char.is_eq(c, ':'), When.strip(t), SCon{c, When.strip(t)})

def When.off.ok(ok: Bool, neg: Bool, off: Nat) -> Maybe<&2, WOff>:
  match ok:
    case True{}:
      Some{WOff{True{}, Bool.not(neg), off}}
    case False{}:
      None{}

def When.off.v(neg: Bool, +len: Nat, h: Maybe<&2, Nat>, m: Maybe<&2, Nat>) -> Maybe<&2, WOff>:
  match h m:
    case Some{+h} Some{+m}:
      When.off.ok(Bool.and(Nat.is_eq(len, 4n), Bool.and(Nat.is_le(h, 23n), Nat.is_le(m, 59n))), neg, Nat.add(Nat.mul(h, 3600n), Nat.mul(m, 60n)))
    case Some{+h} None{}:
      When.off.ok(Bool.and(Nat.is_eq(len, 2n), Nat.is_le(h, 23n)), neg, Nat.mul(h, 3600n))
    case _ _:
      None{}

def When.off.hm(neg: Bool, +d: String) -> Maybe<&2, WOff>:
  When.off.v(neg, String.length(d), When.n(String.take(d, 2n), 2n), When.n(String.take(String.drop(d, 2n), 2n), 2n))

# an offset: nothing, z, or +hh[:]mm / +hh
def When.off.sign(neg: Bool, t: String) -> Maybe<&2, WOff>:
  When.off.hm(neg, When.strip(t))

def When.off.k(z: Bool, plus: Bool, minus: Bool, t: String) -> Maybe<&2, WOff>:
  match z plus minus:
    case True{} _ _:
      Bool.pick(Maybe<&2, WOff>, String.is_empty(t), Some{WOff{True{}, True{}, 0n}}, None{})
    case False{} True{} _:
      When.off.sign(False{}, t)
    case False{} False{} True{}:
      When.off.sign(True{}, t)
    case False{} False{} False{}:
      None{}

def When.off(tail: String) -> Maybe<&2, WOff>:
  match tail:
    case SNil{}:
      Some{WOff{False{}, True{}, 0n}}
    case SCon{+c, t}:
      When.off.k(Char.is_eq(c, 'z'), Char.is_eq(c, '+'), Char.is_eq(c, '-'), t)

def When.wt(day: Nat, secs: Nat, o: Maybe<&2, WOff>) -> Maybe<&2, WT>:
  match o:
    case Some{WOff{has, east, off}}:
      Some{WT{Nat.add(day, secs), has, east, off}}
    case None{}:
      None{}

def When.clock.f(ws: Maybe<&2, WS>, +day: Nat) -> Maybe<&2, WT>:
  match ws:
    case Some{WS{secs, rest}}:
      When.wt(day, secs, When.off(rest))
    case None{}:
      None{}

def When.clock.s(ok: Bool, +day: Nat, +secs: Nat, tail: String) -> Maybe<&2, WT>:
  match ok:
    case True{}:
      When.clock.f(When.sec(tail, secs), day)
    case False{}:
      None{}

def When.clock.k(h: Maybe<&2, Nat>, m: Maybe<&2, Nat>, colon: Bool, +day: Nat, tail: String) -> Maybe<&2, WT>:
  match h m:
    case Some{+h} Some{+m}:
      When.clock.s(Bool.and(colon, Bool.and(Nat.is_le(h, 23n), Nat.is_le(m, 59n))), day, Nat.add(Nat.mul(h, 3600n), Nat.mul(m, 60n)), tail)
    case _ _:
      None{}

def When.clock(+day: Nat, +t: String) -> Maybe<&2, WT>:
  When.clock.k(When.n(String.take(t, 2n), 2n), When.n(String.take(String.drop(t, 3n), 2n), 2n), When.char.at(t, 2n, ':'), day, String.drop(t, 5n))

def When.iso.t2(ist: Bool, +day: Nat, t: String) -> Maybe<&2, WT>:
  match ist:
    case True{}:
      When.clock(day, t)
    case False{}:
      None{}

def When.iso.t(+day: Nat, rest: String) -> Maybe<&2, WT>:
  match rest:
    case SNil{}:
      Some{WT{Nat.add(day, When.default()), False{}, True{}, 0n}}
    case SCon{+c, t}:
      When.iso.t2(Char.is_eq(c, 't'), day, t)

def When.iso.k(d: Maybe<&2, Nat>, rest: String) -> Maybe<&2, WT>:
  match d:
    case Some{+day}:
      When.iso.t(day, rest)
    case None{}:
      None{}

# the joined words of an ISO phrase (date, optional "t" or space, time, offset)
def When.iso(+j: String) -> Maybe<&2, WT>:
  When.iso.k(When.date(String.take(j, 10n)), String.drop(j, 10n))

def When.inst.k(has: Bool, east: Bool, off: Nat, +wall: Nat, rule: TZ.TzRule) -> Nat:
  match has:
    case True{}:
      M.Snooze.utc(east, wall, off)
    case False{}:
      TZ.Tz.at(rule, wall)

# a moment from its wall time
def When.inst(w: WT, rule: TZ.TzRule) -> Nat:
  match w:
    case WT{+wall, has, east, off}:
      When.inst.k(has, east, off, wall, rule)

# Relative: "in 20m", "in 1h30m", "in 90 minutes"
def When.units() -> List<&2, UK>:
  [UK{"s", 1n}, UK{"sec", 1n}, UK{"secs", 1n}, UK{"second", 1n}, UK{"seconds", 1n},
   UK{"m", 60n}, UK{"min", 60n}, UK{"mins", 60n}, UK{"minute", 60n}, UK{"minutes", 60n},
   UK{"h", 3600n}, UK{"hr", 3600n}, UK{"hrs", 3600n}, UK{"hour", 3600n}, UK{"hours", 3600n},
   UK{"d", 86400n}, UK{"day", 86400n}, UK{"days", 86400n},
   UK{"w", 604800n}, UK{"week", 604800n}, UK{"weeks", 604800n}]

def When.days() -> List<&2, UK>:
  [UK{"sun", 0n}, UK{"sunday", 0n}, UK{"mon", 1n}, UK{"monday", 1n}, UK{"tue", 2n}, UK{"tues", 2n}, UK{"tuesday", 2n},
   UK{"wed", 3n}, UK{"wednesday", 3n}, UK{"thu", 4n}, UK{"thur", 4n}, UK{"thurs", 4n}, UK{"thursday", 4n},
   UK{"fri", 5n}, UK{"friday", 5n}, UK{"sat", 6n}, UK{"saturday", 6n},
   UK{"today", 100n}, UK{"tomorrow", 101n}]

def When.find.k(hit: Bool, v: Nat, rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest

def When.find(xs: List<&2, UK>, +k: String) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}:
      None{}
    case UK{+n, v} <> t:
      When.find.k(String.eq(n, k), v, When.find(t, k))

def When.run.flush(st: RS) -> RS:
  match st:
    case RS{+acc, +cur, kind, +bad}:
      Bool.pick(RS, Nat.is_eq(kind, 0n), RS{acc, cur, 0n, bad}, RS{cur <> acc, "", 0n, bad})

def When.run.add.n(st: RS, +c: Char, kind: Nat) -> RS:
  match st:
    case RS{acc, cur, k, bad}:
      RS{acc, SCon{c, SNil{}}, kind, bad}

def When.run.add(st: RS, +c: Char, +kind: Nat) -> RS:
  match st:
    case RS{+acc, +cur, +k, +bad}:
      Bool.pick(RS, Nat.is_eq(k, kind), RS{acc, cur ++ SCon{c, SNil{}}, kind, bad}, When.run.add.n(When.run.flush(RS{acc, cur, k, bad}), c, kind))

def When.run.bad(st: RS) -> RS:
  match st:
    case RS{acc, cur, k, bad}:
      RS{acc, cur, k, True{}}

def When.run.step(+st: RS, +c: Char) -> RS:
  Bool.pick(RS, Char.is_digit(c), When.run.add(st, c, 1n), Bool.pick(RS, Char.is_alpha(c), When.run.add(st, c, 2n), When.run.bad(st)))

def When.run.go(s: String, st: RS) -> RS:
  match s:
    case SNil{}:
      st
    case SCon{+c, t}:
      When.run.go(t, When.run.step(st, c))

def When.run.fin(st: RS) -> Maybe<&2, List<&2, String>>:
  match st:
    case RS{acc, cur, kind, bad}:
      Bool.pick(Maybe<&2, List<&2, String>>, bad, None{}, Some{List.reverse(&2, String, acc)})

def When.runs(s: String) -> Maybe<&2, List<&2, String>>:
  When.run.fin(When.run.flush(When.run.go(s, RS{Nil{}, "", 0n, False{}})))

def When.pair.k(acc: Maybe<&2, Nat>, n: Maybe<&2, Nat>, u: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match acc n u:
    case Some{+a} Some{+n} Some{+u}:
      Some{Nat.add(a, Nat.mul(n, u))}
    case _ _ _:
      None{}

def When.pair.step(acc: Maybe<&2, Nat>, n: String, u: String) -> Maybe<&2, Nat>:
  When.pair.k(acc, CR.Cron.num(n), When.find(When.units(), u))

def When.pairs(ts: List<&2, String>, acc: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match ts:
    case Nil{}:
      acc
    case _ <> Nil{}:
      None{}
    case n <> u <> rest:
      When.pairs(rest, When.pair.step(acc, n, u))

def When.rel.k(ts: Maybe<&2, List<&2, String>>) -> Maybe<&2, Nat>:
  match ts:
    case Some{xs}:
      When.pairs(xs, Some{0n})
    case None{}:
      None{}

# seconds from "20m", "1h30m", "90minutes" (words joined)
def When.rel(ws: List<&2, String>) -> Maybe<&2, Nat>:
  When.rel.k(When.runs(String.concat(ws)))

def When.hm.ok(a: Bool, b: Bool, +h: Nat, +m: Nat) -> Maybe<&2, Nat>:
  match a b:
    case True{} True{}:
      Some{Nat.add(Nat.mul(h, 3600n), Nat.mul(m, 60n))}
    case _ _:
      None{}

# Day words and clock times
# -------------------------

# "9", "9:30", "9am", "9:30pm", "21:00" as seconds into the day
def When.hm.v(h: Maybe<&2, Nat>, m: Maybe<&2, Nat>, pm: Bool, +ampm: Bool) -> Maybe<&2, Nat>:
  match h m:
    case Some{+h} Some{+m}:
      When.hm.ok(Bool.pick(Bool, ampm, Bool.and(Nat.is_ge(h, 1n), Nat.is_le(h, 12n)), Nat.is_le(h, 23n)), Nat.is_le(m, 59n), Bool.pick(Nat, ampm, Nat.add(Nat.mod(h, 12n), Bool.pick(Nat, pm, 12n, 0n)), h), m)
    case _ _:
      None{}

def When.hm.min(+m: String) -> Maybe<&2, Nat>:
  Bool.pick(Maybe<&2, Nat>, String.is_empty(m), Some{0n}, When.n(m, 2n))

def When.hm.t(h: String, m: String, pm: Bool, ampm: Bool) -> Maybe<&2, Nat>:
  When.hm.v(CR.Cron.num(h), When.hm.min(m), pm, ampm)

def When.hm.split(ps: List<&2, String>, pm: Bool, ampm: Bool) -> Maybe<&2, Nat>:
  match ps:
    case h <> Nil{}:
      When.hm.t(h, "", pm, ampm)
    case h <> m <> Nil{}:
      When.hm.t(h, m, pm, ampm)
    case _:
      None{}

def When.hm.suffix(+am: Bool, +pm: Bool, +w: String) -> Maybe<&2, Nat>:
  When.hm.split(String.split(Bool.pick(String, Bool.or(am, pm), String.take(w, Nat.sub(String.length(w), 2n)), w), ':'), pm, Bool.or(am, pm))

def When.hm(+w: String) -> Maybe<&2, Nat>:
  When.hm.suffix(String.ends_with(w, "am"), String.ends_with(w, "pm"), w)

def When.hm.ex(ok: Bool, +w: String) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      When.hm(w)
    case False{}:
      None{}

# a time with no day word must show it is a time: a colon or am/pm
def When.hm.explicit(+w: String) -> Maybe<&2, Nat>:
  When.hm.ex(Bool.or(String.contains(w, ":"), Bool.or(String.ends_with(w, "am"), String.ends_with(w, "pm"))), w)

# the day of week (0 = Sunday) a wall time falls on
def When.wday(+wall: Nat) -> Nat:
  TZ.Tz.wday(Nat.div(wall, 86400n))

def When.delta(+code: Nat, +d0: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(code, 100n), Bool.pick(Nat, Nat.is_eq(code, 101n), 1n, 0n), Nat.mod(Nat.add(Nat.sub(Nat.add(code, 7n), TZ.Tz.wday(d0)), 0n), 7n))

def When.at.next(bare: Bool, week: Bool, rule: TZ.TzRule, +secs: Nat, +now: Nat, +day: Nat) -> Maybe<&2, Nat>:
  match bare week:
    case True{} _:
      Some{TZ.Tz.at(rule, Nat.add(Nat.mul(Nat.add(day, 1n), 86400n), secs))}
    case False{} True{}:
      Some{TZ.Tz.at(rule, Nat.add(Nat.mul(Nat.add(day, 7n), 86400n), secs))}
    case False{} False{}:
      None{}

# the time was past today: a bare time or a weekday goes on (a day later, a week later)
def When.at.later(+code: Nat, rule: TZ.TzRule, +secs: Nat, +now: Nat, +day: Nat) -> Maybe<&2, Nat>:
  When.at.next(Nat.is_eq(code, 102n), Nat.is_lt(code, 7n), rule, secs, now, day)

def When.at.pick(ahead: Bool, rule: TZ.TzRule, +code: Nat, +secs: Nat, +now: Nat, +day: Nat) -> Maybe<&2, Nat>:
  match ahead:
    case True{}:
      Some{TZ.Tz.at(rule, Nat.add(Nat.mul(day, 86400n), secs))}
    case False{}:
      When.at.later(code, rule, secs, now, day)

def When.at.first(+rule: TZ.TzRule, +code: Nat, +secs: Nat, +now: Nat, +day: Nat) -> Maybe<&2, Nat>:
  When.at.pick(Nat.is_gt(TZ.Tz.at(rule, Nat.add(Nat.mul(day, 86400n), secs)), now), rule, code, secs, now, day)

def When.at.try(rule: TZ.TzRule, +code: Nat, +secs: Nat, +now: Nat, +d0: Nat) -> Maybe<&2, Nat>:
  When.at.first(rule, code, secs, now, Nat.add(d0, When.delta(code, d0)))

# which day: 0..6 a weekday, 100 today, 101 tomorrow, 102 no day word
def When.at.day(+rule: TZ.TzRule, +code: Nat, +secs: Nat, +now: Nat) -> Maybe<&2, Nat>:
  When.at.try(rule, code, secs, now, Nat.div(TZ.Tz.wall(rule, now), 86400n))

def When.day.go(code: Maybe<&2, Nat>, tm: Maybe<&2, Nat>, rule: TZ.TzRule, +now: Nat) -> Maybe<&2, Nat>:
  match code tm:
    case Some{+c} Some{+t}:
      When.at.day(rule, c, t, now)
    case _ _:
      None{}

def When.day.one(code: Maybe<&2, Nat>, w: String, rule: TZ.TzRule, +now: Nat) -> Maybe<&2, Nat>:
  match code:
    case Some{c}:
      When.at.day(rule, c, When.default(), now)
    case None{}:
      When.day.go(Some{102n}, When.hm.explicit(w), rule, now)

# the words after any "at": [day], [day time] or [time]
def When.day(ws: List<&2, String>, rule: TZ.TzRule, +now: Nat) -> Maybe<&2, Nat>:
  match ws:
    case +w <> Nil{}:
      When.day.one(When.find(When.days(), w), w, rule, now)
    case d <> t <> Nil{}:
      When.day.go(When.find(When.days(), d), When.hm(t), rule, now)
    case _:
      None{}

def When.drop.at(ws: List<&2, String>) -> List<&2, String>:
  match ws:
    case Nil{}:
      Nil{}
    case +w <> +t:
      Bool.pick(List<&2, String>, String.eq(w, "at"), When.drop.at(t), w <> When.drop.at(t))

# Top
# ---

def When.after(m: Maybe<&2, Nat>, +now: Nat) -> Maybe<&2, Nat>:
  match m:
    case Some{+t}:
      Bool.pick(Maybe<&2, Nat>, Nat.is_gt(t, now), Some{t}, None{})
    case None{}:
      None{}

def When.in(m: Maybe<&2, Nat>, +now: Nat) -> Maybe<&2, Nat>:
  match m:
    case Some{+s}:
      Bool.pick(Maybe<&2, Nat>, Nat.is_gt(s, 0n), Some{Nat.add(now, s)}, None{})
    case None{}:
      None{}

def When.iso.m(w: Maybe<&2, WT>, rule: TZ.TzRule) -> Maybe<&2, Nat>:
  match w:
    case Some{x}:
      Some{When.inst(x, rule)}
    case None{}:
      None{}

def When.kind(isin: Bool, isiso: Bool, ws: List<&2, String>, t: List<&2, String>, rule: TZ.TzRule, +now: Nat) -> Maybe<&2, Nat>:
  match isin isiso:
    case True{} _:
      When.in(When.rel(t), now)
    case False{} True{}:
      When.iso.m(When.iso(String.join(ws, "t")), rule)
    case False{} False{}:
      When.day(When.drop.at(ws), rule, now)

def When.iso.like(+h: String) -> Bool:
  Bool.and(Nat.is_ge(String.length(h), 10n), Bool.and(When.char.at(h, 4n, '-'), When.char.at(h, 7n, '-')))

def When.top(ws: List<&2, String>, rule: TZ.TzRule, +now: Nat) -> Maybe<&2, Nat>:
  match ws:
    case Nil{}:
      None{}
    case +h <> +t:
      When.kind(String.eq(h, "in"), When.iso.like(h), h <> t, t, rule, now)

def When.parse.k(ok: Bool, text: String, rule: TZ.TzRule, +now: Nat) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      When.after(When.top(CR.Cron.words(String.to_lower(String.trim(text))), rule, now), now)
    case False{}:
      None{}

# a moment strictly after `now` from a phrase, else None
def When.parse(+text: String, +now: Nat, rule: TZ.TzRule) -> Maybe<&2, Nat>:
  When.parse.k(Nat.is_le(String.length(text), 80n), text, rule, now)

# a phrase that needs no zone to read: a duration ("in 20m") or an ISO time
# with its own offset ("...T09:00Z", "...+03:00")
def When.independent(+text: String) -> Bool:
  +s = String.to_lower(String.trim(String.take(text, 256n)))
  +clock = String.drop(s, 10n)
  Bool.or(String.starts_with(s, "in "), Bool.or(String.ends_with(clock, "z"), Bool.or(String.contains(clock, "+"), String.contains(clock, "-"))))
