import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/signal.bend as SIGREV

# Typed signal inputs prove the only canonical-history exemptions.
law signal_activity_input:
  for +st: M.State
  for th: String
  for act: String
  for tone: String
  for kind: String
  for summary: String
  for at: Nat
  {SIGREV.SignalInput.of(M.State.apply(st, M.ActivityLogged{th, act, tone, kind, summary, at})) == SIGREV.SignalInput.of(st) : SIGREV.SignalInput}

law signal_assistant_input:
  for +st: M.State
  for th: String
  for id: String
  for text: String
  for at: Nat
  {SIGREV.SignalInput.of(M.State.apply(st, M.MessagePosted{th, id, M.Assistant{}, text, at})) == SIGREV.SignalInput.of(st) : SIGREV.SignalInput}

law signal_system_input:
  for +st: M.State
  for th: String
  for id: String
  for text: String
  for at: Nat
  {SIGREV.SignalInput.of(M.State.apply(st, M.MessagePosted{th, id, M.System{}, text, at})) == SIGREV.SignalInput.of(st) : SIGREV.SignalInput}

law signal_user_revision:
  for th: String
  for id: String
  for text: String
  for at: Nat
  for old: Nat
  for head: Nat
  {SIGREV.SignalRevision.advance([M.MessagePosted{th, id, M.User{}, text, at}], old, head) == head : Nat}

def signal_activity_input(st, th, act, tone, kind, summary, at):
  match st:
    case M.State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw}: {==}

def signal_assistant_input(st, th, id, text, at):
  match st:
    case M.State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw}: {==}

def signal_system_input(st, th, id, text, at):
  match st:
    case M.State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw}: {==}

def signal_user_revision(th, id, text, at, old, head):
  {==}

def main() -> IO(Unit):
  C.Check.str("four typed-input dependency laws", "proved", "proved")
