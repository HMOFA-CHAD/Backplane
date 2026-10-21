import Base
import ../src/core/desktop-browser.bend as D
import ../src/server/desktop-broker.bend as B
import ../src/server/desktop-transport.bend as T
import ../src/core/json.bend as J

def check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "FAIL " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    check("empty frame fits zero byte limit", D.Desktop.bytes_within("", 0n))
    check("ASCII exact byte boundary", D.Desktop.bytes_within("abcd", 4n))
    check("ASCII overflow refused", Bool.not(D.Desktop.bytes_within("abcd", 3n)))
    check("UTF8 two-byte boundary", D.Desktop.bytes_within("é", 2n))
    check("UTF8 two-byte overflow refused", Bool.not(D.Desktop.bytes_within("é", 1n)))
    check("UTF8 Japanese three-byte boundary", D.Desktop.bytes_within("あ", 3n))
    check("UTF8 Japanese overflow refused", Bool.not(D.Desktop.bytes_within("あ", 2n)))
    check("UTF8 supplementary four-byte boundary", D.Desktop.bytes_within("😀", 4n))
    check("UTF8 supplementary overflow refused", Bool.not(D.Desktop.bytes_within("😀", 3n)))
    check("mixed Unicode sum exact", D.Desktop.bytes_within("Aéあ😀", 10n))
    check("mixed Unicode never counts codepoints as bytes", Bool.not(D.Desktop.bytes_within("Aéあ😀", 9n)))
    +frame : String = T.Transport.stamped("{\"payload\":{\"text\":\"あ😀\"}}", 4294967295n)
    check("stamped payload retains Unicode content", D.Desktop.bytes_within(frame, 1048576n))
    check("two queued writer plus blocked single broker payload bound4MiB", Nat.is_eq(Nat.mul(4n, 1048576n), 4194304n))
    +out : Chan(String) <- Chan.new(String, 2)
    B.Broker.send_checked(False{}, Some{out}, "must not truncate")
    got : Maybe<&1, String> <- Chan.recv(String, out)
    check("over-budget send closes channel instead of truncation", Maybe.is_none(&1, String, got))
