import Base
import ../src/core/telemetry.bend as T
import ./check.bend as C

def Delivery.ev(+ver: String) -> T.TmEv:
  T.TmEv{"update", "2026-10-20", False{}, "", ver, "0.11.2", "release", "linux", "x64", "", 1n, False{}}

def Delivery.state() -> T.TmState:
  T.TmState{"", "0.11.4", "2026-10-20", False{}, "0", [Delivery.ev("0.11.3"), Delivery.ev("0.11.4")], 0n, 0n, True{}}

def Delivery.after(+code: Nat, +retry: Nat) -> T.TmState:
  T.Tm.sent(Delivery.state(), [Delivery.ev("0.11.3")], code, retry, 100n)

# Exhaust every HTTP status, including non-HTTP zero. Compare the protocol's
# explicit terminal set against real queue mutation and retry scheduling.
def Delivery.codes(+n: Nat) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        +drop : Bool = Bool.or(Nat.is_eq(k, 202n), Bool.or(Nat.is_eq(k, 400n), Bool.or(Nat.is_eq(k, 401n), Bool.or(Nat.is_eq(k, 403n), Bool.or(Nat.is_eq(k, 409n), Nat.is_eq(k, 413n))))))
        C.Check.str("HTTP " ++ Nat.show(k) ++ " queue", T.Tm.state.json(Delivery.after(k, 0n)), T.Tm.state.json(T.TmState{"", "0.11.4", "2026-10-20", False{}, "0", Bool.pick(List<&2, T.TmEv>, drop, [Delivery.ev("0.11.4")], [Delivery.ev("0.11.3"), Delivery.ev("0.11.4")]), Bool.pick(Nat, drop, 0n, 3700n), 0n, True{}}))
        Delivery.codes(k)

def main() -> IO(Unit):
  do IO<Unit>:
    Delivery.codes(600n)
    C.Check.str("long Retry-After wins", Nat.show(T.TmState.next(Delivery.after(408n, 7200n))), "7300")
    C.Check.str("short Retry-After retains hour floor", Nat.show(T.TmState.next(Delivery.after(302n, 1n))), "3700")
    C.Check.str("202 removes only submitted event", Nat.show(List.length(&2, T.TmEv, T.TmState.queue(Delivery.after(202n, 0n)))), "1")
