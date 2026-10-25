import Base
import ../src/core/json.bend as J
import ../src/core/secret.bend as S

# Proofs for the secret box (src/core/secret.bend; LAWS.bend's block
# "secret box" states the headline laws and PROOF.bend fills them from
# here). No stored value survives a mask, a mask is idempotent and leaves
# clean text alone, and every string of a masked JSON tree is clean.

# False is not True
def Secp.disc(b: Bool) -> Type:
  match b:
    case False{}:
      Unit
    case True{}:
      Empty

law secp_false_ne_true:
  for e: {False{} == True{} : Bool}
  Empty

def secp_false_ne_true(e):
  %e : Secp.disc(_)
  Unit{}

law secp_not_true:
  for b: Bool
  for +h: {Bool.not(b) == True{} : Bool}
  {b == False{} : Bool}

def secp_not_true(b, h):
  match b:
    case False{}:
      {==}
    case True{}:
      Empty.absurd({True{} == False{} : Bool}, secp_false_ne_true(h))

law secp_and_l:
  for a: Bool
  for b: Bool
  for +h: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool}

def secp_and_l(a, b, h):
  match a:
    case True{}:
      {==}
    case False{}:
      Empty.absurd({False{} == True{} : Bool}, secp_false_ne_true(h))

law secp_and_r:
  for a: Bool
  for b: Bool
  for +h: {Bool.and(a, b) == True{} : Bool}
  {b == True{} : Bool}

def secp_and_r(a, b, h):
  match a:
    case True{}:
      h
    case False{}:
      Empty.absurd({b == True{} : Bool}, secp_false_ne_true(h))

# bullets never spell a storable value
law secp_ok_bul:
  for n: Nat
  for +t: String
  for +h: {S.Sec.ok(t) == True{} : Bool}
  {String.contains(S.Sec.bul(n), t) == False{} : Bool}

def secp_ok_bul(n, t, h):
  match n t:
    case _ SNil{}:
      Empty.absurd({String.contains(S.Sec.bul(n), SNil{}) == False{} : Bool}, secp_false_ne_true(h))
    case 0n SCon{y, yt}:
      {==}
    case 1n+p SCon{+y, +yt}:
      %Equal.sym(Bool, Char.is_eq(Chr{8226}, y), False{}, secp_not_true(Char.is_eq(Chr{8226}, y), h)) : {String.contains.if(S.Sec.bul(p), SCon{y, yt}, String.starts_with.if(S.Sec.bul(p), yt, _)) == False{} : Bool}
      secp_ok_bul(p, SCon{y, yt}, h)

law secp_bul_clean:
  for vs: List<&2, S.SecVal>
  for +n: Nat
  for +h: {S.Sec.valid.go(vs) == True{} : Bool}
  {S.Sec.clean.go(vs, S.Sec.bul(n)) == True{} : Bool}

def secp_bul_clean(vs, n, h):
  match vs:
    case Nil{}:
      {==}
    case S.SecVal{+t} <> +r:
      %Equal.sym(Bool, String.contains(S.Sec.bul(n), t), False{}, secp_ok_bul(n, t, secp_and_l(S.Sec.ok(t), S.Sec.valid.go(r), h))) : {Bool.and(Bool.not(_), S.Sec.clean.go(r, S.Sec.bul(n))) == True{} : Bool}
      secp_bul_clean(r, n, secp_and_r(S.Sec.ok(t), S.Sec.valid.go(r), h))

law secp_mask_f:
  for b: Bool
  for +vs: List<&2, S.SecVal>
  for +f: String
  for e: {S.Sec.clean.go(vs, f) == b : Bool}
  for +h: {S.Sec.valid.go(vs) == True{} : Bool}
  {S.Sec.clean.go(vs, S.Sec.mask.f(b, f)) == True{} : Bool}

def secp_mask_f(b, vs, f, e, h):
  match b:
    case True{}:
      e
    case False{}:
      secp_bul_clean(vs, String.length(f), h)

law secp_mask_g:
  for +vs: List<&2, S.SecVal>
  for +f: String
  for +h: {S.Sec.valid.go(vs) == True{} : Bool}
  {S.Sec.clean.go(vs, S.Sec.mask.g(vs, f)) == True{} : Bool}

def secp_mask_g(vs, f, h):
  secp_mask_f(S.Sec.clean.go(vs, f), vs, f, {==}, h)

law secp_mask_c:
  for b: Bool
  for +vs: List<&2, S.SecVal>
  for +s: String
  for e: {S.Sec.clean.go(vs, s) == b : Bool}
  for +h: {S.Sec.valid.go(vs) == True{} : Bool}
  {S.Sec.clean.go(vs, S.Sec.mask.c(b, vs, s)) == True{} : Bool}

def secp_mask_c(b, vs, s, e, h):
  match b:
    case True{}:
      e
    case False{}:
      secp_mask_g(vs, S.Sec.fine(vs, s), h)

# no stored value occurs in masked text
law secp_mask_go_total:
  for +vs: List<&2, S.SecVal>
  for +s: String
  for +h: {S.Sec.valid.go(vs) == True{} : Bool}
  {S.Sec.clean.go(vs, S.Sec.mask.go(vs, s)) == True{} : Bool}

def secp_mask_go_total(vs, s, h):
  secp_mask_c(S.Sec.clean.go(vs, s), vs, s, {==}, h)

law secp_mask_total:
  for +v: S.Vault
  for +s: String
  for +h: {S.Sec.valid(v) == True{} : Bool}
  {S.Sec.clean(v, S.Sec.mask(v, s)) == True{} : Bool}

def secp_mask_total(v, s, h):
  match v:
    case S.Vault{vs}:
      secp_mask_go_total(vs, s, h)

