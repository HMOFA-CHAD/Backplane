import Base
import ./model.bend as M
import ./cron.bend as CR

# Time zones
# ----------
# A zone is its POSIX TZ rule, the footer line of a TZif file
# (`EET-2EEST,M3.5.0/3,M10.5.0/4`): a standard offset and name, and
# optionally a daylight-saving offset and name with the rules for when it
# starts and ends. Offsets in the string are POSIX's (west positive); a
# rule keeps them as `Sg` (east positive). `Tz.off` says which offset holds
# at a UTC instant, `Tz.wall` is the clock on the wall then, and `Tz.at`
# goes back: the instant of a wall time. A wall time in the gap of a spring
# forward is read with the standard offset (02:30 in a 02:00 to 03:00 gap
# is 03:30 local); an ambiguous one (fall back) is the earlier instant.

# a signed number of seconds: east of UTC (positive) or west, and how many
type Sg is Data:
  Sg{east: Bool, n: Nat}

# the day a transition falls on
type TzDay is Data:
  TzM{m: Nat, w: Nat, d: Nat}
  TzJ{n: Nat}
  TzN{n: Nat}

type TzRule is Data:
  TzRule{sname: String, soff: Sg, dst: Bool, dname: String, doff: Sg, start: TzDay, stime: Sg, end: TzDay, etime: Sg}

type TzOff is Data:
  TzOff{east: Bool, secs: Nat, dst: Bool, abbr: String}

# Signed seconds
# --------------

def Tz.sg.add.k(same: Bool, ea: Bool, +na: Nat, eb: Bool, +nb: Nat) -> Sg:
  match same:
    case True{}:
      Sg{ea, Nat.add(na, nb)}
    case False{}:
      Bool.pick(Sg, Nat.is_ge(na, nb), Sg{ea, Nat.sub(na, nb)}, Sg{eb, Nat.sub(nb, na)})

def Tz.sg.add(a: Sg, b: Sg) -> Sg:
  match a b:
    case Sg{+ea, +na} Sg{+eb, +nb}:
      Tz.sg.add.k(Bool.not(Bool.xor(ea, eb)), ea, na, eb, nb)

# a non-negative number of seconds, negatives as 0
def Tz.sg.nat(s: Sg) -> Nat:
  match s:
    case Sg{east, n}:
      Bool.pick(Nat, east, n, 0n)

# Parsing
# -------

type TkSt is Data:
  TkSt{acc: List<&2, String>, cur: String, kind: Nat, bad: Bool}

def Tz.tok.flush.k(none: Bool, acc: List<&2, String>, cur: String, bad: Bool) -> TkSt:
  match none:
    case True{}:
      TkSt{acc, cur, 0n, bad}
    case False{}:
      TkSt{cur <> acc, "", 0n, bad}

def Tz.tok.flush(st: TkSt) -> TkSt:
  match st:
    case TkSt{acc, cur, kind, bad}:
      Tz.tok.flush.k(Nat.is_eq(kind, 0n), acc, cur, bad)

def Tz.tok.add.n(st: TkSt, c: Char, kind: Nat) -> TkSt:
  match st:
    case TkSt{acc, cur, k, bad}:
      TkSt{acc, SCon{c, SNil{}}, kind, bad}

def Tz.tok.add.k(same: Bool, acc: List<&2, String>, cur: String, k: Nat, bad: Bool, +c: Char, +kind: Nat) -> TkSt:
  match same:
    case True{}:
      TkSt{acc, cur ++ SCon{c, SNil{}}, kind, bad}
    case False{}:
      Tz.tok.add.n(Tz.tok.flush(TkSt{acc, cur, k, bad}), c, kind)

def Tz.tok.add(st: TkSt, +c: Char, +kind: Nat) -> TkSt:
  match st:
    case TkSt{acc, cur, +k, bad}:
      Tz.tok.add.k(Nat.is_eq(k, kind), acc, cur, k, bad, c, kind)

