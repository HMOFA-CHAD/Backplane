import Base
import ../../src/app/win.bend as W

# The window's input events, with a real X window (run under Xvfb): ime
# events queued before the app drains them each keep their own text, in
# order; a long commit arrives whole; no unknown event is a quit.
#   scripts/build-app.sh test/native/ime_events.bend build/ime_events
#   DISPLAY=:91 BACKPLANE_NO_IME=1 build/ime_events

def ok(+name: String, +got: String, +want: String) -> IO(Unit):
  IO.print(Bool.pick(String, String.eq(got, want), "ok " ++ name, "FAIL " ++ name ++ ": got " ++ got ++ " want " ++ want))

# the ime events among the decoded, as "c<id>" and "p<id>"
def ids(es: List<&2, W.WinEv>) -> List<&2, U32>:
  match es:
    case Nil{}:
      Nil{}
    case W.WCommit{id, _} <> t:
      id <> ids(t)
    case W.WPreedit{_, _, id, _, _, _, _} <> t:
      id <> ids(t)
    case _ <> t:
      ids(t)

def quits(es: List<&2, W.WinEv>) -> Nat:
  match es:
    case Nil{}:
      0n
    case W.WQuit{} <> t:
      1n+quits(t)
    case _ <> t:
      quits(t)

def firsts(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      ""
    case x <> t:
      U32.show(x) ++ " " ++ firsts(t)

def pair(r: Window & String & String) -> IO(Window & String):
  (w, (t, f)) = r
  IO.pure(Window & String, (w, t ++ "|" ++ f ++ ";"))

def cat(r: Window & String, p: Window & String) -> IO(Window & String):
  (w, acc) = p
  IO.pure(Window & String, (w, acc))

def one(x: U32, r: Window & String) -> IO(Window & String):
  (w, acc) = r
  IO.bind(Window & String, Window & String, IO.bind(Window & String & String, Window & String, W.Win.payload(w, x), pair), q => add(acc, q))

def add(acc: String, q: Window & String) -> IO(Window & String):
  (w, t) = q
  IO.pure(Window & String, (w, acc ++ t))

# fetch the payloads newest first, so each is shown not to depend on order
def fetch(w: Window, xs: List<&2, U32>) -> IO(Window & String):
  match xs:
    case Nil{}:
      IO.pure(Window & String, (w, ""))
    case x <> t:
      IO.bind(Window & String, Window & String, fetch(w, t), r => one(x, r))

def decoded(r: Window & List<&2, U32>) -> IO(Window & List<&2, W.WinEv>):
  (w, ws) = r
  IO.pure(Window & List<&2, W.WinEv>, (w, W.Win.decode(ws)))

def drain(w: Window) -> IO(Window & List<&2, W.WinEv>):
  IO.bind(Window & List<&2, U32>, Window & List<&2, W.WinEv>, W.Win.words(w), decoded)

def text_of(r: Window & String & String) -> IO(Window & String):
  (w, (t, _)) = r
  IO.pure(Window & String, (w, t))

def go2(w: Window, es: List<&2, W.WinEv>, +big: String) -> IO(Unit):
  do IO<Unit>:
    a : Window & String <- IO.bind(Window & String & String, Window & String, W.Win.payload(w, nth(ids(es), 0n)), text_of)
    b : Window & String <- IO.bind(Window & String & String, Window & String, W.Win.payload(fst(a), nth(ids(es), 1n)), text_of)
    ok("a long commit arrives whole", Bool.show(String.eq(snd(a), big)), "True")
    ok("and the next one is its own", snd(b), "after")
    m : Window & U32 <- W.Win.ime(fst(b))
    IO.print("mode " ++ U32.show(snd2(m)))

def fst(r: Window & String) -> Window:
  (w, _) = r
  w

def snd(r: Window & String) -> String:
  (_, t) = r
  t

def snd2(r: Window & U32) -> U32:
  (_, t) = r
  t

def go1(w: Window, es: List<&2, W.WinEv>) -> IO(Unit):
  do IO<Unit>:
    f : Window & String <- fetch(w, ids(es))
    ok("queued payloads keep their own text, in order", snd(f), "日本語😀|0000;にほん|222;あ|0;")
    ok("no stray quit", Nat.show(quits(es)), "0")
    +big : String = String.repeat("日本語ABC😀", 60000)
    w8 : Window <- W.Win.ime_inject(fst(f), 0, big)
    w9 : Window <- W.Win.ime_inject(w8, 0, "after")
    d2 : Window & List<&2, W.WinEv> <- drain(w9)
    go2(fst2(d2), snd3(d2), big)

def fst2(r: Window & List<&2, W.WinEv>) -> Window:
  (w, _) = r
  w

def snd3(r: Window & List<&2, W.WinEv>) -> List<&2, W.WinEv>:
  (_, e) = r
  e

def go(w: Window) -> IO(Unit):
  do IO<Unit>:
    w1 : Window <- W.Win.ime_inject(w, 0, "あ")
    w2 : Window <- W.Win.ime_inject(w1, 1, "にほん")
    w3 : Window <- W.Win.ime_inject(w2, 0, "日本語😀")
    w4 : Window <- W.Win.ime_inject(w3, 2, "")
    w5 : Window <- W.Win.ime_inject(w4, 0, "")
    d : Window & List<&2, W.WinEv> <- drain(w5)
    go1(fst2(d), snd3(d))

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, Window> <- W.Win.open("ime", 400, 300)
    go0(r)

def go0(r: Result<&1, &1, U32 & String, Window>) -> IO(Unit):
  match r:
    case Done{w}:
      go(w)
    case Fail{e}:
      IO.print("FAIL open")
