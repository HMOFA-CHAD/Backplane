import Base

# Where the hub's own binary is. Linux reports /proc/self/exe as
# "<path> (deleted)" once an install or update has replaced the file by
# rename while the hub keeps running.

# the binary was replaced under the running hub
def Exe.gone(+raw: String) -> Bool:
  String.ends_with(raw, " (deleted)")

def Exe.path.k(gone: Bool, +raw: String) -> String:
  match gone:
    case True{}:
      String.take(raw, Nat.sub(String.length(raw), 10n))
    case False{}:
      raw

# the installed binary's path: raw without a trailing " (deleted)"
def Exe.path(+raw: String) -> String:
  Exe.path.k(Exe.gone(raw), raw)

def Exe.child.k(gone: Bool, raw: String) -> String:
  match gone:
    case True{}:
      "/proc/self/exe"
    case False{}:
      raw

# the program a child of this same build runs: a replaced binary is still run
# through /proc/self/exe, so the hub and its child stay one version
def Exe.child(+raw: String) -> String:
  Exe.child.k(Exe.gone(raw), raw)
