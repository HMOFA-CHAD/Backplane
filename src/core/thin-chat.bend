import Base
import ./model.bend as M
import ./bot.bend as B
import ./ubersync.bend as US
import ./thin.bend as T
import ./mail.bend as ML

# Chat-only materialization, never a change to source history or search.
# Keep exactly the Page.delivery.receipt predicate without importing client
# into the thin index (which would introduce a dependency cycle).
def Chat.receipt(e: M.Entry) -> Bool:
  match e:
    case M.Act{+id, _, +tone, +kind, _, _}:
      Bool.and(String.starts_with(id, "ride:"), Bool.and(String.eq(tone, "info"), String.eq(kind, "ride")))
    case M.Msg{_, _, _, _, _}: False{}

def Chat.enabled(+st: M.State, +th: String) -> Bool:
  Bool.or(B.World.is_bot_thread(M.State.bots(st), th), US.Ub.chat.is(st, th))

# An explicit AVL spine, like ML.Order.page: seek to the exclusive source
# ordinal, then stop after n+1 retained rows. No full list or replay.
type ChatScan is Data:
  ChatScan{todo: List<&2, ML.Order>, skip: Nat, left: Nat, acc: List<&2, T.Row>}

def Chat.keep(hide: Bool, todo: List<&2, ML.Order>, +left: Nat, r: T.Row, acc: List<&2, T.Row>) -> ChatScan:
  match hide:
    case True{}: ChatScan{todo, 0n, left, acc}
    case False{}: ChatScan{todo, 0n, Nat.sub(left, 1n), r <> acc}

def Chat.step(c: Cmp, a: Nat, +id: String, +l: ML.Order, +r: ML.Order, +rest: List<&2, ML.Order>, +skip: Nat, +left: Nat, +acc: List<&2, T.Row>, +i: T.Index) -> ChatScan:
  match c:
    case LT{}: ChatScan{l <> ML.Order.node(a, id, ML.OEmpty{}, r) <> rest, skip, left, acc}
    case EQ{}:
      +row = T.Index.row.k(Map.get(T.Row, T.Row.blank(), T.Index.rows(i), id))
      Chat.keep(Chat.receipt(T.Row.entry(row)), r <> rest, left, row, acc)
    case GT{}: ChatScan{r <> rest, Nat.sub(skip, 1n+ML.Order.count(l)), left, acc}

def Chat.walk(fuel: Nat, cur: ChatScan, +i: T.Index) -> List<&2, T.Row>:
  match fuel cur:
    case 0n ChatScan{_, _, _, acc}: List.reverse(&2, T.Row, acc)
    case 1n+f ChatScan{_, _, 0n, acc}: List.reverse(&2, T.Row, acc)
    case 1n+f ChatScan{Nil{}, _, _, acc}: List.reverse(&2, T.Row, acc)
    case 1n+f ChatScan{ML.OEmpty{} <> rest, skip, left, acc}:
      Chat.walk(f, ChatScan{rest, skip, left, acc}, i)
    case 1n+f ChatScan{ML.ONode{_, _, a, +id, +l, r} <> rest, +skip, left, acc}:
      Chat.walk(f, Chat.step(Nat.cmp(skip, ML.Order.count(l)), a, id, l, r, rest, skip, left, acc, i), i)

def Chat.limit(+n: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_le(n, 32n), n, 32n)

# The lookahead stays in this request's index; only n rows are emitted.
# remaining is a bounded lower bound; hasMore and the source cursor are exact.
def Chat.window(+i: T.Index, +th: String, +before: Nat, +n: Nat) -> T.Index:
  +o = T.Index.thread(i, th)
  T.Index.window(Chat.walk(1n+Nat.mul(3n, ML.Order.count(o)), ChatScan{[o], T.Page.after(o, before), 1n+Chat.limit(n), Nil{}}, i), th, 0n, i)

def Chat.index(enabled: Bool, +i: T.Index, th: String, before: Nat, n: Nat) -> T.Index:
  match enabled:
    case True{}: Chat.window(i, th, before, n)
    case False{}: i
