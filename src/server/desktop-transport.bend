import Base
import ./host.bend as H
import ../core/http.bend as W
import ../core/utf8.bend as U
import ../core/json.bend as J
import ../core/desktop-browser.bend as D

# Private text WebSocket IO. Does not share the public CBOR UI writer or expose
# recorder frames through UI broadcasts. The hub owns the authenticated channel.
type Input is Data:
  Input{kind: String, text: String}

def Transport.sent(r: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Socket):
  (s, _) = r
  IO.pure(Socket, s)

def Transport.send(s: Socket, text: String) -> IO(Socket):
  IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Socket, H.Sock.send_bytes(s, W.Ws.text(text)), r => Transport.sent(r))

def Transport.wrote(r: Socket & Result<&1, &1, U32 & String, Unit>, +out: Chan(String), k: Socket -> IO(Unit)) -> IO(Unit):
  (s, result) = r
  match result:
    case Done{_}: k(s)
    case Fail{_}:
      do IO<Unit>:
        Chan.close(String, out)
        s2 : Socket <- H.Sock.shut_read(s)
        Socket.close(s2)

def Transport.stamped(line: String, sequence: Nat) -> String:
  J.Json.show(D.Desktop.put(Maybe.default(&2, J.Json, J.Json.parse(line), J.Null{}), "serverSequence", J.Num{Nat.show(sequence)}))

def Transport.write_checked(valid: Bool, s: Socket, +out: Chan(String), text: String, k: Socket -> IO(Unit)) -> IO(Unit):
  match valid:
    case True{}:
      IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Unit, H.Sock.send_until(s, W.Ws.text(text), 1000), r => Transport.wrote(r, out, k))
    case False{}:
      do IO<Unit>:
        Chan.close(String, out)
        s2 : Socket <- H.Sock.shut_read(s)
        Socket.close(s2)

def Transport.write_stamped(s: Socket, +out: Chan(String), +text: String, k: Socket -> IO(Unit)) -> IO(Unit):
  Transport.write_checked(D.Desktop.bytes_within(text, 1048576n), s, out, text, k)

def Transport.write(m: Maybe<&1, String>, s: Socket, +out: Chan(String), sequence: Nat, k: Socket -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{line}:
      Transport.write_stamped(s, out, Transport.stamped(line, sequence), k)
    case None{}:
      IO.bind(Socket, Unit, H.Sock.shut_read(s), s2 => Socket.close(s2))

def Transport.writer(fuel: Nat, s: Socket, +out: Chan(String), +sequence: Nat) -> IO(Unit):
  match fuel:
    case 0n: Socket.close(s)
    case 1n+n:
      IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, out), m => Transport.write(m, s, out, sequence, s2 => Transport.writer(n, s2, out, Nat.add(sequence, 1n))))

def Transport.close(s: Socket, +input: Chan(Input), +out: Chan(String)) -> IO(Unit):
  do IO<Unit>:
    Chan.close(String, out)
    s2 : Socket <- H.Sock.shut_read(s)
    Socket.close(s2)
    ok : Result<&1, &1, Input, Unit> <- Chan.send(Input, input, Input{"closed", ""})
    Chan.close(Input, input)

def Transport.more(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, buf: List<&2, U32>, +input: Chan(Input), +out: Chan(String), k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  (s, result) = r
  match result:
    case Done{Nil{}}: Transport.close(s, input, out)
    case Done{bs}: k(s, List.append(&2, U32, buf, bs))
    case Fail{_}: Transport.close(s, input, out)

def Transport.frame(ok: Bool, op: U32, payload: List<&2, U32>, s: Socket, rest: List<&2, U32>, +input: Chan(Input), +out: Chan(String), k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match ok:
    case False{}: Transport.close(s, input, out)
    case True{}:
      do IO<Unit>:
        sent : Result<&1, &1, Input, Unit> <- Chan.send(Input, input, Input{"frame", U.Utf8.decode(payload)})
        k(s, rest)

def Transport.decoded(got: Maybe<&2, W.Got>, s: Socket, +buf: List<&2, U32>, +input: Chan(Input), +out: Chan(String), k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match got:
    case Some{W.Got{W.Frame{fin, +op, payload}, rest}}:
      Transport.frame(Bool.and(fin, U32.is_eq(op, 1)), op, payload, s, rest, input, out, k)
    case None{}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536), r => Transport.more(r, buf, input, out, k))

# Bound the buffered frame BEFORE decoding its payload. Client masking required.
def Transport.scan(ok: Bool, s: Socket, +buf: List<&2, U32>, +input: Chan(Input), +out: Chan(String), k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match ok:
    case False{}: Transport.close(s, input, out)
    case True{}: Transport.decoded(W.Ws.decode(buf), s, buf, input, out, k)

def Transport.masked(bs: List<&2, U32>) -> Bool:
  match bs:
    case _ <> mask <> _: U32.is_ge(mask, 128)
    case _: True{}

def Transport.reader(fuel: Nat, s: Socket, +buf: List<&2, U32>, +input: Chan(Input), +out: Chan(String)) -> IO(Unit):
  match fuel:
    case 0n: Transport.close(s, input, out)
    case 1n+n:
      Transport.scan(Bool.and(Nat.is_le(List.length(&2, U32, buf), 1048590n), Transport.masked(buf)), s, buf, input, out,
        s2 => b2 => Transport.reader(n, s2, b2, input, out))
