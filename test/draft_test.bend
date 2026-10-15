import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/client.bend as U

# A sent message never comes back to the composer: typed, sent, the thread
# left and opened again, the composer is empty, and the host was told to
# forget its copy in the step that sent it (a bot's thread too). A draft
# not sent survives a reopen and a restart. A draft kept by an older build
# after it was sent is forgotten when its thread is opened.

def ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

# the Keep commands, in order, as "thread=text;"
def keeps.go(cs: List<&2, U.Cmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case U.Keep{id, t} <> r:
      id ++ "=" ++ t ++ ";" ++ keeps.go(r)
    case _ <> r:
      keeps.go(r)

def keeps(a: U.Act) -> String:
  match a:
    case U.Act{_, cs}:
      keeps.go(cs)

# what the host has written down: every Keep applied in order
def disk.go(cs: List<&2, U.Cmd>, m: Map<&2, String>) -> Map<&2, String>:
  match cs:
    case Nil{}:
      m
    case U.Keep{id, t} <> r:
      disk.go(r, Map.set(&2, String, m, id, t))
    case _ <> r:
      disk.go(r, m)

def disk(a: U.Act, m: Map<&2, String>) -> Map<&2, String>:
  match a:
    case U.Act{_, cs}:
      disk.go(cs, m)

def state() -> M.State:
  M.State.replay([
    M.ThreadCreated{"t1", "p1", "A", M.Local{}, "", "", "claude", "", 1n},
    M.ThreadCreated{"t2", "p1", "B", M.Local{}, "", "", "claude", "", 1n},
    M.ThreadCreated{"tb", "", "Bub", M.Local{}, "", "", "claude", "", 1n},
    M.BotSet{"b1", "Bub", "tb", 0n, "", 1n},
    M.MessagePosted{"tb", "m0", M.User{}, "sent before", 2n},
    M.MessagePosted{"tb", "m1", M.Assistant{}, "ok", 3n}], M.State.empty())

def fresh() -> U.Ui:
  U.Ui.adopt.raw(U.Ui.init(100n), state())

# a restart: a fresh client, the kept drafts read back (as the hosts do)
def restored.go(ks: List<&2, String>, +m: Map<&2, String>, u: U.Ui) -> U.Ui:
  match ks:
    case Nil{}:
      u
    case +k <> t:
      restored.go(t, m, U.Ui.restore(u, k, U.Str.get(m, k)))

def restored(+m: Map<&2, String>) -> U.Ui:
  restored.go(Map.keys(&2, String, m), m, fresh())

def text(a: U.Act) -> String:
  U.Ui.draft_text(ui(a))

def main() -> IO(Unit):
  +m0 = Map.new(&2, String)
  # a thread: type, send, leave, come back
  +a1 = U.Ui.act(fresh(), "select", "t1")
  +a2 = U.Ui.act(ui(a1), "draft", "hello")
  +a3 = U.Ui.act(ui(a2), "send", "")
  +a4 = U.Ui.act(ui(a3), "select", "t2")
  +a5 = U.Ui.act(ui(a4), "select", "t1")
  # an unsent draft in t2
  +a6 = U.Ui.act(ui(a5), "select", "t2")
  +a7 = U.Ui.act(ui(a6), "draft", "keep me")
  +a8 = U.Ui.act(ui(a7), "select", "t1")
  +a9 = U.Ui.act(ui(a8), "select", "t2")
  # a bot's thread: type, send, leave, come back
  +b1 = U.Ui.act(ui(a9), "bot", "b1")
  +b2 = U.Ui.act(ui(b1), "draft", "hi bot")
  +b3 = U.Ui.act(ui(b2), "send", "")
  +b4 = U.Ui.act(ui(b3), "select", "t1")
  +b5 = U.Ui.act(ui(b4), "bot", "b1")
  # what the host holds after all of it, and a restart on it
  +d = disk(b5, disk(b4, disk(b3, disk(b2, disk(b1, disk(a9, disk(a8, disk(a7, disk(a6, disk(a5, disk(a4, disk(a3, disk(a2, disk(a1, m0))))))))))))))
  +r0 = restored(d)
  +r1 = U.Ui.act(r0, "select", "t1")
  +r2 = U.Ui.act(ui(r1), "select", "t2")
  +r3 = U.Ui.act(ui(r2), "bot", "b1")
  # an older build kept a bot's sent text: forgotten when it is opened
  +o0 = restored(Map.set(&2, String, Map.set(&2, String, m0, "tb", "sent before"), "t2", "not sent"))
  +o1 = U.Ui.act(o0, "bot", "b1")
  +o2 = U.Ui.act(ui(o1), "select", "t1")
  +o3 = U.Ui.act(ui(o2), "bot", "b1")
  +o4 = U.Ui.act(ui(o3), "select", "t2")
  # a restored draft the person changed is theirs, whatever it says
  +e0 = restored(Map.set(&2, String, m0, "tb", "sent"))
  +e1 = U.Ui.act(ui(U.Ui.act(e0, "select", "tb")), "draft", "sent before")
  +e2 = U.Ui.act(ui(U.Ui.act(ui(e1), "select", "t1")), "bot", "b1")
  do IO<Unit>:
    C.Check.str("typed", text(a2), "hello")
    C.Check.str("send forgets the copy in the same step", keeps(a3), "t1=;")
    C.Check.str("sent empties the composer", text(a3), "")
    C.Check.str("leaving keeps nothing", keeps(a4), "")
    C.Check.str("reopened empty", text(a5), "")
    C.Check.str("reopen writes nothing", keeps(a5), "")
    C.Check.str("unsent survives a reopen", text(a9), "keep me")
    C.Check.str("bot thread selected", U.Ui.sel(ui(b1)), "tb")
    C.Check.str("bot send forgets the copy in the same step", keeps(b3), "tb=;")
    C.Check.str("bot sent empties the composer", text(b3), "")
    C.Check.str("bot reopened empty", text(b5), "")
    C.Check.str("host keeps t1", U.Str.get(d, "t1"), "")
    C.Check.str("host keeps tb", U.Str.get(d, "tb"), "")
    C.Check.str("host keeps t2", U.Str.get(d, "t2"), "keep me")
    C.Check.str("restart: sent stays gone", text(r1), "")
    C.Check.str("restart: unsent survives", text(r2), "keep me")
    C.Check.str("restart: bot sent stays gone", text(r3), "")
    C.Check.str("old kept sent text forgotten on open", text(o1), "")
    C.Check.str("old kept sent text forgotten by the host", keeps(o1), "tb=;")
    C.Check.str("stays forgotten", text(o3), "")
    C.Check.str("checked once", keeps(o3), "")
    C.Check.str("old kept unsent text survives", text(o4), "not sent")
    C.Check.str("typed again is kept", text(e2), "sent before")