# the vault the hub builds is always valid
law secp_keep_k:
  for b: Bool
  for +t: String
  for +rl: List<&2, S.SecVal>
  for e: {S.Sec.ok(t) == b : Bool}
  for ih: {S.Sec.valid.go(rl) == True{} : Bool}
  {S.Sec.valid.go(S.Sec.keep.k(b, t, rl)) == True{} : Bool}

def secp_keep_k(b, t, rl, e, ih):
  match b:
    case True{}:
      %Equal.sym(Bool, S.Sec.ok(t), True{}, e) : {Bool.and(_, S.Sec.valid.go(rl)) == True{} : Bool}
      ih
    case False{}:
      ih

law secp_vault_valid:
  for ts: List<&2, String>
  {S.Sec.valid(S.Sec.vault(ts)) == True{} : Bool}

def secp_vault_valid(ts):
  match ts:
    case Nil{}:
      {==}
    case +t <> +r:
      secp_keep_k(S.Sec.ok(t), t, S.Sec.keep(r), {==}, secp_vault_valid(r))

law secp_vault_total:
  for +ts: List<&2, String>
  for +s: String
  {S.Sec.clean(S.Sec.vault(ts), S.Sec.mask(S.Sec.vault(ts), s)) == True{} : Bool}

def secp_vault_total(ts, s):
  secp_mask_total(S.Sec.vault(ts), s, secp_vault_valid(ts))

# clean text is left as it is
law secp_mask_clean_id:
  for +v: S.Vault
  for +s: String
  for +h: {S.Sec.clean(v, s) == True{} : Bool}
  {S.Sec.mask(v, s) == s : String}

def secp_mask_clean_id(v, s, h):
  match v:
    case S.Vault{+vs}:
      %Equal.sym(Bool, S.Sec.clean.go(vs, s), True{}, h) : {S.Sec.mask.c(_, vs, s) == s : String}
      {==}

law secp_mask_idem:
  for +v: S.Vault
  for +s: String
  for +h: {S.Sec.valid(v) == True{} : Bool}
  {S.Sec.mask(v, S.Sec.mask(v, s)) == S.Sec.mask(v, s) : String}

def secp_mask_idem(v, s, h):
  secp_mask_clean_id(v, S.Sec.mask(v, s), secp_mask_total(v, s, h))

law secp_empty_id:
  for +s: String
  {S.Sec.mask(S.Vault{[]}, s) == s : String}

def secp_empty_id(s):
  {==}

# every string of a masked JSON tree is clean
law secp_json_go_total:
  for j: J.Json
  for +vs: List<&2, S.SecVal>
  for +h: {S.Sec.valid.go(vs) == True{} : Bool}
  {S.Sec.json.clean.go(S.Sec.json.go(j, vs), vs) == True{} : Bool}

def secp_json_go_total(j, vs, h):
  match j:
    case J.Str{+t}:
      secp_mask_go_total(vs, t, h)
    case J.Arr{i}:
      secp_json_go_total(i, vs, h)
    case J.Obj{f}:
      secp_json_go_total(f, vs, h)
    case J.Item{a, t}:
      %Equal.sym(Bool, S.Sec.json.clean.go(S.Sec.json.go(a, vs), vs), True{}, secp_json_go_total(a, vs, h)) : {Bool.and(_, S.Sec.json.clean.go(S.Sec.json.go(t, vs), vs)) == True{} : Bool}
      secp_json_go_total(t, vs, h)
    case J.Field{+k, x, t}:
      %Equal.sym(Bool, S.Sec.clean.go(vs, S.Sec.mask.go(vs, k)), True{}, secp_mask_go_total(vs, k, h)) : {Bool.and(_, Bool.and(S.Sec.json.clean.go(S.Sec.json.go(x, vs), vs), S.Sec.json.clean.go(S.Sec.json.go(t, vs), vs))) == True{} : Bool}
      %Equal.sym(Bool, S.Sec.json.clean.go(S.Sec.json.go(x, vs), vs), True{}, secp_json_go_total(x, vs, h)) : {Bool.and(True{}, Bool.and(_, S.Sec.json.clean.go(S.Sec.json.go(t, vs), vs))) == True{} : Bool}
      secp_json_go_total(t, vs, h)
    case J.Null{}:
      {==}
    case J.Flag{b}:
      {==}
    case J.Num{r}:
      {==}
    case J.End{}:
      {==}

law secp_json_k:
  for b: Bool
  for +vs: List<&2, S.SecVal>
  for +j: J.Json
  for e: {S.Sec.json.clean.go(j, vs) == b : Bool}
  for +h: {S.Sec.valid.go(vs) == True{} : Bool}
  {S.Sec.json.clean.go(S.Sec.json.k(b, vs, j), vs) == True{} : Bool}

def secp_json_k(b, vs, j, e, h):
  match b:
    case True{}:
      e
    case False{}:
      secp_json_go_total(j, vs, h)

law secp_json_total:
  for +v: S.Vault
  for +j: J.Json
  for +h: {S.Sec.valid(v) == True{} : Bool}
  {S.Sec.json.clean(v, S.Sec.json(v, j)) == True{} : Bool}

def secp_json_total(v, j, h):
  match v:
    case S.Vault{+vs}:
      secp_json_k(S.Sec.json.clean.go(j, vs), vs, j, {==}, h)

# a handle is the name and the set flag, nothing else
law secp_handle_shape:
  for +n: String
  for b: Bool
  {S.Sec.handle(n, b) == J.Obj{J.Field{"secret", J.Str{n}, J.Field{"set", J.Flag{b}, J.End{}}}} : J.Json}

def secp_handle_shape(n, b):
  {==}
