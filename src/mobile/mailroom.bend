import Base
import ../core/client.bend as U
import ../core/mailview.bend as MV
import ../core/json.bend as J
import ../core/ref.bend as R
import ../web/mail-actions.bend as MA

# Phone projection only: all ordering, unread state, recipients and requests
# remain in shared Mailv. Text is complete; only the visible page is encoded.
def MMail.page() -> Nat:
  50n

def MMail.row(r: MV.Row) -> J.Json:
  match r:
    case MV.Row{+id, +subject, +who, +head, +at, +unread, +status, +project, +live, _}:
      J.Json.obj([J.KV{"id", J.Str{id}}, J.KV{"subject", J.Str{subject}}, J.KV{"who", J.Str{who}},
        J.KV{"head", J.Str{head}}, J.KV{"at", J.Json.nat(at)}, J.KV{"unread", J.Flag{unread}},
        J.KV{"status", J.Str{status}}, J.KV{"project", J.Str{project}}, J.KV{"live", J.Flag{live}}])

def MMail.rows(rs: List<&2, MV.Row>) -> List<&2, J.Json>:
  match rs:
    case Nil{}: Nil{}
    case r <> t: MMail.row(r) <> MMail.rows(t)

def MMail.list.rows(search: Bool, +u: U.Ui) -> List<&2, MV.Row>:
  match search:
    case False{}: MV.Mv.rows(U.Mailv.cache(u), U.Mailv.key(u), U.Mailv.scroll(u), MMail.page())
    case True{}: List.take(&2, MV.Row, List.drop(&2, MV.Row, MV.Find.hits(U.Mailv.find(u)), U.Mailv.scroll(u)), MMail.page())

def MMail.list.total(search: Bool, +u: U.Ui) -> Nat:
  match search:
    case False{}: MV.Mv.total(U.Mailv.cache(u), U.Mailv.key(u))
    case True{}: List.length(&2, MV.Row, MV.Find.hits(U.Mailv.find(u)))

def MMail.source.k(thread: Bool, bot: Bool, +from: String) -> String:
  match thread bot:
    case True{} _: R.Ref.uri(R.Ref.thread(String.drop(from, 7n)))
    case False{} True{}: R.Ref.uri(R.Ref.bot(String.drop(from, 4n)))
    case _ _: ""

def MMail.source(+from: String) -> String:
  MMail.source.k(String.starts_with(from, "thread:"), String.starts_with(from, "bot:"), from)

def MMail.message(m: MV.Bub) -> J.Json:
  match m:
    case MV.Bub{+id, +from, +who, +kind, +want, +at, +text, +lead}:
      J.Json.obj([J.KV{"id", J.Str{id}}, J.KV{"from", J.Str{from}}, J.KV{"who", J.Str{who}},
        J.KV{"kind", J.Str{kind}}, J.KV{"want", J.Str{want}}, J.KV{"at", J.Json.nat(at)},
        J.KV{"text", J.Str{text}}, J.KV{"lead", J.Flag{lead}}, J.KV{"sourceURI", J.Str{MMail.source(from)}}])

def MMail.messages(ms: List<&2, MV.Bub>) -> List<&2, J.Json>:
  match ms:
    case Nil{}: Nil{}
    case m <> t: MMail.message(m) <> MMail.messages(t)

def MMail.message.id(m: MV.Bub) -> String:
  match m:
    case MV.Bub{id, _, _, _, _, _, _, _}: id

def MMail.anchor(ms: List<&2, MV.Bub>) -> String:
  match ms:
    case Nil{}: ""
    case m <> _: MMail.message.id(m)

# Search only stable IDs, never mail text. Once found, no tail is traversed.
def MMail.find(ms: List<&2, MV.Bub>, +anchor: String, +at: Nat, found: Bool, +fallback: Nat) -> Nat:
  match ms found:
    case _ True{}: at
    case Nil{} False{}: fallback
    case +m <> +t False{}:
      +hit = String.eq(MMail.message.id(m), anchor)
      MMail.find(t, anchor, Bool.pick(Nat, hit, at, 1n+at), hit, fallback)

def MMail.first.k(empty: Bool, +ms: List<&2, MV.Bub>, +anchor: String, +fallback: Nat) -> Nat:
  match empty:
    case True{}: fallback
    case False{}: MMail.find(ms, anchor, 0n, False{}, fallback)

def MMail.first(+ms: List<&2, MV.Bub>, +anchor: String) -> Nat:
  MMail.first.k(String.is_empty(anchor), ms, anchor, Nat.sub(List.length(&2, MV.Bub, ms), MMail.page()))