def Tz.num.char(+c: Char) -> Bool:
  Bool.or(Char.is_digit(c), Bool.or(Char.is_eq(c, '+'), Bool.or(Char.is_eq(c, '-'), Char.is_eq(c, ':'))))

def Tz.tok.open.n(st: TkSt) -> TkSt:
  match st:
    case TkSt{acc, cur, k, bad}:
      TkSt{acc, "<", 3n, bad}

def Tz.tok.open(st: TkSt) -> TkSt:
  match st:
    case TkSt{acc, cur, k, bad}:
      Tz.tok.open.n(Tz.tok.flush(TkSt{acc, cur, k, bad}))

def Tz.tok.shut(st: TkSt) -> TkSt:
  match st:
    case TkSt{acc, cur, k, bad}:
      TkSt{cur <> acc, "", 0n, bad}

def Tz.tok.bad(st: TkSt) -> TkSt:
  match st:
    case TkSt{acc, cur, k, bad}:
      TkSt{acc, cur, k, True{}}

def Tz.tok.step.k(quoted: Bool, close: Bool, open: Bool, alpha: Bool, num: Bool, +st: TkSt, +c: Char) -> TkSt:
  match quoted:
    case True{}:
      Bool.pick(TkSt, close, Tz.tok.shut(st), Tz.tok.add(st, c, 3n))
    case False{}:
      Bool.pick(TkSt, open, Tz.tok.open(st), Bool.pick(TkSt, alpha, Tz.tok.add(st, c, 1n), Bool.pick(TkSt, num, Tz.tok.add(st, c, 2n), Tz.tok.bad(st))))

def Tz.tok.step.q(st: TkSt) -> Bool:
  match st:
    case TkSt{acc, cur, k, bad}:
      Nat.is_eq(k, 3n)

def Tz.tok.step(+st: TkSt, +c: Char) -> TkSt:
  Tz.tok.step.k(Tz.tok.step.q(st), Char.is_eq(c, '>'), Char.is_eq(c, '<'), Char.is_alpha(c), Tz.num.char(c), st, c)

# the name and offset tokens of a rule's first part, in order; None for a
# character that belongs in none
def Tz.tok.go(s: String, st: TkSt) -> TkSt:
  match s:
    case SNil{}:
      st
    case SCon{+c, t}:
      Tz.tok.go(t, Tz.tok.step(st, c))

