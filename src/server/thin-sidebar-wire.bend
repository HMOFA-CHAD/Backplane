import Base
import ../core/json.bend as J
import ../core/thin-wire.bend as W
import ../web/sidebar-slot.bend as S
import ./thin-actor.bend as A
import ./thin-view.bend as V
import ./thin-content-eq.bend as E

# One acknowledged sidebar per surviving actor. The private dependency key is
# never sent. Its ordinary render memo remains a complete picture, including
# when this transport replaces the sidebar in one outgoing reply.
type Output is Data:
  Output{actors: List<&2, A.Actor>, result: J.Json}

def Region.key(ms: List<&2, A.Memo>) -> String:
  match ms:
    case Nil{}: ""
    case A.Sidebar{key, _} <> _: key
    case _ <> rest: Region.key(rest)

def Region.token(ms: List<&2, A.Memo>, +key: String) -> String:
  match ms:
    case Nil{}: ""
    case A.SidebarWire{+saved, token} <> _: Bool.pick(String, String.eq(saved, key), token, "")
    case _ <> rest: Region.token(rest, key)

def Region.drop(ms: List<&2, A.Memo>) -> List<&2, A.Memo>:
  match ms:
    case Nil{}: Nil{}
    case A.SidebarWire{_, _} <> rest: Region.drop(rest)
    case m <> rest: m <> Region.drop(rest)

def Region.save(a: A.Actor, key: String, token: String) -> A.Actor:
  match a:
    case A.Actor{u, view, target, pending, reads, dirty, ms}:
      A.Actor{u, view, target, pending, reads, dirty, A.SidebarWire{key, token} <> Region.drop(ms)}

def Region.marker() -> J.Json:
  J.Json.obj([J.KV{"type", J.Str{"element"}}, J.KV{"tag", J.Str{"bp-sidebar-ref"}}, J.KV{"key", J.Str{"sidebar"}},
    J.KV{"attrs", J.Json.arr(Nil{})}, J.KV{"kids", J.Json.arr(Nil{})}])

# Traverse only outside the matched sidebar; never inspect/rewrite its rows.
def Region.replace.go(o: J.Json, hit: Bool) -> J.Json:
  match o hit:
    case _ True{}: Region.marker()
    case J.Obj{fs} False{}: J.Obj{Region.replace.go(fs, False{})}
    case J.Field{k, +v, tail} False{}:
      J.Field{k, Region.replace.go(v, S.Slot.is(v, "aside")), Region.replace.go(tail, False{})}
    case J.Arr{items} False{}: J.Arr{Region.replace.go(items, False{})}
    case J.Item{+head, tail} False{}:
      J.Item{Region.replace.go(head, S.Slot.is(head, "aside")), Region.replace.go(tail, False{})}
    case _ _: o

def Region.result(+reuse: Bool, +res: J.Json, +token: String) -> J.Json:
  +shown = J.Json.get_obj(res, "shown")
  V.Obj.put(V.Obj.put(res, "shown", Bool.pick(J.Json, reuse, Region.replace.go(shown, S.Slot.is(shown, "aside")), shown)),
    "sidebarRegion", J.Json.obj([J.KV{"version", J.Num{"1"}}, J.KV{"token", J.Str{token}}, J.KV{"base", J.Str{Bool.pick(String, reuse, token, "")}}]))

def Region.can_reuse(+previous: String, +ack: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(previous)), String.eq(previous, ack))

# An opt-in ordinary read may bind its fresh full-sequence picture key to
# the same receipt only after comparing the actual newly-rendered sidebar.
# Neither SidebarImage nor a metadata revision grants this authority.
def Content.drop(ms: List<&2, A.Memo>) -> List<&2, A.Memo>:
  match ms:
    case Nil{}: Nil{}
    case A.SidebarSent{_, _, _} <> rest: Content.drop(rest)
    case m <> rest: m <> Content.drop(rest)

def Content.save(ok: Bool, a: A.Actor, scope: String, token: String, node: J.Json) -> A.Actor:
  match ok a:
    case True{} A.Actor{u, view, target, pending, reads, dirty, ms}:
      A.Actor{u, view, target, pending, reads, dirty, A.SidebarSent{scope, token, node} <> Content.drop(ms)}
    case False{} A.Actor{u, view, target, pending, reads, dirty, ms}:
      A.Actor{u, view, target, pending, reads, dirty, Content.drop(ms)}

def Content.target(a: A.Actor, p: J.Json) -> Bool:
  match a:
    case A.Actor{_, _, target, _, _, _, _}: W.Target.same(target, J.Json.get_obj(p, "target"))

def Content.enabled(+a: A.Actor, +p: J.Json, +res: J.Json) -> Bool:
  Bool.and(J.Json.get_bool(J.Json.get_obj(p, "sidebarRegion"), "exactContent", False{}),
    Bool.and(String.is_empty(J.Json.get_str(p, "action", "")),
    Bool.and(Bool.not(String.is_empty(J.Json.get_str(p, "hub", ""))),
    Bool.and(Bool.not(String.is_empty(J.Json.get_str(p, "epoch", ""))),
    Bool.and(Bool.not(String.is_empty(J.Json.get_str(p, "generation", ""))),
    Bool.and(Bool.not(Maybe.is_some(&2, J.Json, J.Json.get(res, "nextTarget"))),
      Bool.and(Content.target(a, p), E.ContentEq.same(J.Json.get_obj(res, "cmds"), J.Arr{J.End{}}))))))))

