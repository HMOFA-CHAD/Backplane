import Base
import ./check.bend as C
import ../src/core/tz.bend as Z
import ../src/core/cron.bend as CR

def sh.m(m: Maybe<&2, Z.TzRule>, +t: Nat) -> String:
  match m:
    case None{}:
      "none"
    case Some{r}:
      Z.Tz.show(r, t)

# the zone's wall clock at the UTC instant t
def sh(rule: String, +t: Nat) -> String:
  sh.m(Z.Tz.parse(rule), t)

def iso.m(m: Maybe<&2, Z.TzRule>, +t: Nat) -> String:
  match m:
    case None{}:
      "none"
    case Some{r}:
      Z.Tz.iso(r, t)

def iso(rule: String, +t: Nat) -> String:
  iso.m(Z.Tz.parse(rule), t)

# the UTC instant of a wall time, in ISO
def at.m(m: Maybe<&2, Z.TzRule>, +w: Nat) -> String:
  match m:
    case None{}:
      "none"
    case Some{r}:
      Z.Tz.iso(Z.Tz.utc0(), Z.Tz.at(r, w))

def wall(+y: Nat, +m: Nat, +d: Nat, +h: Nat, +mi: Nat) -> Nat:
  Nat.add(Nat.add(Nat.mul(CR.Cron.days(y, m, d), 86400n), Nat.mul(h, 3600n)), Nat.mul(mi, 60n))

def at(rule: String, +y: Nat, +m: Nat, +d: Nat, +h: Nat, +mi: Nat) -> String:
  at.m(Z.Tz.parse(rule), wall(y, m, d, h, mi))

def ok.m(m: Maybe<&2, Z.TzRule>) -> String:
  match m:
    case None{}:
      "none"
    case Some{_}:
      "some"

def ok(rule: String) -> String:
  ok.m(Z.Tz.parse(rule))

def off.m(m: Maybe<&2, Z.TzRule>, +t: Nat) -> String:
  match m:
    case None{}:
      "none"
    case Some{+r}:
      Z.Tz.offset.text(Z.Tz.off(r, t)) ++ " " ++ Bool.show(Z.Tz.off.is.dst(Z.Tz.off(r, t)))

def off(rule: String, +t: Nat) -> String:
  off.m(Z.Tz.parse(rule), t)

def hel() -> String:
  "EET-2EEST,M3.5.0/3,M10.5.0/4"

def ny() -> String:
  "EST5EDT,M3.2.0,M11.1.0"

