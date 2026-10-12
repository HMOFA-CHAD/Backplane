import Base
import ./model.bend as M
import ./bot.bend as BT
import ./far.bend as FR

# The uberbot (docs/uber.md)
# --------------------------
# One bot the person made their main interface: UberSet (model.bend) folds
# as the settings uber.bot (its id here) and uber.uid (its id across
# machines). Nothing promotes a bot by itself.

# a bot of this machine, alive
def Uber.live(+st: M.State, +id: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(id)), Bool.and(Bool.not(FR.Fr.is(id)), BT.Bot.live(BT.World.bot(M.State.bots(st), id))))

def Uber.bot.k(live: Bool, +id: String) -> String:
  Bool.pick(String, live, id, "")

# the uberbot's bot id, "" when none, or when its bot is gone or elsewhere
def Uber.bot(+st: M.State) -> String:
  Uber.bot.k(Uber.live(st, M.Setting.get(st, "uber.bot", "")), M.Setting.get(st, "uber.bot", ""))

def Uber.is(+st: M.State, +id: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(id)), String.eq(Uber.bot(st), id))

# its id across machines
def Uber.uid(+now: Nat, +seed: String) -> String:
  "u" ++ Nat.show(now) ++ "-" ++ seed

# what promoting asks the log for: an error text, or the changes to log
type Promo is Data:
  Promo{err: String, log: List<&2, M.Change>}

def Promo.err(p: Promo) -> String:
  match p:
    case Promo{e, _}:
      e

def Promo.log(p: Promo) -> List<&2, M.Change>:
  match p:
    case Promo{_, l}:
      l

# promote a live bot of this machine ("" demotes): a far or missing bot is
# refused, the bot already the uberbot (or no uberbot to demote) changes
# nothing, and a bot keeps the uid it has
def Uber.promote.demote(+raw: String, +now: Nat) -> Promo:
  Bool.pick(Promo, String.is_empty(raw), Promo{"", Nil{}}, Promo{"", [M.UberSet{"", "", now}]})

def Uber.promote.same(+bot: String, +raw: String, +have: String, +uid: String, +now: Nat) -> Promo:
  Bool.pick(Promo, Bool.and(String.eq(bot, raw), Bool.not(String.is_empty(have))), Promo{"", Nil{}},
    Promo{"", [M.UberSet{bot, uid, now}]})

def Uber.promote.live(live: Bool, +bot: String, +raw: String, +have: String, +uid: String, +now: Nat) -> Promo:
  match live:
    case True{}:
      Uber.promote.same(bot, raw, have, uid, now)
    case False{}:
      Promo{"only a bot on this machine can be the uberbot", Nil{}}

def Uber.promote.k(empty: Bool, live: Bool, +bot: String, +raw: String, +have: String, +uid: String, +now: Nat) -> Promo:
  match empty:
    case True{}:
      Uber.promote.demote(raw, now)
    case False{}:
      Uber.promote.live(live, bot, raw, have, uid, now)

def Uber.promote(+st: M.State, +bot: String, +uid: String, +now: Nat) -> Promo:
  Uber.promote.k(String.is_empty(bot), Uber.live(st, bot), bot, M.Setting.get(st, "uber.bot", ""), M.Setting.get(st, "uber.uid", ""), uid, now)
