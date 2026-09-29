import Base
import ./json.bend as J
import ./model.bend as M
import ./codec.bend as C

# Threads that live on a linked machine (docs/bots.md, "Threads elsewhere").
#
# A hub shares its bots and their threads with the owner's other machines
# it is linked to. The owning hub stays the authority: it pushes each
# shared change, as its own log numbers it, to every such peer (POST
# /far/push), and a peer that missed some asks for them (POST /far/log,
# paged). The peer keeps what it got (its mirror, one per link) and hands
# it to its clients, which fold it into their read model under ids of
# their own: a thing that lives elsewhere is named by the link and its
# id there ("<link>~<id>", Fr.id), so nothing here can be mistaken for it
# and nothing shows twice. What a client does to such a thread (write,
# stop, answer) goes back to its hub (Fr.route, POST /far/rpc).
#
# Order and loss: a batch says which log number it follows (`since`) and
# where it ends (`to`). A mirror takes a batch only when it follows what it
# has (since <= head), and only the items it lacks (n > head); a batch past
# a gap changes nothing and asks for what is missing (Fr.take). So a
# batch that comes twice, late, or out of order is harmless, and a restart
# or a partition on either side ends in one pull.

# Ids
# ---

# a thing on the machine a link reaches, named here
def Fr.id(+link: String, +id: String) -> String:
  link ++ "~" ++ id

# the same, keeping "" (no project, no parent) as it is
def Fr.opt(+link: String, +id: String) -> String:
  Bool.pick(String, String.is_empty(id), "", Fr.id(link, id))

# whether an id names a thing elsewhere (local ids never hold a "~")
def Fr.is(+id: String) -> Bool:
  String.contains(id, "~")

def Fr.link.k(ps: List<&2, String>) -> String:
  match ps:
    case l <> _ <> _:
      l
    case _:
      ""

# the link an id elsewhere lives behind ("" for an id here)
def Fr.link(+id: String) -> String:
  Fr.link.k(String.split(id, '~'))

def Fr.local.k(ps: List<&2, String>, +id: String) -> String:
  match ps:
    case _ <> +t <> +r:
      String.join(t <> r, "~")
    case _:
      id

# its id on its own machine (an id here is itself)
def Fr.local(+id: String) -> String:
  Fr.local.k(String.split(id, '~'), id)

# Changes, as a client here reads them
# ------------------------------------
# The owning hub's change renamed into this hub's ids. Only what shows a
# thread, a bot and its space goes; settings, devices, links, webhooks,
# rooms (shared rooms travel on their own), ordering and usage stay home
# (None).