def MMail.target(t: MV.Opt) -> J.Json:
  match t:
    case MV.Opt{addr, label}:
      J.Json.obj([J.KV{"address", J.Str{addr}}, J.KV{"label", J.Str{label}}])

def MMail.targets(ts: List<&2, MV.Opt>) -> List<&2, J.Json>:
  match ts:
    case Nil{}: Nil{}
    case t <> r: MMail.target(t) <> MMail.targets(r)

def MMail.window.anchor(show: Bool, +ms: List<&2, MV.Bub>, +first: Nat) -> String:
  match show:
    case False{}: ""
    case True{}: MMail.anchor(List.drop(&2, MV.Bub, ms, first))

def MMail.send(+u: U.Ui) -> String:
  MA.MA.get(u, "state")


def MMail.body.at(+u: U.Ui, +read: MV.Read, +ms: List<&2, MV.Bub>, +first: Nat) -> J.Json:
  J.Json.obj([J.KV{"id", J.Str{U.Ui.scratch(u, "@mr.conv")}}, J.KV{"subject", J.Str{MV.Read.subject(read)}},
    J.KV{"status", J.Str{MV.Read.status(read)}}, J.KV{"first", J.Json.nat(first)}, J.KV{"total", J.Json.nat(List.length(&2, MV.Bub, ms))},
    J.KV{"messages", J.Json.arr(MMail.messages(List.take(&2, MV.Bub, List.drop(&2, MV.Bub, ms, first), MMail.page())))},
    J.KV{"windowAnchor", J.Str{MMail.anchor(List.drop(&2, MV.Bub, ms, first))}},
    J.KV{"previousAnchor", J.Str{MMail.window.anchor(Nat.is_gt(first, 0n), ms, Nat.sub(first, 48n))}},
    J.KV{"nextAnchor", J.Str{MMail.window.anchor(Nat.is_lt(Nat.add(first, MMail.page()), List.length(&2, MV.Bub, ms)), ms, Nat.add(first, 48n))}},
    J.KV{"remoteEarlier", J.Flag{MV.Read.more(read)}},
    J.KV{"loading", J.Flag{Bool.not(String.is_empty(U.Ui.scratch(u, "@mr.read")))}},
    J.KV{"targets", J.Json.arr(MMail.targets(U.Mailv.targets(u)))},
    J.KV{"to", J.Str{U.Ui.scratch(u, "@mr.to")}}, J.KV{"draft", J.Str{U.Ui.scratch(u, "@f.mrreply")}},
    J.KV{"sendState", J.Str{MMail.send(u)}}])

def MMail.body.k(open: Bool, +u: U.Ui, +ms: List<&2, MV.Bub>) -> J.Json:
  match open:
    case False{}: J.Null{}
    case True{}:
      MMail.body.at(u, MV.Mv.read_of(U.Mailv.cache(u), U.Ui.scratch(u, "@mr.conv")), ms,
        MMail.first(ms, U.Ui.scratch(u, "@mr.mobile.anchor")))

def MMail.model.k(+search: Bool, +u: U.Ui) -> J.Json:
  J.Json.obj([J.KV{"owner", J.Str{U.Mailv.owner(u)}}, J.KV{"origin", J.Str{U.Ui.info(u, "origin")}}, J.KV{"filter", J.Str{U.Mailv.key(u)}},
    J.KV{"query", J.Str{U.Ui.scratch(u, "@f.mrsearch")}}, J.KV{"status", J.Str{U.Ui.scratch(u, "@mr.status")}},
    J.KV{"first", J.Json.nat(U.Mailv.scroll(u))}, J.KV{"total", J.Json.nat(MMail.list.total(search, u))},
    J.KV{"rows", J.Json.arr(MMail.rows(MMail.list.rows(search, u)))},
    J.KV{"loading", J.Flag{Bool.not(String.is_empty(U.Ui.scratch(u, "@mr.list")))}},
    J.KV{"searchCapped", J.Flag{MV.Find.capped(U.Mailv.find(u))}},
    J.KV{"body", MMail.body.k(Bool.not(String.is_empty(U.Ui.scratch(u, "@mr.conv"))), u, U.Mailv.bubbles(u))}])

def MMail.model(+u: U.Ui) -> J.Json:
  MMail.model.k(Bool.not(String.is_empty(U.Ui.scratch(u, "@f.mrsearch"))), u)
