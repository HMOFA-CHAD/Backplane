import Base
import ./json.bend as J

# Secrets the agent never sees (pure; docs/secrets.md). The person pastes a
# key into a masked box; the hub keeps it in the vault
# (server/vault.bend, effects/vault.js: sealed at rest, the master key in
# the OS keychain) and agents only ever get a handle {secret, set}. A
# stored value lives in Bend only inside a SecVal, gathered in a Vault, and
# the only defs that take one apart are the masks below: Sec.mask (text),
# Sec.json (every string of a JSON tree) and Sec.clean (a Bool). Nothing
# answers a value as a String. test/tools/secret.mjs keeps SecVal{ and
# Vault{ inside this file, server/vault.bend and the proofs, and keeps
# every other type from naming them in a field, so no Change, mail,
# prompt, render or tool-result constructor can hold a value (laws sec_*).

type SecVal is Data:
  SecVal{text: String}

type Vault is Data:
  Vault{vals: List<&2, SecVal>}

# What may be stored
# ------------------
# A value the masks can cover: not empty and not starting with the mask's
# own character (U+2022), so the bullets a mask writes never spell it.
def Sec.ok(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, _}:
      Bool.not(Char.is_eq(Chr{8226}, c))

def Sec.keep.k(ok: Bool, +t: String, r: List<&2, SecVal>) -> List<&2, SecVal>:
  match ok:
    case True{}:
      SecVal{t} <> r
    case False{}:
      r

def Sec.keep(ts: List<&2, String>) -> List<&2, SecVal>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> r:
      Sec.keep.k(Sec.ok(t), t, Sec.keep(r))

# the vault from the values the effect holds (only the coverable ones;
# Sec.bad keeps any other from being stored at all)
def Sec.vault(ts: List<&2, String>) -> Vault:
  Vault{Sec.keep(ts)}

def Sec.valid.go(vs: List<&2, SecVal>) -> Bool:
  match vs:
    case Nil{}:
      True{}
    case SecVal{t} <> r:
      Bool.and(Sec.ok(t), Sec.valid.go(r))

def Sec.valid(v: Vault) -> Bool:
  match v:
    case Vault{vs}:
      Sec.valid.go(vs)

# nothing stored (every mask is then the identity, law sec_empty_id)
def Sec.empty(v: Vault) -> Bool:
  match v:
    case Vault{vs}:
      List.is_empty(&2, SecVal, vs)

def Sec.size(v: Vault) -> Nat:
  match v:
    case Vault{vs}:
      List.length(&2, SecVal, vs)

# Clean text
# ----------
# no stored value occurs in s (String.contains is native in the hub's
# bundle, scripts/js-native.py)
def Sec.clean.go(vs: List<&2, SecVal>, +s: String) -> Bool:
  match vs:
    case Nil{}:
      True{}
    case SecVal{t} <> r:
      Bool.and(Bool.not(String.contains(s, t)), Sec.clean.go(r, s))

def Sec.clean(v: Vault, +s: String) -> Bool:
  match v:
    case Vault{vs}:
      Sec.clean.go(vs, s)

# The mask
# --------
# Sec.fine covers each character inside an occurrence of a stored value
# with U+2022, keeping the rest and the length (in the hub's bundle its
# body is native, scripts/js-native.py: the same cover by indexOf, checked
# against this definition by test/tools/secret.mjs): "SECRET-FIXTURE-1" in
# a log line reads "••••••••••••••••". Its result is checked: should it ever
# leave a value, the whole text becomes bullets. So Sec.mask's laws hold
# whatever Sec.fine does (sec_mask_total), and clean text is never walked.

def Sec.hit.k(on: Bool, +l: Nat, +n: Nat) -> Nat:
  match on:
    case True{}:
      Bool.pick(Nat, Nat.is_gt(l, n), l, n)
    case False{}:
      n

# the longest stored value s starts with (0 for none)
def Sec.hit(vs: List<&2, SecVal>, +s: String, +n: Nat) -> Nat:
  match vs:
    case Nil{}:
      n
    case SecVal{+t} <> r:
      Sec.hit(r, s, Sec.hit.k(String.starts_with(s, t), String.length(t), n))

def Sec.cell(k: Nat, c: Char) -> Char:
  match k:
    case 0n:
      c
    case 1n+_:
      Chr{8226}

def Sec.pred(k: Nat) -> Nat:
  match k:
    case 0n:
      0n
    case 1n+p:
      p

def Sec.top(+h: Nat, +k: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_gt(h, k), h, k)

