import Base
import ../core/json.bend as J
import ../core/secret.bend as S

# The secrets vault's IO (effects/vault.js; core/secret.bend is the pure
# side). The effect holds the values; Bend asks for them only to mask
# (Vx.vault), and hands names, never values, to VaultFx.run.

# read <home>/secrets/vault.json and its key once: {key, locked, why, n}
def VaultFx.open(home: String) -> IO(String):
  import "./effects/vault.js"

def VaultFx.status() -> IO(String):
  import "./effects/vault.js"

# the values to mask, one a line (read by Vx.vault alone)
def VaultFx.values() -> IO(String):
  import "./effects/vault.js"

# the metadata, a JSON array of {name, purpose, by, at, usedAt, usedBy}
def VaultFx.list() -> IO(String):
  import "./effects/vault.js"

# keep a value: "ok" or "fail <why>"
def VaultFx.put(name: String, value: String, purpose: String, by: String) -> IO(String):
  import "./effects/vault.js"

def VaultFx.del(name: String) -> IO(String):
  import "./effects/vault.js"

# run a command with secrets injected by name ({command, env, files, cwd,
# timeout, thread}); its answer is raw: mask it (Vx.run)
def VaultFx.run(spec: String) -> IO(String):
  import "./effects/vault.js"

# lines of a text, in one tail-recursive walk (Base's split recurses per
# character)
type VxCut is Data:
  VxCut{cur: String, acc: List<&2, String>}

def Vx.step.k(nl: Bool, +c: U32, st: VxCut) -> VxCut:
  match nl st:
    case True{} VxCut{cur, acc}:
      VxCut{SNil{}, String.reverse(cur) <> acc}
    case False{} VxCut{cur, acc}:
      VxCut{SCon{Chr{c}, cur}, acc}

def Vx.lines.go(s: String, st: VxCut) -> List<&2, String>:
  match s st:
    case SNil{} VxCut{cur, acc}:
      List.reverse(&2, String, String.reverse(cur) <> acc)
    case SCon{Chr{+c}, t} _:
      Vx.lines.go(t, Vx.step.k(U32.is_eq(c, 10), c, st))

def Vx.lines(s: String) -> List<&2, String>:
  Vx.lines.go(s, VxCut{SNil{}, Nil{}})

def Vx.of.k(empty: Bool, +t: String) -> S.Vault:
  match empty:
    case True{}:
      S.Vault{[]}
    case False{}:
      S.Sec.vault(Vx.lines(t))

def Vx.of(+t: String) -> S.Vault:
  Vx.of.k(String.is_empty(t), t)

# the vault to mask with (empty when nothing is stored: every mask is then
# the identity, law sec_empty_id)
def Vx.vault() -> IO(S.Vault):
  IO.bind(String, S.Vault, VaultFx.values(), t => IO.pure(S.Vault, Vx.of(t)))

# text masked with the vault as it is now
def Vx.mask(+s: String) -> IO(String):
  IO.bind(S.Vault, String, Vx.vault(), v => IO.pure(String, S.Sec.mask(v, s)))

def Vx.metas() -> IO(List<&2, S.SecMeta>):
  IO.bind(String, List<&2, S.SecMeta>, VaultFx.list(), t => IO.pure(List<&2, S.SecMeta>, S.Sec.metas(t)))

# the <secrets> block for an agent's prompt (names only)
def Vx.prompt() -> IO(String):
  IO.bind(List<&2, S.SecMeta>, String, Vx.metas(), ms => IO.pure(String, S.Sec.prompt(ms)))

# secret_run: the run, its answer masked
def Vx.run(+spec: String) -> IO(String):
  IO.bind(String, String, VaultFx.run(spec), r => Vx.mask(r))

# each launch argument of an agent masked (every provider's spawn: Claude,
# Codex, the ACP/MSP/RPC runners, the writer's one-shot); the prompt, the
# turn's text and any instructions ride in them
def Vx.args.go(xs: List<&2, String>, +v: S.Vault, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +x <> t:
      Vx.args.go(t, v, S.Sec.mask(v, x) <> acc)

def Vx.args(xs: List<&2, String>) -> IO(List<&2, String>):
  IO.bind(S.Vault, List<&2, String>, Vx.vault(), v => IO.pure(List<&2, String>, Vx.args.go(xs, v, Nil{})))
