import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/subthreads.bend as ST

# Frozen pre-change operations: compare values, including invalid ancestry,
# rather than assuming a cache hit or counting implementation details.
def Old.raw(+s: M.State, +id: String) -> String:
  +p = M.Setting.get(s, ST.Tree.key(id), "")
  ST.Tree.raw.k(Bool.and(Bool.not(String.is_empty(p)), Bool.and(Bool.not(String.eq(id, p)),
    Bool.and(ST.Tree.alive(M.State.thread.get(s, id)), Bool.and(ST.Tree.alive(M.State.thread.get(s, p)),
      String.eq(ST.Tree.project(M.State.thread.get(s, id)), ST.Tree.project(M.State.thread.get(s, p))))))), p)

def Old.chain(fuel: Nat, +s: M.State, id: String, +origin: String) -> Bool:
  match fuel id:
    case _ SNil{}: True{}
    case 0n SCon{c, t}: False{}
    case 1n+n SCon{+c, +t}:
      Bool.and(Bool.not(String.eq(SCon{c, t}, origin)), Old.chain(n, s, Old.raw(s, SCon{c, t}), origin))

def Old.parent(+s: M.State, +id: String) -> String:
  ST.Tree.raw.k(Old.chain(64n, s, Old.raw(s, id), id), Old.raw(s, id))

def Old.display(+s: M.State, +id: String) -> String:
  +p = Old.parent(s, id)
  ST.Tree.raw.k(ST.Tree.same(ST.Tree.archived(M.State.thread.get(s, id)), ST.Tree.archived(M.State.thread.get(s, p))), p)

def base() -> M.State:
  M.State.replay([M.ProjectCreated{"p", "Project", "/tmp/p", 1n}, M.ProjectCreated{"q", "Other", "/tmp/q", 1n},
    M.ThreadCreated{"parent", "p", "Parent", M.Local{}, "", "", "codex", "", 2n},
    M.ThreadCreated{"child", "p", "Child", M.Local{}, "", "", "codex", "", 3n},
    M.ThreadCreated{"leaf", "p", "Leaf", M.Local{}, "", "", "codex", "", 4n},
    M.ThreadCreated{"other", "q", "Other", M.Local{}, "", "", "codex", "", 5n},
    M.ThreadCreated{"hub~parent", "hub~p", "Mirror parent", M.Local{}, "", "", "codex", "", 2n},
    M.ThreadCreated{"hub~child", "hub~p", "Mirror child", M.Local{}, "", "", "codex", "", 3n}], M.State.empty())

def linked() -> M.State:
  M.State.replay([M.ThreadParentSet{"child", "parent", 6n}, M.ThreadParentSet{"leaf", "child", 7n}], base())

def ids() -> List<&2, String>:
  ["parent", "child", "leaf", "other", "hub~parent", "hub~child", "missing", ""]

def agree(xs: List<&2, String>, +s: M.State) -> Bool:
  match xs:
    case Nil{}: True{}
    case +id <> rest:
      Bool.and(String.eq(ST.Tree.raw(s, id), Old.raw(s, id)), Bool.and(String.eq(ST.Tree.parent(s, id), Old.parent(s, id)),
        Bool.and(String.eq(ST.Tree.display_parent(s, id), Old.display(s, id)), agree(rest, s))))

def check(name: String, s: M.State) -> IO(Unit):
  C.Check.str(name, Bool.show(agree(ids(), s)), "True")

def chain(+n: Nat, s: M.State) -> M.State:
  match n:
    case 0n: s
    case 1n+k:
      chain(k, M.State.replay([M.ThreadCreated{"n" ++ Nat.show(n), "p", "Chain", M.Local{}, "", "", "codex", "", 2n},
        M.ThreadParentSet{"n" ++ Nat.show(n), "n" ++ Nat.show(k), 3n}], s))

def chain_same(+s: M.State, +id: String) -> Bool:
  Bool.and(String.eq(ST.Tree.parent(s, id), Old.parent(s, id)), String.eq(ST.Tree.display_parent(s, id), Old.display(s, id)))

def main() -> IO(Unit):
  do IO<Unit>:
    check("flat roots and missing IDs match legacy", base())
    check("nested ancestry matches legacy", linked())
    check("missing parent matches legacy", M.State.apply(linked(), M.ThreadParentSet{"child", "missing", 8n}))
    check("cross-project parent matches legacy", M.State.apply(linked(), M.ThreadParentSet{"child", "other", 8n}))
    check("self cycle matches legacy", M.State.apply(linked(), M.ThreadParentSet{"child", "child", 8n}))
    check("ancestor cycle matches legacy", M.State.apply(linked(), M.ThreadParentSet{"parent", "leaf", 8n}))
    check("cycle unrelated to leaf matches legacy", M.State.replay([M.ThreadParentSet{"parent", "child", 8n}, M.ThreadParentSet{"child", "parent", 9n}], linked()))
    check("deleted parent matches legacy", M.State.apply(linked(), M.ThreadDeleted{"parent", 8n}))
    check("deleted child matches legacy", M.State.apply(linked(), M.ThreadDeleted{"child", 8n}))
    check("archived parent promotes live child exactly", M.State.apply(linked(), M.ThreadArchived{"parent", True{}, 8n}))
    check("archived child matches legacy", M.State.apply(linked(), M.ThreadArchived{"child", True{}, 8n}))
    check("same archived shelf matches legacy", M.State.replay([M.ThreadArchived{"parent", True{}, 8n}, M.ThreadArchived{"child", True{}, 9n}], linked()))
    check("cleared relationship matches legacy", M.State.apply(linked(), M.ThreadParentSet{"child", "", 8n}))
    check("namespaced mirrors match legacy", M.State.apply(linked(), M.ThreadParentSet{"hub~child", "hub~parent", 8n}))
    C.Check.str("64-level boundary matches legacy", Bool.show(chain_same(chain(64n, base()), "n64")), "True")
    C.Check.str("over-depth corrupt ancestry matches legacy", Bool.show(chain_same(chain(67n, base()), "n67")), "True")