def Fr.change(+l: String, c: M.Change) -> Maybe<&2, M.Change>:
  match c:
    case M.ThreadCreated{+id, +project, title, env, branch, worktree, provider, model, at}:
      Some{M.ThreadCreated{Fr.id(l, id), Fr.opt(l, project), title, env, branch, worktree, provider, model, at}}
    case M.ThreadRenamed{+id, title, at}:
      Some{M.ThreadRenamed{Fr.id(l, id), title, at}}
    case M.MessagePosted{+thread, msg, role, text, at}:
      Some{M.MessagePosted{Fr.id(l, thread), msg, role, text, at}}
    case M.TurnChanged{+thread, state, at}:
      Some{M.TurnChanged{Fr.id(l, thread), state, at}}
    case M.PendingChanged{+thread, count, at}:
      Some{M.PendingChanged{Fr.id(l, thread), count, at}}
    case M.ActivityLogged{+thread, act, tone, kind, summary, at}:
      Some{M.ActivityLogged{Fr.id(l, thread), act, tone, kind, summary, at}}
    case M.ThreadSettled{+id, manual, at}:
      Some{M.ThreadSettled{Fr.id(l, id), manual, at}}
    case M.ThreadUnsettled{+id, at}:
      Some{M.ThreadUnsettled{Fr.id(l, id), at}}
    case M.ThreadArchived{+id, b, at}:
      Some{M.ThreadArchived{Fr.id(l, id), b, at}}
    case M.ThreadDeleted{+id, at}:
      Some{M.ThreadDeleted{Fr.id(l, id), at}}
    case M.ModesSet{+id, runtime, interaction, model, at}:
      Some{M.ModesSet{Fr.id(l, id), runtime, interaction, model, at}}
    case M.TaskDelegated{+task, +parent, +child, depth, provider, model, at}:
      Some{M.TaskDelegated{Fr.id(l, task), Fr.opt(l, parent), Fr.opt(l, child), depth, provider, model, at}}
    case M.TaskStateSet{+task, state, summary, at}:
      Some{M.TaskStateSet{Fr.id(l, task), state, summary, at}}
    case M.TaskDelivered{+task, at}:
      Some{M.TaskDelivered{Fr.id(l, task), at}}
    case M.TurnQueued{+thread, msg, text, at}:
      Some{M.TurnQueued{Fr.id(l, thread), msg, text, at}}
    case M.QueueTaken{+thread, at}:
      Some{M.QueueTaken{Fr.id(l, thread), at}}
    case M.AskOpened{+id, +thread, kind, tool, detail, options, at}:
      Some{M.AskOpened{Fr.id(l, id), Fr.id(l, thread), kind, tool, detail, options, at}}
    case M.AskClosed{+id, answer, at}:
      Some{M.AskClosed{Fr.id(l, id), answer, at}}
    case M.QueueEdited{+thread, msg, text, at}:
      Some{M.QueueEdited{Fr.id(l, thread), msg, text, at}}
    case M.QueueRemoved{+thread, msg, at}:
      Some{M.QueueRemoved{Fr.id(l, thread), msg, at}}
    case M.QueueMoved{+thread, msg, to, at}:
      Some{M.QueueMoved{Fr.id(l, thread), msg, to, at}}
    case M.QueueTakenOne{+thread, msg, at}:
      Some{M.QueueTakenOne{Fr.id(l, thread), msg, at}}
    case M.ProviderSet{+id, provider, model, at}:
      Some{M.ProviderSet{Fr.id(l, id), provider, model, at}}
    case M.TodosSet{+thread, todos, at}:
      Some{M.TodosSet{Fr.id(l, thread), todos, at}}
    case M.BotSet{+id, name, +thread, look, persona, at}:
      Some{M.BotSet{Fr.id(l, id), name, Fr.id(l, thread), look, persona, at}}
    case M.BotDeleted{+id, at}:
      Some{M.BotDeleted{Fr.id(l, id), at}}
    case M.RoutineSet{+id, +bot, name, cron, prompt, on, at}:
      Some{M.RoutineSet{Fr.id(l, id), Fr.id(l, bot), name, cron, prompt, on, at}}
    case M.RoutineDeleted{+id, at}:
      Some{M.RoutineDeleted{Fr.id(l, id), at}}
    case M.RoutineFired{+id, at}:
      Some{M.RoutineFired{Fr.id(l, id), at}}
    case M.MemorySaved{+bot, key, kind, text, tags, at}:
      Some{M.MemorySaved{Fr.id(l, bot), key, kind, text, tags, at}}
    case M.MemoryForgot{+bot, key, at}:
      Some{M.MemoryForgot{Fr.id(l, bot), key, at}}
    case M.SpaceSet{+bot, spec, at}:
      Some{M.SpaceSet{Fr.id(l, bot), spec, at}}
    case M.SpacePageSet{+bot, html, at}:
      Some{M.SpacePageSet{Fr.id(l, bot), html, at}}
    case _:
      None{}

# What the owning hub shares
# --------------------------
# Its bots and every thread that belongs to no project (a bot's own), with
# what happens in them: turns, asks, the tasks they delegate. Nothing
# about projects, settings, devices, links, hooks or rooms.

def Fr.st.threads(s: M.State) -> Map<&2, M.Thread>:
  match s:
    case M.State{_, ts, _, _, _, _, _, _, _, _, _}:
      ts

def Fr.st.asks(s: M.State) -> Map<&2, M.Ask>:
  match s:
    case M.State{_, _, _, _, _, _, _, ak, _, _, _}:
      ak

def Fr.st.tasks(s: M.State) -> Map<&2, M.Task>:
  match s:
    case M.State{_, _, _, _, tk, _, _, _, _, _, _}:
      tk

