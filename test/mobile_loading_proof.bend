import Base
import ../src/core/json.bend as J
import ../src/core/presentation.bend as P
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/mailview.bend as MV
import ../src/core/outbox.bend as O

law state_kept:
  for +u: U.Ui
  for +p: J.Json
  {U.Ui.state(P.Session.adopt(u, p)) == U.Ui.state(u) : M.State}

law seq_kept:
  for +u: U.Ui
  for +p: J.Json
  {U.Ui.seq(P.Session.adopt(u, p)) == U.Ui.seq(u) : Nat}

law bodies_kept:
  for +u: U.Ui
  for +p: J.Json
  {U.Mailv.cache(P.Session.adopt(u, p)) == U.Mailv.cache(u) : MV.Cache}

law credit_generation_kept:
  for +c: O.Cr
  for +at: Nat
  for +more: Bool
  for +rest: List<&2, String>
  {O.Cr.gen(P.Session.history_credit(c, at, more, rest)) == O.Cr.gen(c) : U32}

law credit_room_kept:
  for +c: O.Cr
  for +at: Nat
  for +more: Bool
  for +rest: List<&2, String>
  {O.Cr.room(P.Session.history_credit(c, at, more, rest)) == O.Cr.room(c) : Bool}

law credit_over_kept:
  for +c: O.Cr
  for +at: Nat
  for +more: Bool
  for +rest: List<&2, String>
  {O.Cr.over(P.Session.history_credit(c, at, more, rest)) == O.Cr.over(c) : Bool}

def state_kept(u, p):
  match u:
    case U.Ui{st, sel, dr, live, open, online, now, adding, panel, version, rid, want, error, note, info, outbox, stores}: {==}

def seq_kept(u, p):
  match u:
    case U.Ui{st, sel, dr, live, open, online, now, adding, panel, version, rid, want, error, note, info, outbox, stores}: {==}

def bodies_kept(u, p):
  match u:
    case U.Ui{st, sel, dr, live, open, online, now, adding, panel, version, rid, want, error, note, info, outbox, U.MailvLocal{terms, mail}}: {==}

def credit_generation_kept(c, at, more, rest):
  match c:
    case O.Cr{g, s, a, b, k, native, boot, old, fl, fseq, wait, xs}: {==}

def credit_room_kept(c, at, more, rest):
  match c:
    case O.Cr{g, s, a, b, k, native, boot, old, fl, fseq, wait, xs}: {==}

def credit_over_kept(c, at, more, rest):
  match c:
    case O.Cr{g, s, a, b, k, native, boot, old, fl, fseq, wait, xs}: {==}
