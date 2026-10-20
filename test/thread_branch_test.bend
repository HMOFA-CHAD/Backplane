import Base
import ./check.bend as C
import ../src/core/hub.bend as H
import ../src/server/git.bend as G

# Run this same program with bend (JS) and compiled natively. Expected
# seeds and names were computed with arbitrary-precision decimal arithmetic
# modulo 2^32 and Murmur3's finalizer, independently of Wt.seed.

def branch(id: String) -> String:
  G.Git.branch.temp(H.Wt.seed(id))

def contains(xs: List<&2, String>, +b: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case h <> t:
      Bool.or(String.eq(h, b), contains(t, b))

# Consecutive realistic sequence numbers in one second must remain stable
# and distinct. Keep every previous branch, so this catches nonadjacent
# collisions too; cover both decimal sequence-width boundaries.
def distinct.go(n: Nat, +seq: Nat, +seen: List<&2, String>) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      +id = H.Hub.id("t", 1791993305n, seq)
      +b = branch(id)
      Bool.and(Bool.and(String.eq(b, branch(id)), Bool.not(contains(seen, b))), distinct.go(p, 1n+seq, b <> seen))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("t100-1", Nat.show(H.Wt.seed("t100-1")) ++ " " ++ branch("t100-1"), "1001 backplane/18ac53dc")
    C.Check.str("t1791993305-99999", Nat.show(H.Wt.seed("t1791993305-99999")) ++ " " ++ branch("t1791993305-99999"), "410108991 backplane/485d1666")
    C.Check.str("t1791993305-100000", Nat.show(H.Wt.seed("t1791993305-100000")) ++ " " ++ branch("t1791993305-100000"), "4100189920 backplane/c46bd601")
    C.Check.str("t1791993305-100157", Nat.show(H.Wt.seed("t1791993305-100157")) ++ " " ++ branch("t1791993305-100157"), "4100190077 backplane/bb1883ea")
    C.Check.str("t1791993305-100158", Nat.show(H.Wt.seed("t1791993305-100158")) ++ " " ++ branch("t1791993305-100158"), "4100190078 backplane/e57c75ca")
    C.Check.str("t1792000001-103473", Nat.show(H.Wt.seed("t1792000001-103473")) ++ " " ++ branch("t1792000001-103473"), "2206258801 backplane/2377f928")
    C.Check.str("t1792075081-125169", Nat.show(H.Wt.seed("t1792075081-125169")) ++ " " ++ branch("t1792075081-125169"), "4271836465 backplane/335ba08c")
    C.Check.str("t1792172729-149991", Nat.show(H.Wt.seed("t1792172729-149991")) ++ " " ++ branch("t1792172729-149991"), "3135613479 backplane/72eb8dfd")
    C.Check.str("t1792172729-999999", Nat.show(H.Wt.seed("t1792172729-999999")) ++ " " ++ branch("t1792172729-999999"), "3136463487 backplane/ec3672a1")
    C.Check.str("t1792172729-1000000", Nat.show(H.Wt.seed("t1792172729-1000000")) ++ " " ++ branch("t1792172729-1000000"), "1290863808 backplane/b49343c2")
    C.Check.str("t1792172729-12345678901234567890", Nat.show(H.Wt.seed("t1792172729-12345678901234567890")) ++ " " ++ branch("t1792172729-12345678901234567890"), "2712603346 backplane/03eccc2d")
    C.Check.str("U32 wrap below", Nat.show(H.Wt.seed("t4294967295")), "4294967295")
    C.Check.str("U32 wrap", Nat.show(H.Wt.seed("t4294967296")), "0")
    C.Check.str("U32 wrap above", Nat.show(H.Wt.seed("t4294967297")), "1")
    C.Check.str("skip nondigits", Nat.show(H.Wt.seed("t100-1")) ++ " " ++ Nat.show(H.Wt.seed("x1!00/1")), "1001 1001")
    C.Check.str("no digits", Nat.show(H.Wt.seed("")) ++ " " ++ Nat.show(H.Wt.seed("thread")), "0 0")
    C.Check.str("same second 99999 to 100000", Bool.show(distinct.go(256n, 99900n, Nil{})), "True")
    C.Check.str("same second 999999 to 1000000", Bool.show(distinct.go(256n, 999900n, Nil{})), "True")