def Fr.thread.project(t: M.Thread) -> String:
  match t:
    case M.Thread{_, p, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      p

def Fr.got.thread(r: Map<&2, M.Thread> & M.Thread) -> M.Thread:
  (_, t) = r
  t

# a thread kept here that belongs to no project
def Fr.has(r: Map<&2, M.Thread> & Bool) -> Bool:
  (_, b) = r
  b

def Fr.thread.shared(+s: M.State, +th: String) -> Bool:
  Bool.and(Fr.has(Map.has(&2, M.Thread, Fr.st.threads(s), th)),
    String.is_empty(Fr.thread.project(Fr.got.thread(Map.get(M.Thread, M.Thread.blank(th), Fr.st.threads(s), th)))))

def Fr.ask.thread(r: Map<&2, M.Ask> & M.Ask) -> String:
  match r:
    case (_, M.Ask{_, t, _, _, _, _, _, _}):
      t

def Fr.task.parent(r: Map<&2, M.Task> & M.Task) -> String:
  match r:
    case (_, M.Task{_, p, _, _, _, _, _, _, _}):
      p

def Fr.ask.shared(+s: M.State, +id: String) -> Bool:
  Fr.thread.shared(s, Fr.ask.thread(Map.get(M.Ask, M.Ask{id, "", "", "", "", "", False{}, ""}, Fr.st.asks(s), id)))

def Fr.task.shared(+s: M.State, +id: String) -> Bool:
  Fr.thread.shared(s, Fr.task.parent(Map.get(M.Task, M.Task.blank(id), Fr.st.tasks(s), id)))

# whether a change (with the state after it) goes to the owner's other
# machines
def Fr.shared(+s: M.State, c: M.Change) -> Bool:
  match c:
    case M.ThreadCreated{+id, _, _, _, _, _, _, _, _}:
      Fr.thread.shared(s, id)
    case M.ThreadRenamed{+id, _, _}:
      Fr.thread.shared(s, id)
    case M.MessagePosted{+thread, _, _, _, _}:
      Fr.thread.shared(s, thread)
    case M.TurnChanged{+thread, _, _}:
      Fr.thread.shared(s, thread)
    case M.PendingChanged{+thread, _, _}:
      Fr.thread.shared(s, thread)
    case M.ActivityLogged{+thread, _, _, _, _, _}:
      Fr.thread.shared(s, thread)
    case M.ThreadSettled{+id, _, _}:
      Fr.thread.shared(s, id)
    case M.ThreadUnsettled{+id, _}:
      Fr.thread.shared(s, id)
    case M.ThreadArchived{+id, _, _}:
      Fr.thread.shared(s, id)
    case M.ThreadDeleted{+id, _}:
      Fr.thread.shared(s, id)
    case M.ModesSet{+id, _, _, _, _}:
      Fr.thread.shared(s, id)
    case M.TaskDelegated{_, +parent, _, _, _, _, _}:
      Fr.thread.shared(s, parent)
    case M.TaskStateSet{+task, _, _, _}:
      Fr.task.shared(s, task)
    case M.TaskDelivered{+task, _}:
      Fr.task.shared(s, task)
    case M.TurnQueued{+thread, _, _, _}:
      Fr.thread.shared(s, thread)
    case M.QueueTaken{+thread, _}:
      Fr.thread.shared(s, thread)
    case M.AskOpened{_, +thread, _, _, _, _, _}:
      Fr.thread.shared(s, thread)
    case M.AskClosed{+id, _, _}:
      Fr.ask.shared(s, id)
    case M.QueueEdited{+thread, _, _, _}:
      Fr.thread.shared(s, thread)
    case M.QueueRemoved{+thread, _, _}:
      Fr.thread.shared(s, thread)
    case M.QueueMoved{+thread, _, _, _}:
      Fr.thread.shared(s, thread)
    case M.QueueTakenOne{+thread, _, _}:
      Fr.thread.shared(s, thread)
    case M.ProviderSet{+id, _, _, _}:
      Fr.thread.shared(s, id)
    case M.TodosSet{+thread, _, _}:
      Fr.thread.shared(s, thread)
    case M.BotSet{_, _, _, _, _, _}:
      True{}
    case M.BotDeleted{_, _}:
      True{}
    case M.RoutineSet{_, _, _, _, _, _, _}:
      True{}
    case M.RoutineDeleted{_, _}:
      True{}
    case M.RoutineFired{_, _}:
      True{}
    case M.MemorySaved{_, _, _, _, _, _}:
      True{}
    case M.MemoryForgot{_, _, _}:
      True{}
    case M.SpaceSet{_, _, _}:
      True{}
    case M.SpacePageSet{_, _, _}:
      True{}
    case _:
      False{}

# Batches
# -------
# An item is a change as its own hub numbers it (its place in that log)
# and sends it (its wire JSON, ids its own).

type Item is Data:
  Item{n: Nat, c: J.Json}

def Item.n(i: Item) -> Nat:
  match i:
    case Item{n, _}:
      n

def Item.json(i: Item) -> J.Json:
  match i:
    case Item{n, c}:
      J.Json.obj([J.KV{"n", J.Json.nat(n)}, J.KV{"c", c}])

def Item.of(+o: J.Json) -> Item:
  Item{J.Json.get_nat(o, "n", 0n), Maybe.default(&2, J.Json, J.Json.get(o, "c"), J.Null{})}

def Fr.items.of(os: List<&2, J.Json>) -> List<&2, Item>:
  match os:
    case Nil{}:
      Nil{}
    case +o <> t:
      Item.of(o) <> Fr.items.of(t)

def Fr.items.json(xs: List<&2, Item>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      Item.json(x) <> Fr.items.json(t)

def Fr.fresh.k(keep: Bool, x: Item, rest: List<&2, Item>) -> List<&2, Item>:
  match keep:
    case True{}:
      x <> rest
    case False{}:
      rest

# the items after head, in order
def Fr.fresh(xs: List<&2, Item>, +head: Nat) -> List<&2, Item>:
  match xs:
    case Nil{}:
      Nil{}
    case Item{+n, c} <> t:
      Fr.fresh.k(Nat.is_gt(n, head), Item{n, c}, Fr.fresh(t, head))

# what a batch leaves: the new head, the items to take, and whether a gap
# came first (then nothing is taken and the rest is asked for)
type Got is Data:
  Got{head: Nat, items: List<&2, Item>, gap: Bool}

def Fr.take.k(gap: Bool, +head: Nat, +to: Nat, xs: List<&2, Item>) -> Got:
  match gap:
    case True{}:
      Got{head, Nil{}, True{}}
    case False{}:
      Got{Bool.pick(Nat, Nat.is_gt(to, head), to, head), Fr.fresh(xs, head), False{}}

# a batch that follows `since` and ends at `to`, for a mirror at `head`
def Fr.take(+head: Nat, +since: Nat, +to: Nat, xs: List<&2, Item>) -> Got:
  Fr.take.k(Nat.is_gt(since, head), head, to, xs)

def Got.head(g: Got) -> Nat:
  match g:
    case Got{h, _, _}:
      h

def Got.items(g: Got) -> List<&2, Item>:
  match g:
    case Got{_, xs, _}:
      xs

def Got.gap(g: Got) -> Bool:
  match g:
    case Got{_, _, x}:
      x

# A client's fold
# ---------------
# A client keeps how far it has each link's changes beside the read model
# (a Nav under "far~<link>", so a fresh log forgets both at once), folds
# in only what it lacks, and never counts those changes in its own log's
# sequence (M.State.apply.go: a reconnect still asks this hub for exactly
# the changes it missed).

def Fr.nav(+link: String) -> String:
  "far~" ++ link

def Fr.head(+s: M.State, +link: String) -> Nat:
  M.Nav.until(M.Nav.get(M.State.navs(s), Fr.nav(link)))

def Fr.head.set(s: M.State, +link: String, +h: Nat) -> M.State:
  M.State.nav((x => M.Nav{h, "", ""}), s, Fr.nav(link))

def Fr.apply.k(m: Maybe<&2, M.Change>, s: M.State) -> M.State:
  match m:
    case Some{c}:
      M.State.apply.go(s, c)
    case None{}:
      s

def Fr.apply.c(m: Maybe<&2, M.Change>, +link: String, s: M.State) -> M.State:
  match m:
    case Some{c}:
      Fr.apply.k(Fr.change(link, c), s)
    case None{}:
      s

def Fr.apply(xs: List<&2, Item>, +link: String, s: M.State) -> M.State:
  match xs:
    case Nil{}:
      s
    case Item{_, +c} <> t:
      Fr.apply(t, link, Fr.apply.c(C.Change.decode(c), link, s))

def Fr.fold.k(g: Got, +link: String, s: M.State) -> M.State:
  match g:
    case Got{_, _, True{}}:
      s
    case Got{h, xs, False{}}:
      Fr.head.set(Fr.apply(xs, link, s), link, h)

# a link's batch folded into a client's read model
def Fr.fold(+s: M.State, +link: String, +since: Nat, +to: Nat, xs: List<&2, Item>) -> M.State:
  Fr.fold.k(Fr.take(Fr.head(s, link), since, to, xs), link, s)

# A hub's mirror of a link
# ------------------------
# What the other end sent, in its order, how far it goes, its name, and
# whether it answered last time (away: shown, stale, until it does).

type In is Data:
  In{link: String, name: String, head: Nat, items: List<&2, Item>, away: Bool}

def In.new(+link: String, +name: String) -> In:
  In{link, name, 0n, Nil{}, True{}}

def In.link(i: In) -> String:
  match i:
    case In{l, _, _, _, _}:
      l

def In.head(i: In) -> Nat:
  match i:
    case In{_, _, h, _, _}:
      h

def In.away(i: In) -> Bool:
  match i:
    case In{_, _, _, _, a}:
      a

def In.away.set(i: In, a: Bool) -> In:
  match i:
    case In{l, n, h, xs, _}:
      In{l, n, h, xs, a}

def In.name.set(i: In, +nm: String) -> In:
  match i:
    case In{l, n, h, xs, a}:
      In{l, Bool.pick(String, String.is_empty(nm), n, nm), h, xs, a}

def In.put.k(g: Got, i: In) -> In:
  match g i:
    case Got{_, _, True{}} _:
      i
    case Got{h, ys, False{}} In{l, n, _, xs, _}:
      In{l, n, h, List.append(&2, Item, xs, ys), False{}}

# a batch into the mirror (it answered, so it is here)
def In.put(+i: In, +since: Nat, +to: Nat, xs: List<&2, Item>) -> In:
  In.put.k(Fr.take(In.head(i), since, to, xs), i)

# what a batch brings that the mirror lacks (Nil on a gap)
def In.got(+i: In, +since: Nat, +to: Nat, xs: List<&2, Item>) -> Got:
  Fr.take(In.head(i), since, to, xs)

# the message a client folds: {"t":"far","link","name","away","since","head","items"}
def Fr.msg(+link: String, +name: String, away: Bool, +since: Nat, +head: Nat, xs: List<&2, Item>) -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"far"}}, J.KV{"link", J.Str{link}}, J.KV{"name", J.Str{name}}, J.KV{"away", J.Json.bool(away)},
    J.KV{"since", J.Json.nat(since)}, J.KV{"head", J.Json.nat(head)}, J.KV{"items", J.Json.arr(Fr.items.json(xs))}]))