def Tz.tok.fin.k(bad: Bool, ts: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match bad:
    case True{}:
      None{}
    case False{}:
      Some{ts}

def Tz.tok.fin(st: TkSt) -> Maybe<&2, List<&2, String>>:
  match st:
    case TkSt{acc, cur, kind, bad}:
      Tz.tok.fin.k(Bool.or(bad, Nat.is_eq(kind, 3n)), List.reverse(&2, String, acc))

def Tz.tok.clean.k(empty: Bool, h: String, rest: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      rest
    case False{}:
      h <> rest

# the tokens still hold an empty first when nothing followed; drop empties
def Tz.tok.clean(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +h <> t:
      Tz.tok.clean.k(String.is_empty(h), h, Tz.tok.clean(t))

def Tz.tokens(s: String) -> Maybe<&2, List<&2, String>>:
  Tz.tok.fin(Tz.tok.flush(Tz.tok.go(s, TkSt{Nil{}, "", 0n, False{}})))

def Tz.alpha.all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{+c, t}:
      Bool.and(Char.is_alpha(c), Tz.alpha.all(t))

def Tz.name.q(empty: Bool, r: String) -> Maybe<&2, String>:
  match empty:
    case True{}:
      None{}
    case False{}:
      Some{r}

def Tz.name.a.k(ok: Bool, s: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{s}
    case False{}:
      None{}

def Tz.name.a(+s: String) -> Maybe<&2, String>:
  Tz.name.a.k(Bool.and(Tz.alpha.all(s), Nat.is_ge(String.length(s), 3n)), s)

def Tz.name.k(quoted: Bool, +c: Char, +r: String) -> Maybe<&2, String>:
  match quoted:
    case True{}:
      Tz.name.q(String.is_empty(r), r)
    case False{}:
      Tz.name.a(SCon{c, r})

# a name token: three or more letters, or <...> with something inside
def Tz.name(t: String) -> Maybe<&2, String>:
  match t:
    case SNil{}:
      None{}
    case SCon{+c, r}:
      Tz.name.k(Char.is_eq(c, '<'), c, r)

def Tz.hms.ok(ok: Bool, +n: Nat) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      Some{n}
    case False{}:
      None{}

def Tz.hms.h(h: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match h:
    case Some{+h}:
      Tz.hms.ok(Nat.is_le(h, 167n), Nat.mul(h, 3600n))
    case None{}:
      None{}

def Tz.hms.m(h: Maybe<&2, Nat>, m: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match h m:
    case Some{+h} Some{+m}:
      Tz.hms.ok(Bool.and(Nat.is_le(h, 167n), Nat.is_le(m, 59n)), Nat.add(Nat.mul(h, 3600n), Nat.mul(m, 60n)))
    case _ _:
      None{}

def Tz.hms.s(h: Maybe<&2, Nat>, m: Maybe<&2, Nat>, s: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match h m s:
    case Some{+h} Some{+m} Some{+s}:
      Tz.hms.ok(Bool.and(Bool.and(Nat.is_le(h, 167n), Nat.is_le(m, 59n)), Nat.is_le(s, 59n)), Nat.add(Nat.add(Nat.mul(h, 3600n), Nat.mul(m, 60n)), s))
    case _ _ _:
      None{}

# h[h[h]][:mm[:ss]] as seconds
def Tz.hms.go(ps: List<&2, String>) -> Maybe<&2, Nat>:
  match ps:
    case h <> Nil{}:
      Tz.hms.h(CR.Cron.num(h))
    case h <> m <> Nil{}:
      Tz.hms.m(CR.Cron.num(h), CR.Cron.num(m))
    case h <> m <> s <> Nil{}:
      Tz.hms.s(CR.Cron.num(h), CR.Cron.num(m), CR.Cron.num(s))
    case _:
      None{}

# a sign (+ or -) apart from the digits: (negative, rest)
type Signed is Data:
  Signed{neg: Bool, rest: String}

def Tz.sign.k(neg: Bool, plus: Bool, +c: Char, t: String) -> Signed:
  match neg plus:
    case True{} _:
      Signed{True{}, t}
    case False{} True{}:
      Signed{False{}, t}
    case False{} False{}:
      Signed{False{}, SCon{c, t}}

def Tz.sign(s: String) -> Signed:
  match s:
    case SNil{}:
      Signed{False{}, ""}
    case SCon{+c, t}:
      Tz.sign.k(Char.is_eq(c, '-'), Char.is_eq(c, '+'), c, t)

def Tz.hms(t: String) -> Maybe<&2, Nat>:
  Tz.hms.go(String.split(t, ':'))

# a POSIX offset: no sign or + is west, - is east
def Tz.posix.k(sg: Signed, v: Maybe<&2, Nat>) -> Maybe<&2, Sg>:
  match sg v:
    case Signed{neg, _} Some{n}:
      Some{Sg{neg, n}}
    case _ None{}:
      None{}

def Tz.posix.n(sg: Signed) -> Maybe<&2, Sg>:
  match sg:
    case Signed{+neg, rest}:
      Tz.posix.k(Signed{neg, ""}, Tz.hms(rest))

def Tz.posix(t: String) -> Maybe<&2, Sg>:
  Tz.posix.n(Tz.sign(t))

# a transition time: the sign is literal, + or none is positive
def Tz.ttime.k(sg: Signed, v: Maybe<&2, Nat>) -> Maybe<&2, Sg>:
  match sg v:
    case Signed{neg, _} Some{n}:
      Some{Sg{Bool.not(neg), n}}
    case _ None{}:
      None{}

def Tz.ttime.n(sg: Signed) -> Maybe<&2, Sg>:
  match sg:
    case Signed{+neg, rest}:
      Tz.ttime.k(Signed{neg, ""}, Tz.hms(rest))

def Tz.ttime(t: String) -> Maybe<&2, Sg>:
  Tz.ttime.n(Tz.sign(t))

def Tz.day.ok(ok: Bool, d: TzDay) -> Maybe<&2, TzDay>:
  match ok:
    case True{}:
      Some{d}
    case False{}:
      None{}

def Tz.day.m.k(m: Maybe<&2, Nat>, w: Maybe<&2, Nat>, d: Maybe<&2, Nat>) -> Maybe<&2, TzDay>:
  match m w d:
    case Some{+m} Some{+w} Some{+d}:
      Tz.day.ok(Bool.and(Bool.and(Nat.is_ge(m, 1n), Nat.is_le(m, 12n)), Bool.and(Bool.and(Nat.is_ge(w, 1n), Nat.is_le(w, 5n)), Nat.is_le(d, 6n))), TzM{m, w, d})
    case _ _ _:
      None{}

def Tz.day.m(ps: List<&2, String>) -> Maybe<&2, TzDay>:
  match ps:
    case m <> w <> d <> Nil{}:
      Tz.day.m.k(CR.Cron.num(m), CR.Cron.num(w), CR.Cron.num(d))
    case _:
      None{}

def Tz.day.j(v: Maybe<&2, Nat>) -> Maybe<&2, TzDay>:
  match v:
    case Some{+n}:
      Tz.day.ok(Bool.and(Nat.is_ge(n, 1n), Nat.is_le(n, 365n)), TzJ{n})
    case None{}:
      None{}

def Tz.day.n(v: Maybe<&2, Nat>) -> Maybe<&2, TzDay>:
  match v:
    case Some{+n}:
      Tz.day.ok(Nat.is_le(n, 365n), TzN{n})
    case None{}:
      None{}

def Tz.day.k(m: Bool, j: Bool, c: Char, t: String) -> Maybe<&2, TzDay>:
  match m j:
    case True{} _:
      Tz.day.m(String.split(t, '.'))
    case False{} True{}:
      Tz.day.j(CR.Cron.num(t))
    case False{} False{}:
      Tz.day.n(CR.Cron.num(SCon{c, t}))

def Tz.day(s: String) -> Maybe<&2, TzDay>:
  match s:
    case SNil{}:
      None{}
    case SCon{+c, t}:
      Tz.day.k(Char.is_eq(c, 'M'), Char.is_eq(c, 'J'), c, t)

type TzTrans is Data:
  TzTrans{day: TzDay, time: Sg}

def Tz.trans.k(d: Maybe<&2, TzDay>, t: Maybe<&2, Sg>) -> Maybe<&2, TzTrans>:
  match d t:
    case Some{d} Some{t}:
      Some{TzTrans{d, t}}
    case _ _:
      None{}

def Tz.trans.parts(ps: List<&2, String>) -> Maybe<&2, TzTrans>:
  match ps:
    case d <> Nil{}:
      Tz.trans.k(Tz.day(d), Some{Sg{True{}, 7200n}})
    case d <> t <> Nil{}:
      Tz.trans.k(Tz.day(d), Tz.ttime(t))
    case _:
      None{}

def Tz.trans(s: String) -> Maybe<&2, TzTrans>:
  Tz.trans.parts(String.split(s, '/'))

def Tz.def.start() -> TzTrans:
  TzTrans{TzM{3n, 2n, 0n}, Sg{True{}, 7200n}}

def Tz.def.end() -> TzTrans:
  TzTrans{TzM{11n, 1n, 0n}, Sg{True{}, 7200n}}

# std offset [dst [offset]] with its rule parts
def Tz.build.std(sn: Maybe<&2, String>, so: Maybe<&2, Sg>) -> Maybe<&2, TzRule>:
  match sn so:
    case Some{n} Some{+o}:
      Some{TzRule{n, o, False{}, "", o, TzM{3n, 2n, 0n}, Sg{True{}, 7200n}, TzM{11n, 1n, 0n}, Sg{True{}, 7200n}}}
    case _ _:
      None{}

def Tz.build.dst.k(sn: String, +so: Sg, dn: String, dof: Maybe<&2, Sg>, given: Bool) -> Maybe<&2, TzRule>:
  match dof given:
    case None{} True{}:
      None{}
    case Some{o} True{}:
      Some{TzRule{sn, so, True{}, dn, o, TzM{3n, 2n, 0n}, Sg{True{}, 7200n}, TzM{11n, 1n, 0n}, Sg{True{}, 7200n}}}
    case _ False{}:
      Some{TzRule{sn, so, True{}, dn, Tz.sg.add(so, Sg{True{}, 3600n}), TzM{3n, 2n, 0n}, Sg{True{}, 7200n}, TzM{11n, 1n, 0n}, Sg{True{}, 7200n}}}

def Tz.build.dst(r: Maybe<&2, TzRule>, dn: Maybe<&2, String>, dof: Maybe<&2, Sg>, given: Bool) -> Maybe<&2, TzRule>:
  match r dn:
    case Some{TzRule{sn, so, _, _, _, a, b, c, d}} Some{+dn}:
      Tz.build.dst.k(sn, so, dn, dof, given)
    case _ _:
      None{}

def Tz.with(r: Maybe<&2, TzRule>, a: Maybe<&2, TzTrans>, b: Maybe<&2, TzTrans>) -> Maybe<&2, TzRule>:
  match r a b:
    case Some{TzRule{sn, so, dst, dn, dof, _, _, _, _}} Some{TzTrans{da, ta}} Some{TzTrans{db, tb}}:
      Some{TzRule{sn, so, dst, dn, dof, da, ta, db, tb}}
    case _ _ _:
      None{}

def Tz.parse.names(ts: List<&2, String>) -> Maybe<&2, TzRule>:
  match ts:
    case n <> o <> Nil{}:
      Tz.build.std(Tz.name(n), Tz.posix(o))
    case n <> o <> d <> Nil{}:
      Tz.build.dst(Tz.build.std(Tz.name(n), Tz.posix(o)), Tz.name(d), None{}, False{})
    case n <> o <> d <> o2 <> Nil{}:
      Tz.build.dst(Tz.build.std(Tz.name(n), Tz.posix(o)), Tz.name(d), Tz.posix(o2), True{})
    case _:
      None{}

def Tz.parse.head(m: Maybe<&2, List<&2, String>>) -> Maybe<&2, TzRule>:
  match m:
    case Some{ts}:
      Tz.parse.names(ts)
    case None{}:
      None{}

def Tz.parse.rules.dst.k(dst: Bool, x: TzRule) -> Maybe<&2, TzRule>:
  match dst:
    case True{}:
      Some{x}
    case False{}:
      None{}

# transitions on a rule without DST are an error
def Tz.parse.rules.dst(x: TzRule) -> Maybe<&2, TzRule>:
  match x:
    case TzRule{sn, so, +dst, dn, dof, a, b, c, d}:
      Tz.parse.rules.dst.k(dst, TzRule{sn, so, dst, dn, dof, a, b, c, d})

def Tz.parse.rules.k(x: TzRule, a: Maybe<&2, TzTrans>, b: Maybe<&2, TzTrans>) -> Maybe<&2, TzRule>:
  Tz.with(Tz.parse.rules.dst(x), a, b)

# a rule needs DST names when it has transitions
def Tz.parse.rules(r: Maybe<&2, TzRule>, ps: List<&2, String>) -> Maybe<&2, TzRule>:
  match r ps:
    case Some{x} Nil{}:
      Some{x}
    case Some{x} a <> b <> Nil{}:
      Tz.parse.rules.k(x, Tz.trans(a), Tz.trans(b))
    case _ _:
      None{}

def Tz.parse.split(ps: List<&2, String>) -> Maybe<&2, TzRule>:
  match ps:
    case h <> rest:
      Tz.parse.rules(Tz.parse.head(Tz.tokens(h)), rest)
    case Nil{}:
      None{}

# the POSIX rule of a TZ string, None when it does not parse
def Tz.parse(s: String) -> Maybe<&2, TzRule>:
  Tz.parse.split(String.split(String.trim(s), ','))

# a fixed offset (date +%z) and UTC
def Tz.fixed(+east: Bool, +secs: Nat) -> TzRule:
  TzRule{"", Sg{east, secs}, False{}, "", Sg{east, secs}, TzM{3n, 2n, 0n}, Sg{True{}, 7200n}, TzM{11n, 1n, 0n}, Sg{True{}, 7200n}}

def Tz.utc0() -> TzRule:
  TzRule{"UTC", Sg{True{}, 0n}, False{}, "", Sg{True{}, 0n}, TzM{3n, 2n, 0n}, Sg{True{}, 7200n}, TzM{11n, 1n, 0n}, Sg{True{}, 7200n}}

# Transitions
# -----------

def Tz.leap(+y: Nat) -> Bool:
  Bool.and(Nat.is_eq(Nat.mod(y, 4n), 0n), Bool.or(Bool.not(Nat.is_eq(Nat.mod(y, 100n), 0n)), Nat.is_eq(Nat.mod(y, 400n), 0n)))

# 0 = Sunday; day 0 of the epoch was a Thursday
def Tz.wday(+days: Nat) -> Nat:
  Nat.mod(Nat.add(days, 4n), 7n)

def Tz.month.next(+y: Nat, +m: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_eq(m, 12n), CR.Cron.days(1n+y, 1n, 1n), CR.Cron.days(y, 1n+m, 1n))

def Tz.m.last(over: Bool, +cand: Nat) -> Nat:
  Bool.pick(Nat, over, Nat.sub(cand, 7n), cand)

# the w-th weekday d of month m (w=5: the last one), as a day number
def Tz.m.day(+y: Nat, +m: Nat, +w: Nat, +d: Nat) -> Nat:
  +first = CR.Cron.days(y, m, 1n)
  +cand = Nat.add(Nat.add(first, Nat.mod(Nat.add(d, Nat.sub(7n, Tz.wday(first))), 7n)), Nat.mul(7n, Nat.sub(w, 1n)))
  Tz.m.last(Nat.is_ge(cand, Tz.month.next(y, m)), cand)

def Tz.j.day(+y: Nat, +n: Nat) -> Nat:
  Nat.add(Nat.add(CR.Cron.days(y, 1n, 1n), Nat.sub(n, 1n)), Bool.pick(Nat, Bool.and(Tz.leap(y), Nat.is_ge(n, 60n)), 1n, 0n))

def Tz.day.num(d: TzDay, +y: Nat) -> Nat:
  match d:
    case TzM{+m, +w, +dd}:
      Tz.m.day(y, m, w, dd)
    case TzJ{+n}:
      Tz.j.day(y, n)
    case TzN{+n}:
      Nat.add(CR.Cron.days(y, 1n, 1n), n)

# wall-clock seconds of a transition in year y
def Tz.trans.wall(d: TzDay, t: Sg, +y: Nat) -> Nat:
  Tz.sg.nat(Tz.sg.add(Sg{True{}, Nat.mul(Tz.day.num(d, y), 86400n)}, t))

def Tz.year.of(d: CR.Ymd) -> Nat:
  match d:
    case CR.Ymd{y, _, _}:
      y

def Tz.year(+t: Nat) -> Nat:
  Tz.year.of(CR.Cron.civil(Nat.div(t, 86400n)))

def Tz.sg.local(s: Sg, +t: Nat) -> Nat:
  match s:
    case Sg{east, n}:
      M.Snooze.local(east, t, n)

def Tz.sg.utc(s: Sg, +w: Nat) -> Nat:
  match s:
    case Sg{east, n}:
      M.Snooze.utc(east, w, n)

# the instants in year y that DST begins and ends
def Tz.begins(r: TzRule, +y: Nat) -> Nat:
  match r:
    case TzRule{_, so, _, _, _, a, ta, _, _}:
      Tz.sg.utc(so, Tz.trans.wall(a, ta, y))

def Tz.ends(r: TzRule, +y: Nat) -> Nat:
  match r:
    case TzRule{_, _, _, _, dof, _, _, b, tb}:
      Tz.sg.utc(dof, Tz.trans.wall(b, tb, y))

def Tz.in.dst.k(north: Bool, +s: Nat, +e: Nat, +t: Nat) -> Bool:
  match north:
    case True{}:
      Bool.and(Nat.is_ge(t, s), Nat.is_lt(t, e))
    case False{}:
      Bool.or(Nat.is_ge(t, s), Nat.is_lt(t, e))

def Tz.in.dst.y(+r: TzRule, +y: Nat, +t: Nat) -> Bool:
  +s = Tz.begins(r, y)
  +e = Tz.ends(r, y)
  Tz.in.dst.k(Nat.is_lt(s, e), s, e, t)

def Tz.has.dst(r: TzRule) -> Bool:
  match r:
    case TzRule{_, _, dst, _, _, _, _, _, _}:
      dst

def Tz.std.of(r: TzRule) -> Sg:
  match r:
    case TzRule{_, so, _, _, _, _, _, _, _}:
      so

# whether DST is in effect at the UTC instant t
def Tz.is.dst.k(has: Bool, +r: TzRule, +t: Nat) -> Bool:
  match has:
    case False{}:
      False{}
    case True{}:
      Tz.in.dst.y(r, Tz.year(Tz.sg.local(Tz.std.of(r), t)), t)

def Tz.is.dst(+r: TzRule, +t: Nat) -> Bool:
  Tz.is.dst.k(Tz.has.dst(r), r, t)

def Tz.off.dst(r: TzRule) -> TzOff:
  match r:
    case TzRule{_, _, _, dn, Sg{east, n}, _, _, _, _}:
      TzOff{east, n, True{}, dn}

def Tz.off.std(r: TzRule) -> TzOff:
  match r:
    case TzRule{sn, Sg{east, n}, _, _, _, _, _, _, _}:
      TzOff{east, n, False{}, sn}

def Tz.off.k(dst: Bool, r: TzRule) -> TzOff:
  match dst:
    case True{}:
      Tz.off.dst(r)
    case False{}:
      Tz.off.std(r)

# the offset in effect at the UTC instant t
def Tz.off(+r: TzRule, +t: Nat) -> TzOff:
  Tz.off.k(Tz.is.dst(r, t), r)

def Tz.off.east(o: TzOff) -> Bool:
  match o:
    case TzOff{east, _, _, _}:
      east

def Tz.off.secs(o: TzOff) -> Nat:
  match o:
    case TzOff{_, secs, _, _}:
      secs

def Tz.off.is.dst(o: TzOff) -> Bool:
  match o:
    case TzOff{_, _, dst, _}:
      dst

def Tz.off.abbr(o: TzOff) -> String:
  match o:
    case TzOff{_, _, _, abbr}:
      abbr

def Tz.wall.o(o: TzOff, +t: Nat) -> Nat:
  match o:
    case TzOff{east, secs, _, _}:
      M.Snooze.local(east, t, secs)

# the wall clock at the UTC instant t, as seconds of the wall's own epoch
def Tz.wall(r: TzRule, +t: Nat) -> Nat:
  Tz.wall.o(Tz.off(r, t), t)

def Tz.dst.of(r: TzRule) -> Sg:
  match r:
    case TzRule{_, _, _, _, dof, _, _, _, _}:
      dof

def Tz.at.k(vd: Bool, ud: Nat, us: Nat) -> Nat:
  match vd:
    case True{}:
      ud
    case False{}:
      us

# the instant a wall time happened; the earlier one when it happened twice,
# and when it never did (a gap) the instant with the same offset as before
def Tz.at(+r: TzRule, +w: Nat) -> Nat:
  +ud = Tz.sg.utc(Tz.dst.of(r), w)
  +us = Tz.sg.utc(Tz.std.of(r), w)
  Tz.at.k(Bool.and(Tz.has.dst(r), Tz.is.dst(r, ud)), ud, us)

# Showing
# -------

def Tz.wnames() -> List<&2, String>:
  ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

def Tz.mnames() -> List<&2, String>:
  ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

def Tz.nth(xs: List<&2, String>, n: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, n), "")

def Tz.pad4(+n: Nat) -> String:
  Bool.pick(String, Nat.is_lt(n, 1000n), "0" ++ Nat.show(n), Nat.show(n))

# "+03:00"
def Tz.offset.text(o: TzOff) -> String:
  match o:
    case TzOff{east, +secs, _, _}:
      Bool.pick(String, east, "+", "-") ++ CR.Cron.hm(Nat.div(secs, 3600n), Nat.div(Nat.mod(secs, 3600n), 60n))

def Tz.show.ymd(d: CR.Ymd, +w: Nat) -> String:
  match d:
    case CR.Ymd{y, m, dd}:
      Tz.nth(Tz.wnames(), Tz.wday(Nat.div(w, 86400n))) ++ " " ++ Nat.show(dd) ++ " " ++ Tz.nth(Tz.mnames(), Nat.sub(m, 1n)) ++ " " ++ CR.Cron.hm(Nat.div(Nat.mod(w, 86400n), 3600n), Nat.div(Nat.mod(w, 3600n), 60n))

# "Tue 14 Oct 09:30" from a wall clock
def Tz.show.dt(+w: Nat) -> String:
  Tz.show.ymd(CR.Cron.civil(Nat.div(w, 86400n)), w)

def Tz.show.at(+w: Nat, abbr: String) -> String:
  Tz.show.dt(w) ++ " " ++ abbr

def Tz.abbr.k(empty: Bool, o: TzOff) -> String:
  match empty:
    case True{}:
      Tz.offset.text(o)
    case False{}:
      Tz.off.abbr(o)

# the abbreviation to show: the zone's own, else its offset
def Tz.abbr(+o: TzOff) -> String:
  Tz.abbr.k(String.is_empty(Tz.off.abbr(o)), o)

# "Tue 14 Oct 09:30 EEST"
def Tz.show(+r: TzRule, +t: Nat) -> String:
  Tz.show.at(Tz.wall(r, t), Tz.abbr(Tz.off(r, t)))

# "09:30"
def Tz.show.time(r: TzRule, +t: Nat) -> String:
  +w = Tz.wall(r, t)
  CR.Cron.hm(Nat.div(Nat.mod(w, 86400n), 3600n), Nat.div(Nat.mod(w, 3600n), 60n))

# "2026-10-14T09:30:00+03:00"
def Tz.iso.ymd(d: CR.Ymd, +w: Nat, off: String) -> String:
  match d:
    case CR.Ymd{y, m, d}:
      Tz.pad4(y) ++ "-" ++ CR.Cron.pad2(m) ++ "-" ++ CR.Cron.pad2(d) ++ "T" ++ CR.Cron.pad2(Nat.div(Nat.mod(w, 86400n), 3600n)) ++ ":" ++ CR.Cron.pad2(Nat.div(Nat.mod(w, 3600n), 60n)) ++ ":" ++ CR.Cron.pad2(Nat.mod(w, 60n)) ++ off

def Tz.iso.at(+w: Nat, off: String) -> String:
  Tz.iso.ymd(CR.Cron.civil(Nat.div(w, 86400n)), w, off)

def Tz.iso(+r: TzRule, +t: Nat) -> String:
  Tz.iso.at(Tz.wall(r, t), Tz.offset.text(Tz.off(r, t)))

# "Tue 14 Oct 09:30" with no zone name
def Tz.show.nz(r: TzRule, +t: Nat) -> String:
  Tz.show.dt(Tz.wall(r, t))
