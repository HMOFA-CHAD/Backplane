import Base
import ../mailstore_test.bend as T
import ../mailbody_test.bend as B
import ../check.bend as C
import ../../src/server/mailstore.bend as S
import ../../src/server/perf.bend as P
import ../../src/server/host.bend as H
import ../../src/core/mailbody.bend as MB

def bench_result(r: S.StoreResult<Bool>, n: Nat, home: String, text: String, k: Unit -> IO(Unit)) -> IO(Unit):
  match r:
    case S.Stored{_}: k(Unit{})
    case _: IO.die(Unit, 1, "benchmark append failed at " ++ Nat.show(n) ++ " in " ++ home ++ " body bytes " ++ Nat.show(String.length(text)))

# Native emission plus a reproducible 1000 x 16 KiB append/read benchmark.
def bench(+n: Nat, +home: String, +text: String) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        r : S.StoreResult<Bool> <- S.MailStore.append(home, B.fixture("m" ++ Nat.show(k), "long", text, k))
        bench_result(r, k, home, text, u => bench(k, home, text))

def main() -> IO(Unit):
  do IO<Unit>:
    # host.c currently emits join helpers unconditionally, while their CBOR
    # buffer dependency is conditional. Exercise that existing codec here so
    # this small native target includes the same dependency as the real hub.
    # No socket, hub or user data is touched by this in-memory frame check.
    frame : List<&2, U32> <- H.Json.cbor_frame("null", "", "")
    C.Check.str("host effect linkage frame", Nat.show(List.length(&2, U32, frame)), "3")
    T.main()
    +home : String <- T.home()
    t0 : U32 <- P.Perf.us()
    bench(1000n, home ++ "/bench", B.long(14n, "x"))
    +t1 : U32 <- P.Perf.us()
    page : S.StoreResult<List<&2, MB.Body>> <- S.MailStore.read(home ++ "/bench", "long", "", 20n)
    t2 : U32 <- P.Perf.us()
    C.Check.str("1000 row newest page", T.status(List<&2, MB.Body>, page), "ok")
    IO.print("bench append_us=" ++ U32.show(U32.sub(t1, t0)) ++ " read_us=" ++ U32.show(U32.sub(t2, t1)))
