import Base
import ./check.bend as C
import ./thin_terminal_output_test.bend as F
import ../src/server/term.bend as T
import ../src/server/terminal-output.bend as O
import ../src/core/client.bend as U
import ../src/core/outbox.bend as B
import ../src/core/json.bend as J
import ../src/server/thin-actor.bend as A

# Real actor branch and FIFO channels, no PTY/process/window is launched.
def done(st: T.TS) -> IO(Unit):
  IO.pure(Unit, Unit{})

def digest(m: Maybe<&1, T.TOut>) -> String:
  match m:
    case Some{T.TOut{_, pid, _}}: U32.show(pid)
    case Some{T.TTo{_, _, _, _, _}}: "none"
    case None{}: "closed"

def pid_case(+owner: String, +current: U32, +producer: U32) -> IO(String):
  do IO<String>:
    +input : Chan(List<&2, U32>) <- Chan.new(List<&2, U32>, 4)
    +out : Chan(T.TOut) <- Chan.new(T.TOut, 4)
    T.Term.fed(False{}, [T.Term{owner, input, current, 80, 24}], Nil{}, "a", producer, [90], out, done)
    # A sentinel after the actor call proves whether it forwarded a frame.
    ok : Result<&1, &1, T.TOut, Unit> <- Chan.send(T.TOut, out, T.TTo{0, "sentinel", 0, 0, Nil{}})
    first : Maybe<&1, T.TOut> <- Chan.recv(T.TOut, out)
    Chan.close(T.TOut, out)
    Chan.close(List<&2, U32>, input)
    return digest(first)

def offers(n: Nat, c: B.Cr) -> B.Cr:
  match n:
    case 0n: c
    case 1n+k: offers(k, B.Cr.offer(c, 32n))

def written(c: B.Cr) -> Nat:
  match c:
    case B.Cr{_, _, a, _, _, _, _, _, _, _, _, _}: a

def release(+generation: U32, +report: U32, offered: String, ack: Nat) -> String:
  +credit = B.Cr.drained(offers(16n, B.Cr.new(generation, False{}, False{}, 0n)), report, ack, 32n)
  Bool.show(O.Output.pending(True{}, U.Ui.info_set(O.Output.next(F.ui()), "local.terminal.offered", offered), "a", written(credit)))

def feed(a: A.Actor, byte: U32) -> A.Actor:
  A.Actor.message(a, True{}, "h", J.Json.obj([J.KV{"t", J.Str{"term"}}, J.KV{"thread", J.Str{"a"}}, J.KV{"pid", J.Json.u32(42)}, J.KV{"b", J.Json.arr([J.Json.u32(byte)])}]))

def main() -> IO(Unit):
  do IO<Unit>:
    +old : String <- pid_case("a", 43, 42)
    C.Check.str("old PID bytes rejected after same-owner process replacement", old, "none")
    +live : String <- pid_case("a", 43, 43)
    C.Check.str("current PID bytes forwarded once", live, "43")
    +other : String <- pid_case("b", 43, 43)
    C.Check.str("other terminal reader cannot feed selected owner", other, "none")
    +failure : String <- pid_case("a", 0, 0)
    C.Check.str("spawn failure still reaches visible terminal", failure, "0")
    C.Check.str("stale connection generation cannot release pending pane", release(3, 2, "8", 16n), "False")
    C.Check.str("matching writer completion releases one pending pane", release(3, 3, "8", 8n), "True")
    C.Check.str("old duplicate completion cannot release newer in-flight ordinal", release(3, 3, "9", 8n), "False")
    C.Check.str("new in-flight ordinal releases only on its completion", release(3, 3, "9", 9n), "True")
    C.Check.str("old writer report cannot release reconnected client", release(4, 3, "8", 16n), "False")
    C.Check.str("cleared pending pane is not sent twice", Bool.show(O.Output.pending(True{}, O.Output.offered(O.Output.next(F.ui()), 8n), "a", 16n)), "False")
    C.Check.str("closed owner cannot flush after writer completion", Bool.show(O.Output.pending(True{}, U.Ui.flag_off(O.Output.next(F.ui()), "term"), "a", 16n)), "False")
    +burst : A.Actor = feed(feed(feed(F.actor(), 65), 66), 67)
    C.Check.str("burst coalesces to latest watermark", U.Ui.info(A.Actor.ui(burst), "local.terminal.sequence"), "3")
    C.Check.str("burst keeps one latest pending flag", U.Ui.info(A.Actor.ui(burst), "local.terminal.pending"), "1")
    C.Check.str("burst leaves unrelated conversation clean", Bool.show(A.Actor.dirty(burst)), "False")
