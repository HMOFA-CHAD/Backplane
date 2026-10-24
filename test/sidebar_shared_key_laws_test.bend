import Base
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/server/thin-actor.bend as CHATSIDE
import ../src/server/thin-sidebar.bend as CHATDERIVED

# False is not True
def Bool.disc(b: Bool) -> Type:
  match b:
    case False{}:
      Unit
    case True{}:
      Empty

law false_ne_true:
  for e: {False{} == True{} : Bool}
  Empty

def false_ne_true(e):
  %e : Bool.disc(_)
  Unit{}

law nat_eq_sound:
  for a: Nat
  for b: Nat
  for h: {Nat.is_eq(a, b) == True{} : Bool}
  {a == b : Nat}

def nat_eq_sound(a, b, h):
  match a b:
    case 0n 0n:
      {==}
    case 0n 1n+q:
      Empty.absurd({0n == 1n+q : Nat}, false_ne_true(h))
    case 1n+p 0n:
      Empty.absurd({1n+p == 0n : Nat}, false_ne_true(h))
    case 1n+p 1n+q:
      e = nat_eq_sound(p, q, h)
      %e : {1n+p == 1n+_ : Nat}
      {==}


# Sharing a duplicate key never changes its exact value or fallback.
law sidebar_shared_key_equal:
  for +u: U.Ui
  for +epoch: String
  for +view: String
  for +revision: Nat
  for +h: {Nat.is_eq(M.State.seq(U.Ui.state(u)), revision) == True{} : Bool}
  {CHATSIDE.SidebarImage.key.shared(False{}, u, epoch, view, revision, CHATDERIVED.Sidebar.key(u, epoch, view)) == CHATSIDE.SidebarImage.key(False{}, u, epoch, view, revision) : String}

law sidebar_shared_key_different:
  for +u: U.Ui
  for +epoch: String
  for +view: String
  for +revision: Nat
  for picture: String
  for h: {Nat.is_eq(M.State.seq(U.Ui.state(u)), revision) == False{} : Bool}
  {CHATSIDE.SidebarImage.key.shared(False{}, u, epoch, view, revision, picture) == CHATSIDE.SidebarImage.key(False{}, u, epoch, view, revision) : String}

law sidebar_shared_key_settings:
  for u: U.Ui
  for epoch: String
  for view: String
  for revision: Nat
  for picture: String
  {CHATSIDE.SidebarImage.key.shared(True{}, u, epoch, view, revision, picture) == "" : String}

def sidebar_shared_key_equal(u, epoch, view, revision, h):
  %Equal.sym(Bool, Nat.is_eq(M.State.seq(U.Ui.state(u)), revision), True{}, h) : {CHATSIDE.SidebarImage.key.same(_, CHATDERIVED.Sidebar.key(u, epoch, view), u, epoch, view, revision) == CHATSIDE.SidebarImage.key(False{}, u, epoch, view, revision) : String}
  %nat_eq_sound(M.State.seq(U.Ui.state(u)), revision, h)
    : {CHATDERIVED.Sidebar.key(u, epoch, view) == CHATDERIVED.Sidebar.key.revision(u, epoch, view, _) : String}
  {==}

def sidebar_shared_key_different(u, epoch, view, revision, picture, h):
  %Equal.sym(Bool, Nat.is_eq(M.State.seq(U.Ui.state(u)), revision), False{}, h) : {CHATSIDE.SidebarImage.key.same(_, picture, u, epoch, view, revision) == CHATSIDE.SidebarImage.key(False{}, u, epoch, view, revision) : String}
  {==}

def sidebar_shared_key_settings(u, epoch, view, revision, picture):
  {==}

def main() -> IO(Unit):
  IO.print("ok three exact shared-key branch laws")