def Content.scope(+a: A.Actor, +p: J.Json) -> String:
  J.Json.show(J.Json.obj([J.KV{"hub", J.Str{J.Json.get_str(p, "hub", "")}},
    J.KV{"generation", J.Str{J.Json.get_str(p, "generation", "")}}, J.KV{"epoch", J.Str{J.Json.get_str(p, "epoch", "")}},
    J.KV{"view", J.Str{A.Sidebar.view(a)}}, J.KV{"target", J.Json.get_obj(p, "target")}]))

def Content.equal(ok: Bool, old: J.Json, node: J.Json) -> Bool:
  match ok:
    case False{}: False{}
    case True{}: E.ContentEq.same(old, node)

def Content.matches(ms: List<&2, A.Memo>, +scope: String, +ack: String, node: J.Json) -> Bool:
  match ms:
    case Nil{}: False{}
    case A.SidebarSent{saved, token, old} <> _:
      Content.equal(Bool.and(String.eq(saved, scope), Region.can_reuse(token, ack)), old, node)
    case _ <> rest: Content.matches(rest, scope, ack, node)

def Content.previous(exact: Bool, a: A.Actor, key: String, ack: String) -> String:
  match exact:
    case True{}: ack
    case False{}: Region.token(A.Sidebar.memos(a), key)

# A hit already compares to a bounded sent value; misses can retain at most
# one serialized sidebar of 128KiB. Oversize output still follows the full path.
def Content.bounded(exact: Bool, node: J.Json) -> Bool:
  match exact:
    case True{}: True{}
    case False{}: Nat.is_le(J.Json.bytes(node), 131072n)

def Content.send(+a: A.Actor, +res: J.Json, +p: J.Json, +key: String, +scope: String, +node: J.Json) -> Output:
  +ack = J.Json.get_str(J.Json.get_obj(p, "sidebarRegion"), "token", "")
  +exact = Content.matches(A.Sidebar.memos(a), scope, ack, node)
  +previous = Content.previous(exact, a, key, ack)
  +reuse = Region.can_reuse(previous, ack)
  +token = Bool.pick(String, reuse, previous, Nat.show(J.Json.get_nat(p, "requestRevision", 0n)))
  Output{[Content.save(Content.bounded(exact, node), Region.save(a, key, token), scope, token, node)], Region.result(reuse, res, token)}

def Region.send.original(+a: A.Actor, +res: J.Json, +p: J.Json, +key: String) -> Output:
  +previous = Region.token(A.Sidebar.memos(a), key)
  +reuse = Region.can_reuse(previous, J.Json.get_str(J.Json.get_obj(p, "sidebarRegion"), "token", ""))
  +token = Bool.pick(String, reuse, previous, Nat.show(J.Json.get_nat(p, "requestRevision", 0n)))
  Output{[Region.save(a, key, token)], Region.result(reuse, res, token)}

def Region.send.kind(exact: Bool, +a: A.Actor, +res: J.Json, +p: J.Json, key: String) -> Output:
  match exact:
    case True{}: Content.send(a, res, p, key, Content.scope(a, p), S.Slot.sidebar(J.Json.get_obj(res, "shown")))
    case False{}: Region.send.original(Content.save(False{}, a, "", "", J.Null{}), res, p, key)

def Region.send(+a: A.Actor, +res: J.Json, +p: J.Json, key: String) -> Output:
  Region.send.kind(Content.enabled(a, p, res), a, res, p, key)

def Region.checked(ok: Bool, a: A.Actor, res: J.Json, p: J.Json, key: String) -> Output:
  match ok:
    case True{}: Region.send(a, res, p, key)
    case False{}: Output{[Content.save(False{}, a, "", "", J.Null{})], res}

def Region.output(web: Bool, actors: List<&2, A.Actor>, +res: J.Json, +p: J.Json) -> Output:
  match actors:
    case +a <> Nil{}:
      +key = Region.key(A.Sidebar.memos(a))
      +offered = W.Wire.version(Maybe.default(&2, J.Json, J.Json.get(J.Json.get_obj(p, "sidebarRegion"), "version"), J.Null{}))
      +revision = W.Wire.positive(W.Wire.nat(p, "requestRevision", 4294967295n))
      +sidebar = S.Slot.is(S.Slot.sidebar(J.Json.get_obj(res, "shown")), "aside")
      Region.checked(Bool.and(web, Bool.and(offered, Bool.and(revision, Bool.and(Bool.not(String.is_empty(key)),
        Bool.and(J.Json.get_bool(res, "remoteReady", False{}), sidebar))))), a, res, p, key)
    case _: Output{actors, res}
