import Base
import ./auth.bend as A
import ./http.bend as H
import ./json.bend as J

def Desktop.bool_eq(a: Bool, b: Bool) -> Bool:
  match a b:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def Desktop.strings(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: J.Str{h} <> Desktop.strings(t)

def Desktop.digit(+u: U32) -> Char:
  Char.from_u32(Bool.pick(U32, U32.is_lt(u, 10), U32.add(48, u), U32.add(87, u)))

def Desktop.hex_go(n: Nat, +u: U32, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+k: Desktop.hex_go(k, U32.shrn(u, 4n), SCon{Desktop.digit(U32.and(u, 15)), acc})

def Desktop.hex(u: U32) -> String:
  Desktop.hex_go(8n, u, "")

# Bounded tail walk counts UTF-8 payload bytes without allocating another
# potentially megabyte list. Protocol stamping reserves at most 64 bytes.
def Desktop.char_bytes(+u: U32) -> Nat:
  Bool.pick(Nat, U32.is_lt(u, 128), 1n, Bool.pick(Nat, U32.is_lt(u, 2048), 2n, Bool.pick(Nat, U32.is_lt(u, 65536), 3n, 4n)))

def Desktop.bytes_go(s: String, +left: Nat, valid: Bool) -> Bool:
  match s valid:
    case _ False{}: False{}
    case SNil{} True{}: True{}
    case SCon{Chr{+u}, t} True{}:
      Desktop.bytes_go(t, Nat.sub(left, Desktop.char_bytes(u)), Nat.is_ge(left, Desktop.char_bytes(u)))

def Desktop.bytes_within(s: String, limit: Nat) -> Bool:
  Desktop.bytes_go(s, limit, True{})

# Direct desktop transport never inherits the ordinary localhost/cookie gate.
def Desktop.headers.count(xs: List<&2, H.Header>, +key: String) -> Nat:
  match xs:
    case Nil{}: 0n
    case H.Header{+k, _} <> t:
      Nat.add(Bool.pick(Nat, String.eq(String.to_lower(k), key), 1n, 0n), Desktop.headers.count(t, key))

def Desktop.auth(+peer: String, +method: String, +path: String, +hs: List<&2, H.Header>, +token: String) -> Bool:
  Bool.and(String.eq(method, "GET"), Bool.and(String.eq(path, "/desktop/browser/v1"),
    Bool.and(Bool.or(String.eq(peer, "127.0.0.1"), String.eq(peer, "::1")),
    Bool.and(Bool.not(String.is_empty(token)), Bool.and(Nat.is_eq(Desktop.headers.count(hs, "authorization"), 1n),
    Bool.and(A.Auth.same(H.Http.header_of(hs, "authorization"), "Bearer " ++ token),
    Bool.and(Nat.is_eq(Desktop.headers.count(hs, "host"), 1n), Bool.and(A.Auth.local.host(H.Http.header_of(hs, "host")),
    Bool.and(Nat.is_eq(Desktop.headers.count(hs, "origin"), 0n),
    Bool.and(String.is_empty(H.Http.header_of(hs, "tailscale-user-login")),
      String.eq(String.to_lower(H.Http.header_of(hs, "upgrade")), "websocket")))))))))))

type Target is Data:
  Target{owner: String, tab: String, generation: Nat}

def Target.owner(t: Target) -> String:
  match t: case Target{o, _, _}: o

def Target.tab(t: Target) -> String:
  match t: case Target{_, t, _}: t

def Target.generation(t: Target) -> Nat:
  match t: case Target{_, _, g}: g

def Target.eq(a: Target, b: Target) -> Bool:
  match a b:
    case Target{o, t, g} Target{o2, t2, g2}:
      Bool.and(String.eq(o, o2), Bool.and(String.eq(t, t2), Nat.is_eq(g, g2)))

def Target.json(t: Target) -> J.Json:
  match t:
    case Target{o, t, g}:
      J.Json.obj([J.KV{"owner", J.Str{o}}, J.KV{"tabId", J.Str{t}}, J.KV{"generation", J.Num{Nat.show(g)}}])

# Generation is a canonical natural-number JSON field; strings/fractions refuse.
# Reject oversized raw numerals before Nat.read: the native immediate range
# is smaller than JavaScript's safe-integer range. IDs/sequences are uint32.
def Target.number_bounded(short: Bool, +s: String) -> Bool:
  match short:
    case False{}: False{}
    case True{}:
      +n = J.Json.get_nat(J.Json.obj([J.KV{"n", J.Num{s}}]), "n", 0n)
      Bool.and(Nat.is_le(n, 4294967295n), String.eq(s, Nat.show(n)))

def Target.number(j: J.Json) -> Bool:
  match j:
    case J.Num{+s}: Target.number_bounded(Desktop.bytes_within(s, 10n), s)
    case _: False{}

def Target.decode_generation(valid: Bool, j: J.Json) -> Nat:
  match valid:
    case False{}: 0n
    case True{}: J.Json.get_nat(j, "generation", 0n)

def Target.fields(fs: J.Json) -> Nat:
  match fs:
    case J.Obj{xs}: Target.fields(xs)
    case J.Field{k, _, t}: Nat.add(1n, Target.fields(t))
    case _: 0n

def Target.valid(+j: J.Json) -> Bool:
  Bool.and(Nat.is_eq(Target.fields(j), 3n), Bool.and(Bool.not(String.is_empty(J.Json.get_str(j, "owner", ""))),
    Bool.and(Bool.not(String.is_empty(J.Json.get_str(j, "tabId", ""))),
      Target.number(Maybe.default(&2, J.Json, J.Json.get(j, "generation"), J.Null{})))))

def Target.decode(+j: J.Json) -> Target:
  Target{J.Json.get_str(j, "owner", ""), J.Json.get_str(j, "tabId", ""), Target.decode_generation(Target.number(J.Json.get_obj(j, "generation")), j)}

type Grant is Data:
  Grant{epoch: String, controller: String, target: Target, revision: Nat, expires: Nat, drive: String, recording: Bool}

def Grant.target(g: Grant) -> Target:
  match g: case Grant{_, _, t, _, _, _, _}: t

def Grant.revision(g: Grant) -> Nat:
  match g: case Grant{_, _, _, r, _, _, _}: r

def Grant.drive(g: Grant) -> String:
  match g: case Grant{_, _, _, _, _, d, _}: d

def Grant.recording(g: Grant) -> Bool:
  match g: case Grant{_, _, _, _, _, _, r}: r

def Grant.current(g: Grant, epoch: String, controller: String, target: Target, revision: Nat, now: Nat) -> Bool:
  match g:
    case Grant{e, c, t, r, expires, _, _}:
      Bool.and(String.eq(e, epoch), Bool.and(String.eq(c, controller), Bool.and(Target.eq(t, target),
        Bool.and(Nat.is_eq(r, revision), Nat.is_lt(now, expires)))))

# No wildcard CDP, foreign sessions, arbitrary init script, file upload or global
# Browser/Target/Storage escape. DOM/AX/Runtime still require exact owner authority.
def Desktop.methods() -> List<&2, String>:
  ["DOM.getDocument", "DOM.describeNode", "DOM.querySelector", "DOM.querySelectorAll", "DOM.resolveNode", "DOM.getBoxModel", "DOM.focus",
    "Accessibility.getFullAXTree", "Accessibility.getPartialAXTree", "Runtime.evaluate", "Runtime.callFunctionOn", "Runtime.getProperties", "Runtime.releaseObject", "Runtime.releaseObjectGroup",
    "Page.navigate", "Page.reload", "Page.stopLoading", "Page.getNavigationHistory", "Page.navigateToHistoryEntry", "Page.getLayoutMetrics",
    "Input.dispatchMouseEvent", "Input.dispatchKeyEvent", "Input.insertText", "Input.imeSetComposition"]

def Desktop.member(xs: List<&2, String>, +s: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case h <> t: Bool.or(String.eq(h, s), Desktop.member(t, s))

def Desktop.agent(+g: Grant, +epoch: String, +controller: String, +target: Target, +revision: Nat, +now: Nat, method: String) -> Bool:
  Bool.and(Grant.current(g, epoch, controller, target, revision, now),
    Bool.and(String.eq(Grant.drive(g), "agent"), Desktop.member(Desktop.methods(), method)))

def Desktop.person(+g: Grant, epoch: String, controller: String, target: Target, revision: Nat, now: Nat) -> Bool:
  Bool.and(Grant.current(g, epoch, controller, target, revision, now), String.eq(Grant.drive(g), "person"))

def Desktop.record(+g: Grant, epoch: String, controller: String, target: Target, revision: Nat, now: Nat) -> Bool:
  Bool.and(Grant.current(g, epoch, controller, target, revision, now), Grant.recording(g))

# Canonical Teach drive is deliberately not supplied by the shell.
def Desktop.drive(+known: Bool, +teachDrive: String) -> String:
  match known:
    case False{}: "none"
    case True{}: Bool.pick(String, String.is_empty(teachDrive), "agent", "person")

def Desktop.recording(known: Bool, mode: String) -> Bool:
  Bool.and(known, String.eq(mode, "rec"))

def Desktop.error(+id: String, +message: String, dispatched: Bool) -> String:
  J.Json.show(J.Json.obj([J.KV{"id", J.Str{id}}, J.KV{"ok", J.Flag{False{}}},
    J.KV{"error", J.Str{message}}, J.KV{"dispatched", J.Flag{dispatched}}]))

def Desktop.field(hit: Bool, k: String, v: J.Json, rest: J.Json) -> J.Json:
  match hit:
    case True{}: rest
    case False{}: J.Field{k, v, rest}

def Desktop.drop(fs: J.Json, +key: String) -> J.Json:
  match fs:
    case J.Field{+k, v, t}:
      Desktop.field(String.eq(k, key), k, v, Desktop.drop(t, key))
    case _: J.End{}

def Desktop.put(j: J.Json, +key: String, v: J.Json) -> J.Json:
  match j:
    case J.Obj{fs}: J.Obj{J.Field{key, v, Desktop.drop(fs, key)}}
    case _: J.Json.obj([J.KV{key, v}])

def Desktop.unique(j: J.Json, +seen: List<&2, String>) -> Bool:
  match j:
    case J.Obj{fs}: Desktop.unique(fs, Nil{})
    case J.Arr{xs}: Desktop.unique(xs, Nil{})
    case J.Field{+k, v, t}:
      Bool.and(Bool.not(Desktop.member(seen, k)), Bool.and(Desktop.unique(v, Nil{}), Desktop.unique(t, k <> seen)))
    case J.Item{v, t}: Bool.and(Desktop.unique(v, Nil{}), Desktop.unique(t, Nil{}))
    case _: True{}