# all a mirror holds, for a client that just joined
def In.msg(i: In) -> String:
  match i:
    case In{+l, +n, +h, xs, a}:
      Fr.msg(l, n, a, 0n, h, xs)

# Mirrors by link
# ---------------

def Ins.find(ms: List<&2, In>, +link: String) -> Maybe<&2, In>:
  match ms:
    case Nil{}:
      None{}
    case +i <> t:
      Bool.pick(Maybe<&2, In>, String.eq(In.link(i), link), Some{i}, Ins.find(t, link))

def Ins.get(+ms: List<&2, In>, +link: String, +name: String) -> In:
  Maybe.default(&2, In, Ins.find(ms, link), In.new(link, name))

# the mirror of `link` replaced (added when new)
def Ins.set(ms: List<&2, In>, +i: In) -> List<&2, In>:
  match ms:
    case Nil{}:
      [i]
    case +x <> +t:
      Bool.pick(List<&2, In>, String.eq(In.link(x), In.link(i)), i <> t, x <> Ins.set(t, i))

# Requests to a thread elsewhere
# ------------------------------
# A request naming a thread, an ask or a bot elsewhere goes to the hub it
# lives on, with that hub's ids; only these may (Fr.may): writing to it,
# stopping it, answering it, its queue, settling it, a side question, its
# modes, and a bot's space and routines. Anything else is refused here.