def syd() -> String:
  "AEST-10AEDT,M10.1.0,M4.1.0/3"

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("Europe/Helsinki 1774745999", sh("EET-2EEST,M3.5.0/3,M10.5.0/4", 1774745999n), "Sun 29 Mar 02:59 EET")
    C.Check.str("Europe/Helsinki 1774746000", sh("EET-2EEST,M3.5.0/3,M10.5.0/4", 1774746000n), "Sun 29 Mar 04:00 EEST")
    C.Check.str("Europe/Helsinki 1792889999", sh("EET-2EEST,M3.5.0/3,M10.5.0/4", 1792889999n), "Sun 25 Oct 03:59 EEST")
    C.Check.str("Europe/Helsinki 1792890000", sh("EET-2EEST,M3.5.0/3,M10.5.0/4", 1792890000n), "Sun 25 Oct 03:00 EET")
    C.Check.str("America/New_York 1772953199", sh("EST5EDT,M3.2.0,M11.1.0", 1772953199n), "Sun 8 Mar 01:59 EST")
    C.Check.str("America/New_York 1772953200", sh("EST5EDT,M3.2.0,M11.1.0", 1772953200n), "Sun 8 Mar 03:00 EDT")
    C.Check.str("America/New_York 1793512799", sh("EST5EDT,M3.2.0,M11.1.0", 1793512799n), "Sun 1 Nov 01:59 EDT")
    C.Check.str("America/New_York 1793512800", sh("EST5EDT,M3.2.0,M11.1.0", 1793512800n), "Sun 1 Nov 01:00 EST")
    C.Check.str("Australia/Sydney 1791043199", sh("AEST-10AEDT,M10.1.0,M4.1.0/3", 1791043199n), "Sun 4 Oct 01:59 AEST")
    C.Check.str("Australia/Sydney 1791043200", sh("AEST-10AEDT,M10.1.0,M4.1.0/3", 1791043200n), "Sun 4 Oct 03:00 AEDT")
    C.Check.str("Australia/Sydney 1775318399", sh("AEST-10AEDT,M10.1.0,M4.1.0/3", 1775318399n), "Sun 5 Apr 02:59 AEDT")
    C.Check.str("Australia/Sydney 1775318400", sh("AEST-10AEDT,M10.1.0,M4.1.0/3", 1775318400n), "Sun 5 Apr 02:00 AEST")
    C.Check.str("India", sh("IST-5:30", 1791957600n), "Wed 14 Oct 11:30 IST")
    C.Check.str("quoted name", sh("<+0330>-3:30", 1791957600n), "Wed 14 Oct 09:30 +0330")
    C.Check.str("negative transition before", sh("<-02>2<-01>,M3.5.0/-1,M10.5.0/0", 1774745999n), "Sat 28 Mar 22:59 -02")
    C.Check.str("negative transition after", sh("<-02>2<-01>,M3.5.0/-1,M10.5.0/0", 1774746000n), "Sun 29 Mar 00:00 -01")
    C.Check.str("fixed east", Z.Tz.show(Z.Tz.fixed(True{}, 7200n), 1791957600n), "Wed 14 Oct 08:00 +02:00")
    C.Check.str("fixed west", Z.Tz.show(Z.Tz.fixed(False{}, 18000n), 1791957600n), "Wed 14 Oct 01:00 -05:00")
    C.Check.str("utc", Z.Tz.show(Z.Tz.utc0(), 1791957600n), "Wed 14 Oct 06:00 UTC")
    C.Check.str("iso helsinki summer", iso(hel(), 1791957600n), "2026-10-14T09:00:00+03:00")
    C.Check.str("iso helsinki winter", iso(hel(), 1798761600n), "2027-01-01T02:00:00+02:00")
    C.Check.str("iso new york", iso(ny(), 1791957600n), "2026-10-14T02:00:00-04:00")
    C.Check.str("offset text india", off("IST-5:30", 1791957600n), "+05:30 False")
    C.Check.str("offset text helsinki dst", off(hel(), 1791957600n), "+03:00 True")
    C.Check.str("show time", Z.Tz.show.time(Z.Tz.fixed(True{}, 7200n), 1791957600n), "08:00")
    C.Check.str("at normal", at(hel(), 2026n, 10n, 14n, 9n, 30n), "2026-10-14T06:30:00+00:00")
    C.Check.str("at winter", at(hel(), 2026n, 12n, 14n, 9n, 30n), "2026-12-14T07:30:00+00:00")
    C.Check.str("at helsinki gap", at(hel(), 2026n, 3n, 29n, 3n, 30n), "2026-03-29T01:30:00+00:00")
    C.Check.str("at helsinki overlap is the earlier", at(hel(), 2026n, 10n, 25n, 3n, 30n), "2026-10-25T00:30:00+00:00")
    C.Check.str("at new york gap", at(ny(), 2026n, 3n, 8n, 2n, 30n), "2026-03-08T07:30:00+00:00")
    C.Check.str("at new york overlap", at(ny(), 2026n, 11n, 1n, 1n, 30n), "2026-11-01T05:30:00+00:00")
    C.Check.str("at sydney gap", at(syd(), 2026n, 10n, 4n, 2n, 30n), "2026-10-03T16:30:00+00:00")
    C.Check.str("at sydney overlap", at(syd(), 2026n, 4n, 5n, 2n, 30n), "2026-04-04T15:30:00+00:00")
    C.Check.str("at india", at("IST-5:30", 2026n, 10n, 14n, 9n, 30n), "2026-10-14T04:00:00+00:00")
    C.Check.str("wall at inverse", sh(hel(), Z.Tz.at(Maybe.default(&2, Z.TzRule, Z.Tz.parse(hel()), Z.Tz.utc0()), wall(2026n, 7n, 1n, 12n, 0n))), "Wed 1 Jul 12:00 EEST")
    C.Check.str("dst default rule", off("EST5EDT", 1791957600n), "-04:00 True")
    C.Check.str("dst default rule winter", off("EST5EDT", 1798761600n), "-05:00 False")
    C.Check.str("J rule", off("AAA-1BBB,J60,J300", 1773000000n), "+02:00 True")
    C.Check.str("N rule", off("AAA-1BBB,59,299", 1773000000n), "+02:00 True")
    C.Check.str("hours over 24", off("AAA-1BBB,M3.5.0/25,M10.5.0/3", 1773000000n), "+01:00 False")
    C.Check.str("explicit dst offset", off("AAA-1BBB-3,M3.5.0,M10.5.0", 1791957600n), "+03:00 True")
    C.Check.str("reject empty", ok(""), "none")
    C.Check.str("reject junk", ok("garbage"), "none")
    C.Check.str("reject no offset", ok("EET"), "none")
    C.Check.str("reject short name", ok("E-2"), "none")
    C.Check.str("reject one rule", ok("EET-2EEST,M3.5.0"), "none")
    C.Check.str("reject month 13", ok("EET-2EEST,M13.1.0,M10.5.0"), "none")
    C.Check.str("reject rules without dst", ok("EET-2,M3.5.0,M10.5.0"), "none")
    C.Check.str("reject open quote", ok("<+03-3"), "none")
    C.Check.str("reject empty quote", ok("<>-3"), "none")
    C.Check.str("accept simple", ok("UTC0"), "some")
    C.Check.str("accept quoted", ok("<+03>-3"), "some")
