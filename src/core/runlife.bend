import Base
import ./model.bend as M
import ./mail.bend as ML
import ./cmds.bend as CM
import ./adopt.bend as AD

# Private Mailroom runs own a turn, not a permanently resident SDK.
# Inspect raw RunSet ownership even when automation has since been disabled.
# The same guard governs retirement after commit and restart adoption.
def Life.terminal(t: M.TurnState) -> Bool:
  match t:
    case M.Completed{}: True{}
    case M.Failed{}: True{}
    case M.Interrupted{}: True{}
    case _: False{}

def Life.ask(xs: List<&2, M.Ask>, +th: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case M.Ask{_, +t, _, _, _, _, +open, _} <> rest:
      Bool.or(Bool.and(String.eq(t, th), open), Life.ask(rest, th))

def Life.thread(t: M.Thread) -> Bool:
  match t:
    case M.Thread{_, _, _, _, _, turn, pending, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Bool.and(Life.terminal(turn), Nat.is_eq(pending, 0n))

def Life.owned(r: Maybe<&2, ML.Run>, +s: M.State, +th: String) -> Bool:
  match r:
    case None{}: False{}
    case Some{+r}:
      Bool.and(Bool.not(ML.Run.live(r)), Bool.and(Life.thread(M.State.thread.get(s, th)),
        Bool.and(List.is_empty(&2, M.QItem, M.Queue.items(s, th)), Bool.and(Nat.is_eq(M.Work.busy(s, th), 0n),
          Bool.and(Bool.not(Life.ask(M.Asks.all(s), th)), Bool.not(String.eq(M.Setting.get(s, "run.pending." ++ th, ""), "on")))))))

def Life.finished(+s: M.State, +th: String) -> Bool:
  Life.owned(ML.Box.run_of(M.State.mail(s), th), s, th)

# A terminal state alone cannot discard an accepted/queued command or an
# input waiting for images. Lifecycle results precede command completion.
def Life.retire(+s: M.State, +th: String, +cmds: CM.Cmds, held: Bool) -> Bool:
  Bool.and(Life.finished(s, th), Bool.and(Bool.not(held), Bool.and(Bool.not(CM.Cmds.wake(cmds)), Bool.not(CM.Cmds.open(CM.Cmds.cs(cmds), "")))))

def Life.adopt(v: AD.AVerdict, +s: M.State) -> AD.AVerdict:
  match v:
    case AD.VAdopt{AD.AEntry{+t, +p, +i, +fd, +hd, +g, +k, +c}}:
      Bool.pick(AD.AVerdict, Life.retire(s, t, c, False{}), AD.VStop{AD.AEntry{t, p, i, fd, hd, g, k, c}}, AD.VAdopt{AD.AEntry{t, p, i, fd, hd, g, k, c}})
    case _: v