def Fr.methods() -> List<&2, String>:
  ["turn.start", "turn.interrupt", "ask.answer", "queue.move", "queue.remove", "queue.resume", "queue.steer", "queue.edit",
   "thread.settle", "thread.unsettle", "thread.btw", "thread.modes", "thread.provider", "thread.effort", "bots.space", "bots.routine_run"]

def Fr.may.go(ms: List<&2, String>, +m: String) -> Bool:
  match ms:
    case Nil{}:
      False{}
    case x <> t:
      Bool.or(String.eq(x, m), Fr.may.go(t, m))

def Fr.may(+m: String) -> Bool:
  Fr.may.go(Fr.methods(), m)

# the params that name a thing (the ones renamed on the way)
def Fr.keys() -> List<&2, String>:
  ["thread", "id", "bot"]

def Fr.key(+k: String) -> Bool:
  Fr.may.go(Fr.keys(), k)

# the link a request's params name, "" when they name nothing elsewhere
def Fr.params.link(fs: J.Json) -> String:
  match fs:
    case J.Field{+k, J.Str{+v}, t}:
      Bool.pick(String, Bool.and(Fr.key(k), Fr.is(v)), Fr.link(v), Fr.params.link(t))
    case J.Field{_, _, t}:
      Fr.params.link(t)
    case _:
      ""

