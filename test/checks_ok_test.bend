import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/hub.bend as H
import ../src/server/review.bend as RV

# A project's own checks (.backplane/checks.json) wait for the person's OK:
# the hub asks in the thread (tool "checks_ok", id "checks:<sha256>:<n>"),
# "Run them" trusts that checks.json (ChecksTrust), anything else only
# closes the ask; the checks child runs them once their hash is trusted
# (review.bend's Rvc.trusted).

def hx() -> String:
  "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

def log() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "lamp", "/tmp/lamp", 1n},
   M.ThreadCreated{"t1", "p1", "Checks", M.Local{}, "", "", "claude", "", 1n},
   M.AskOpened{"checks:" ++ hx() ++ ":5", "t1", "input", "checks_ok", "Run this project's own checks?", "Run them\nNot now", 3n}]

def st() -> M.State:
  M.State.replay(log(), M.State.empty())

def trusts(os: List<&2, H.Out>) -> String:
  match os:
    case Nil{}:
      ""
    case H.ChecksTrust{+h} <> t:
      h ++ " " ++ trusts(t)
    case _ <> t:
      trusts(t)

def outs(s: H.Step) -> List<&2, H.Out>:
  match s:
    case H.Step{_, os}:
      os

def answered(+ans: String) -> String:
  trusts(outs(H.Hub.answer(st(), 9n, 0, "r", "checks:" ++ hx() ++ ":5", ans)))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("the ask's id names its checks", H.Checks.hash("checks:" ++ hx() ++ ":5"), hx())
    C.Check.str("Run them trusts them", answered("Run them"), hx() ++ " ")
    C.Check.str("Not now trusts nothing", answered("Not now"), "")
    C.Check.str("a dismissal trusts nothing", answered(""), "")
    C.Check.str("an open question for them counts", Bool.show(H.Checks.asked(st(), hx())), "True")
    C.Check.str("other checks have none", Bool.show(H.Checks.asked(st(), "ff")), "False")
    C.Check.str("a trusted hash is found among the lines", Bool.show(RV.Rvc.trusted(["aa", hx(), "bb"], hx())), "True")
    C.Check.str("an untrusted one is not", Bool.show(RV.Rvc.trusted(["aa", "bb"], hx())), "False")
