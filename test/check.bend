import Base

# "ok name" when got equals want, else "FAIL name: got .. want .."
def Check.pick(same: Bool, name: String, got: String, want: String) -> String:
  match same:
    case True{}:
      "ok " ++ name
    case False{}:
      "FAIL " ++ name ++ ": got " ++ got ++ " want " ++ want

# a equals b, walked with the verdict carried so every step is a tail call
# (Base's String.eq keeps a stack frame per character and faults on the
# tens-of-kilobytes JSON payloads some tests compare)
def Check.same.go(a: String, b: String, ok: Bool) -> Bool:
  match a b:
    case SNil{} SNil{}:
      ok
    case SCon{Chr{x}, xt} SCon{Chr{y}, yt}:
      Check.same.go(xt, yt, Bool.and(ok, U32.is_eq(x, y)))
    case _ _:
      False{}

def Check.same(a: String, b: String) -> Bool:
  Check.same.go(a, b, True{})

def Check.str(name: String, +got: String, +want: String) -> IO(Unit):
  IO.print(Check.pick(Check.same(got, want), name, got, want))