# k: how many characters from here an earlier occurrence still covers
# (tail calls: a tool's output can be long)
def Sec.fine.go(s: String, +k: Nat, +vs: List<&2, SecVal>, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{+c, +t}:
      +k2 = Sec.top(Sec.hit(vs, SCon{c, t}, 0n), k)
      Sec.fine.go(t, Sec.pred(k2), vs, SCon{Sec.cell(k2, c), acc})

def Sec.fine(+vs: List<&2, SecVal>, s: String) -> String:
  Sec.fine.go(s, 0n, vs, SNil{})

# n bullets
def Sec.bul(n: Nat) -> String:
  match n:
    case 0n:
      SNil{}
    case 1n+p:
      SCon{Chr{8226}, Sec.bul(p)}

def Sec.mask.f(ok: Bool, +f: String) -> String:
  match ok:
    case True{}:
      f
    case False{}:
      Sec.bul(String.length(f))

# (f: the fine mask's answer, computed once)
def Sec.mask.g(+vs: List<&2, SecVal>, +f: String) -> String:
  Sec.mask.f(Sec.clean.go(vs, f), f)

def Sec.mask.c(clean: Bool, +vs: List<&2, SecVal>, +s: String) -> String:
  match clean:
    case True{}:
      s
    case False{}:
      Sec.mask.g(vs, Sec.fine(vs, s))

def Sec.mask.go(+vs: List<&2, SecVal>, +s: String) -> String:
  Sec.mask.c(Sec.clean.go(vs, s), vs, s)

# text with every stored value covered (laws sec_mask_*)
def Sec.mask(v: Vault, +s: String) -> String:
  match v:
    case Vault{+vs}:
      Sec.mask.go(vs, s)

# JSON
# ----
# every string of a tree masked, keys too (the commit's changes and the
# MCP answers; law sec_json_total)
def Sec.json.go(j: J.Json, +vs: List<&2, SecVal>) -> J.Json:
  match j:
    case J.Str{t}:
      J.Str{Sec.mask.go(vs, t)}
    case J.Arr{i}:
      J.Arr{Sec.json.go(i, vs)}
    case J.Obj{f}:
      J.Obj{Sec.json.go(f, vs)}
    case J.Item{h, t}:
      J.Item{Sec.json.go(h, vs), Sec.json.go(t, vs)}
    case J.Field{k, x, t}:
      J.Field{Sec.mask.go(vs, k), Sec.json.go(x, vs), Sec.json.go(t, vs)}
    case J.Null{}:
      J.Null{}
    case J.Flag{b}:
      J.Flag{b}
    case J.Num{r}:
      J.Num{r}
    case J.End{}:
      J.End{}

def Sec.json.clean.go(j: J.Json, +vs: List<&2, SecVal>) -> Bool:
  match j:
    case J.Str{t}:
      Sec.clean.go(vs, t)
    case J.Arr{i}:
      Sec.json.clean.go(i, vs)
    case J.Obj{f}:
      Sec.json.clean.go(f, vs)
    case J.Item{h, t}:
      Bool.and(Sec.json.clean.go(h, vs), Sec.json.clean.go(t, vs))
    case J.Field{k, x, t}:
      Bool.and(Sec.clean.go(vs, k), Bool.and(Sec.json.clean.go(x, vs), Sec.json.clean.go(t, vs)))
    case _:
      True{}

# no stored value in any string (or key) of j
def Sec.json.clean(v: Vault, j: J.Json) -> Bool:
  match v:
    case Vault{+vs}:
      Sec.json.clean.go(j, vs)

def Sec.json.k(clean: Bool, +vs: List<&2, SecVal>, +j: J.Json) -> J.Json:
  match clean:
    case True{}:
      j
    case False{}:
      Sec.json.go(j, vs)

# j with every string masked; a clean tree (always, with an empty vault)
# comes back as it was, not rebuilt
def Sec.json(v: Vault, +j: J.Json) -> J.Json:
  match v:
    case Vault{+vs}:
      Sec.json.k(Sec.json.clean.go(j, vs), vs, j)

# whether masking changes j (the commit decodes a change again only then)
def Sec.json.dirty(v: Vault, j: J.Json) -> Bool:
  Bool.not(Sec.json.clean(v, j))

# Names, values and handles
# -------------------------

def Sec.name.c(+c: U32) -> Char:
  Chr{Bool.pick(U32, Bool.or(Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57))), Bool.or(U32.is_eq(c, 95), U32.is_eq(c, 46))),
    c, Bool.pick(U32, Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90)), (c + 32 : U32), 45))}

def Sec.name.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{+c}, t}:
      Sec.name.go(t, SCon{Sec.name.c(c), acc})

# a secret's name: lower case letters, digits, '-', '_' and '.', anything
# else made '-', at most 64 ("Tailscale Bub" is "tailscale-bub")
def Sec.name(+raw: String) -> String:
  Sec.name.go(String.take(String.trim(raw), 64n), SNil{})

def Sec.vchar(+c: U32) -> Bool:
  Bool.and(Bool.and(U32.is_ge(c, 33), U32.is_le(c, 126)), Bool.and(Bool.not(U32.is_eq(c, 34)), Bool.not(U32.is_eq(c, 92))))

