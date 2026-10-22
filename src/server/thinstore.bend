import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/thin.bend as T
import ../core/thinq.bend as Q
import ../core/presentation.bend as P
import ./db.bend as D

# Thin views from the store (IO): the queries core/thinq.bend writes, run on
# a store.db handle (D.Db), each answer a page index the pure renderers read
# as they read the whole index. Nothing here keeps rows between requests.
# (S1's server/storedb.bend Sto.page/Sto.search/Sto.entry will take these
# over with the same shapes.)

type Page is Data:
  Page{index: T.Index, ids: List<&2, String>}

def Page.index(p: Page) -> T.Index:
  match p:
    case Page{i, _}: i

def Page.ids(p: Page) -> List<&2, String>:
  match p:
    case Page{_, ids}: ids

def Ts.nat(xs: List<&2, List<&2, String>>) -> Nat:
  Q.num(Q.first(xs))

def Ts.seq_at(h: String, +before: Nat) -> IO(Nat):
  do IO<Nat>:
    r : List<&2, List<&2, String>> <- D.Db.query(h, Q.sql.seq_at(), [Q.n(Q.before(before))], 1)
    return Ts.nat(r)

# the thread's rows older than the page's oldest, when the page is full
# (one more than the page: a row older than it exists)
def Ts.below(full: Bool, h: String, +th: String, +seq: Nat) -> IO(Nat):
  match full:
    case False{}: IO.pure(Nat, 0n)
    case True{}:
      do IO<Nat>:
        r : List<&2, List<&2, String>> <- D.Db.query(h, Q.sql.below(), [th, Q.n(seq)], 1)
        return Ts.nat(r)

# a thread's page older than ordinal `before` (0: the newest), at most
# `limit` (capped at 32) and one more, as T.Index.page would give it, and
# what Page.window asks of the rest
def Ts.page(h: String, +th: String, +before: Nat, +limit: Nat, +base: T.Index) -> IO(Page):
  +lim = Nat.add(Bool.pick(Nat, Nat.is_le(limit, 32n), limit, 32n), 1n)
  do IO<Page>:
    +s : Nat <- Ts.seq_at(h, before)
    +xs : List<&2, List<&2, String>> <- D.Db.query(h, Q.sql.page(), [th, Q.n(s), Q.n(lim)], U32.from_nat(lim))
    +n : Nat <- Ts.below(Nat.is_eq(List.length(&2, List<&2, String>, xs), lim), h, th, Q.last_seq(xs, 0n))
    +i : T.Index = T.Index.window(Q.rows(xs), th, n, base)
    return Page{i, T.Index.page(i, th, before, limit)}

# A message read whole: the rows the read may name (the cursor's ordinal,
# or the entry `id` among the page's rows), whole, in the page's index
def Ts.whole(h: String, +th: String, +ord: Nat, +id: String, +p: Page) -> IO(Page):
  match p:
    case Page{+i, +ids}:
      do IO<Page>:
        +xs : List<&2, List<&2, String>> <- D.Db.query(h, Q.sql.whole(), [Q.n(ord), id, J.Json.show(J.Json.arr(Q.json.nats(ids)))], 64)
        return Page{T.Index.window(Q.rows(xs), th, 0n, i), ids}

# the ordinal a message read's cursor names ("message:<n>"; 0: none)
def Ts.cursor.ord.q(ok: Bool, +q: String) -> Nat:
  match ok:
    case False{}: 0n
    case True{}: Maybe.default(&2, Nat, P.Session.nat(String.drop(q, 8n), P.Session.nat.max()), 0n)

def Ts.cursor.ord(+p: J.Json) -> Nat:
  +q = J.Json.get_str(Maybe.default(&2, J.Json, J.Json.parse(J.Json.get_str(p, "cursor", "")), J.Null{}), "query", "")
  Ts.cursor.ord.q(String.starts_with(q, "message:"), q)

def Ts.counts(ts: List<&2, Sigma<&2, &2, String, _ => Bool>>, h: String) -> IO(List<&2, Nat>):
  match ts:
    case Nil{}: IO.pure(List<&2, Nat>, Nil{})
    case (+w, _) <> t:
      do IO<List<&2, Nat>>:
        r : List<&2, List<&2, String>> <- D.Db.query(h, Q.sql.count(), [w], 1)
        rest : List<&2, Nat> <- Ts.counts(t, h)
        return Ts.nat(r) <> rest

type Found is Data:
  Found{page: T.SearchPage, index: T.Index}

def Found.page(f: Found) -> T.SearchPage:
  match f:
    case Found{p, _}: p

def Found.index(f: Found) -> T.Index:
  match f:
    case Found{_, i}: i

def Ts.search.terms(empty: Bool, +ts: List<&2, Sigma<&2, &2, String, _ => Bool>>, h: String, +th: String, +before: Nat) -> IO(Found):
  match empty:
    case True{}: IO.pure(Found, Found{T.SearchPage{Nil{}, 0n, "", False{}}, T.Index.empty()})
    case False{}:
      do IO<Found>:
        ns : List<&2, Nat> <- Ts.counts(ts, h)
        +xs : List<&2, List<&2, String>> <- D.Db.query(h, Q.sql.search(), [Q.base(ts, ns), Q.n(Q.before(before)), J.Json.show(J.Json.arr(Q.words.json(ts)))], 129)
        +rs : List<&2, T.Row> = Q.rows(xs)
        return Found{Q.search(ts, rs, th, before), Q.search.index(rs)}

# T.Index.search over the store: the same rows, visits, cursor and more
def Ts.search(h: String, +q: String, +th: String, +before: Nat) -> IO(Found):
  +ts = Q.terms.of(q)
  Ts.search.terms(List.is_empty(&2, Sigma<&2, &2, String, _ => Bool>, ts), ts, h, th, before)

# the recent-only index (Index.of's recent order) from the store and st
def Ts.recent(h: String, +st: M.State) -> IO(T.Index):
  do IO<T.Index>:
    xs : List<&2, List<&2, String>> <- D.Db.query(h, Q.sql.recent(), Nil{}, 4294967295)
    return Q.recent(xs, st)