# the params with the link's ids made local
def Fr.params.local(fs: J.Json, +link: String) -> J.Json:
  match fs:
    case J.Field{+k, J.Str{+v}, t}:
      J.Field{k, J.Str{Bool.pick(String, Bool.and(Fr.key(k), String.eq(Fr.link(v), link)), Fr.local(v), v)}, Fr.params.local(t, link)}
    case J.Field{k, v, t}:
      J.Field{k, v, Fr.params.local(t, link)}
    case x:
      x

def Fr.obj.fields(o: J.Json) -> J.Json:
  match o:
    case J.Obj{fs}:
      fs
    case _:
      J.End{}

def Fr.is.some(m: Maybe<&2, M.Change>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

# a request bound elsewhere: which link, and the request as that hub
# takes it (its method, its params in its ids; no request id)
type Route is Data:
  Route{link: String, m: String, body: String}

def Fr.route.k(+link: String, +m: String, +fs: J.Json) -> Maybe<&2, Route>:
  Bool.pick(Maybe<&2, Route>, String.is_empty(link), None{},
    Some{Route{link, m, J.Json.show(J.Json.obj([J.KV{"id", J.Num{"0"}}, J.KV{"m", J.Str{m}}, J.KV{"p", J.Obj{Fr.params.local(fs, link)}}]))}})

def Route.link.of(m: Maybe<&2, Route>) -> String:
  match m:
    case Some{Route{l, _, _}}:
      l
    case None{}:
      ""

# None: a request for this hub
def Fr.route(+o: J.Json) -> Maybe<&2, Route>:
  Fr.route.k(Fr.params.link(Fr.obj.fields(J.Json.get_obj(o, "p"))), J.Json.get_str(o, "m", ""), Fr.obj.fields(J.Json.get_obj(o, "p")))

# On the owning hub: a request from a linked machine is taken only when it
# is one of Fr.methods and what it names is shared (a bot's thread, an ask
# in one, a bot)
def Fr.allowed.k(+s: M.State, +m: String, +p: J.Json) -> Bool:
  Bool.pick(Bool, String.eq(m, "ask.answer"), Fr.ask.shared(s, J.Json.get_str(p, "id", "")),
    Bool.pick(Bool, Bool.or(String.eq(m, "bots.space"), String.eq(m, "bots.routine_run")), Bool.not(String.is_empty(J.Json.get_str(p, "bot", J.Json.get_str(p, "id", "")))),
      Fr.thread.shared(s, J.Json.get_str(p, "thread", ""))))

def Fr.allowed(+s: M.State, +o: J.Json) -> Bool:
  Bool.and(Fr.may(J.Json.get_str(o, "m", "")), Fr.allowed.k(s, J.Json.get_str(o, "m", ""), J.Json.get_obj(o, "p")))

# How a thing elsewhere is shown
# ------------------------------
# its machine's name beside its own ("Kit · desk"); nothing for one here

def Fr.where(+id: String, +name: String) -> String:
  Bool.pick(String, Fr.is(id), " · " ++ name, "")