def Sec.vchars(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(Sec.vchar(c), Sec.vchars(t))

# why a value cannot be stored ("" when it can): 8 to 4096 printable ASCII
# characters with no space, quote or backslash (a key, a token, a
# password), so it reads the same raw and JSON-escaped and Sec.ok holds
def Sec.bad.value(+v: String) -> String:
  Bool.pick(String, Nat.is_lt(String.length(v), 8n), "A secret is at least 8 characters",
    Bool.pick(String, Nat.is_gt(String.length(v), 4096n), "A secret is at most 4096 characters",
      Bool.pick(String, Sec.vchars(v), "", "Only letters, digits and punctuation: no spaces, quotes or backslashes")))

def Sec.bad(+name: String, +value: String) -> String:
  Bool.pick(String, String.is_empty(Sec.name(name)), "Give the secret a name", Sec.bad.value(String.trim(value)))

# what an agent gets for a secret: its name and whether it is set, never
# more (law sec_handle_name)
def Sec.handle(+name: String, set: Bool) -> J.Json:
  J.Json.obj([J.KV{"secret", J.Str{name}}, J.KV{"set", J.Flag{set}}])

# Requests
# --------
# An agent's secret_request is the setting secret.ask.<name>: a JSON
# object {purpose, thread, by, at}; an empty value is none (dismissed or
# set). Settings are Changes, so it is logged: it names the secret, never a
# value.

def Sec.ask.key(+name: String) -> String:
  "secret.ask." ++ name

def Sec.ask.body(+purpose: String, +thread: String, +by: String, +at: Nat) -> String:
  J.Json.show(J.Json.obj([J.KV{"purpose", J.Str{String.take(purpose, 400n)}}, J.KV{"thread", J.Str{thread}}, J.KV{"by", J.Str{by}}, J.KV{"at", J.Json.nat(at)}]))

# A secret's metadata (the vault's plaintext part; no value field)
type SecMeta is Data:
  SecMeta{name: String, purpose: String, by: String, at: String, used_at: String, used_by: String}

def Sec.meta.of(+o: J.Json) -> SecMeta:
  SecMeta{J.Json.get_str(o, "name", ""), J.Json.get_str(o, "purpose", ""), J.Json.get_str(o, "by", ""), J.Json.get_str(o, "at", ""), J.Json.get_str(o, "usedAt", ""), J.Json.get_str(o, "usedBy", "")}

def Sec.metas.go(xs: List<&2, J.Json>, acc: List<&2, SecMeta>) -> List<&2, SecMeta>:
  match xs:
    case Nil{}:
      List.reverse(&2, SecMeta, acc)
    case +x <> t:
      Sec.metas.go(t, Sec.meta.of(x) <> acc)

# the effect's list (a JSON array of {name, purpose, by, at, usedAt, usedBy})
def Sec.metas(+text: String) -> List<&2, SecMeta>:
  Sec.metas.go(J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse(text), J.Json.arr([]))), Nil{})

def Sec.meta.name(m: SecMeta) -> String:
  match m:
    case SecMeta{n, _, _, _, _, _}:
      n

def Sec.meta.json(m: SecMeta) -> J.Json:
  match m:
    case SecMeta{+n, p, _, _, u, _}:
      J.Json.obj([J.KV{"secret", J.Str{n}}, J.KV{"set", J.Flag{True{}}}, J.KV{"purpose", J.Str{p}}, J.KV{"usedAt", J.Str{u}}])

def Sec.list.go(ms: List<&2, SecMeta>, acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match ms:
    case Nil{}:
      List.reverse(&2, J.Json, acc)
    case m <> t:
      Sec.list.go(t, Sec.meta.json(m) <> acc)

# secret_list's answer: handles with purpose and last use
def Sec.list(ms: List<&2, SecMeta>) -> String:
  J.Json.show(J.Json.arr(Sec.list.go(ms, Nil{})))

def Sec.has(ms: List<&2, SecMeta>, +name: String) -> Bool:
  match ms:
    case Nil{}:
      False{}
    case m <> t:
      Bool.or(String.eq(Sec.meta.name(m), name), Sec.has(t, name))

# What agents are told
# --------------------

def Sec.names.go(ms: List<&2, SecMeta>, +acc: String) -> String:
  match ms:
    case Nil{}:
      acc
    case m <> t:
      Sec.names.go(t, Bool.pick(String, String.is_empty(acc), "", acc ++ ", ") ++ "`" ++ Sec.meta.name(m) ++ "`")

# the <secrets> block every agent gets: the names set, how to use one,
# and to ask with secret_request instead of in chat (names only)
def Sec.prompt(+ms: List<&2, SecMeta>) -> String:
  "<secrets>Backplane keeps secrets (API keys, auth keys, tokens, passwords) in a vault you never see into. "
  ++ Bool.pick(String, List.is_empty(&2, SecMeta, ms), "None is set yet. ", "Set now: " ++ Sec.names.go(ms, "") ++ ". ")
  ++ "Use one only through the secret_run tool: `env {VAR: name}` puts it in that command's environment, `files {VAR: name}` writes it to a private temporary file whose path is in VAR (e.g. `tailscale up --auth-key=file:$TS`, `gh auth login --with-token < $GH`); its output comes back with any secret masked. "
  ++ "Never ask the person to paste a key, token or password in chat, and never put one in a message, a file or a command line: call secret_request {name, purpose} and end your turn; a message tells you when it is set.</secrets>"
