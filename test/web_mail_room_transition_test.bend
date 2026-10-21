import Base
import ./check.bend as C
import ./web_mail_room_nodes.bend as W
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/web/mail-actions.bend as MA
import ../src/web/mailroom.bend as WM
import ../src/web/dom.bend as D

# Bind this test to the room owner's final client bytes before emission.
# These are production UI actions/replies; their RPC commands are never run.
def act_ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}: u

def fixture() -> U.Ui:
  U.Ui.scratch_set(U.Ui.fold([
    M.BotSet{"bub", "Bub", "bub-thread", 0n, "", 1n}, M.UberSet{"bub", "room-transition", 1n},
    M.ConvSet{"room:A", "Healthy A", "room", "bot:bub\nbot:member-a", "", "", 1n},
    M.ConvSet{"room:B", "Selected B", "room", "bot:bub\nbot:member-b", "", "", 1n}], U.Ui.init(1n)), "@bot", "bub")

def data(+conv: String, +member: String, msg: String, text: String) -> J.Json:
  J.Json.obj([J.KV{"conv", J.Json.obj([J.KV{"id", J.Str{conv}}, J.KV{"subject", J.Str{conv}},
    J.KV{"parts", J.Json.arr([J.Str{"bot:bub"}, J.Str{member}])}, J.KV{"project", J.Str{""}}, J.KV{"status", J.Str{"open"}}])},
    J.KV{"mails", J.Json.arr([J.Json.obj([J.KV{"id", J.Str{msg}}, J.KV{"from", J.Str{member}}, J.KV{"to", J.Str{conv}},
      J.KV{"kind", J.Str{"room"}}, J.KV{"want", J.Str{"fyi"}}, J.KV{"at", J.Json.nat(2n)}, J.KV{"text", J.Str{text}}])])}])

def receive(+u: U.Ui, id: String, ok: Bool, result: J.Json, error: String) -> U.Ui:
  +o = J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Str{id}}, J.KV{"ok", J.Flag{ok}}, J.KV{"result", result}, J.KV{"error", J.Str{error}}])
  U.Mailv.reply(MA.MA.recv(u, o), o)

def success(+u: U.Ui, +conv: String, member: String, msg: String, text: String) -> U.Ui:
  receive(u, U.Ui.scratch(u, "@mr.read"), True{}, data(conv, member, msg, text), "")

def seed_b(cached: Bool, +u: U.Ui) -> U.Ui:
  match cached:
    case False{}: u
    case True{}:
      +b = act_ui(MA.MA.open(u, "room:B"))
      success(b, "room:B", "bot:member-b", "b-cached", "B cached body")

def begin(cached_b: Bool) -> U.Ui:
  +a = act_ui(MA.MA.open(fixture(), "room:A"))
  +loaded_a = success(a, "room:A", "bot:member-a", "a-cached", "A cached body")
  +with_b = seed_b(cached_b, loaded_a)
  +again_a = act_ui(MA.MA.open(with_b, "room:A"))
  +kept_id = U.Ui.scratch_set(again_a, "@test.a", U.Ui.scratch(again_a, "@mr.read"))
  +b = act_ui(MA.MA.open(kept_id, "room:B"))
  U.Ui.scratch_set(b, "@test.b", U.Ui.scratch(b, "@mr.read"))

def a_ok(+u: U.Ui) -> U.Ui:
  receive(u, U.Ui.scratch(u, "@test.a"), True{}, data("room:A", "bot:member-a", "a-late", "A late body"), "")

def a_fail(+u: U.Ui) -> U.Ui:
  receive(u, U.Ui.scratch(u, "@test.a"), False{}, J.Null{}, "A stale failure")

def b_fail(+u: U.Ui) -> U.Ui:
  receive(u, U.Ui.scratch(u, "@test.b"), False{}, J.Null{}, "B body unavailable")

def scenario_choose(k: Nat, u: U.Ui) -> U.Ui:
  match k:
    case 0n: u
    case 1n: b_fail(a_ok(u))
    case 2n: a_ok(b_fail(u))
    case 3n: b_fail(u)
    case 4n: act_ui(MA.MA.open(a_ok(b_fail(u)), "room:A"))
    case 5n: a_fail(b_fail(u))
    case 6n: b_fail(a_fail(u))
    case _: u

def scenario_state(+k: Nat) -> U.Ui:
  scenario_choose(k, begin(Bool.or(Nat.is_eq(k, 3n), Nat.is_eq(k, 7n))))

def scenario(k: Nat) -> D.Node:
  WM.WM.page(scenario_state(k))

# The checks of test/tools/web_mail_room_transition.mjs, run here so
# scripts/test.sh runs them too. Bodies and recipients are sorted, "|"-joined.
def bodies(n: D.Node) -> String:
  W.Wn.class_texts(n, "mail-text")

def targets(n: D.Node) -> String:
  W.Wn.act_values(n, "mail-to")

def read_hint(n: D.Node) -> String:
  W.Wn.key_text(n, "mail-read-status")

def failed_b(k: Nat, +label: String) -> IO(Unit):
  do IO<Unit>:
    +s : D.Node = scenario(k)
    C.Check.str(label ++ " has no A body under B", bodies(s), "")
    C.Check.str(label ++ " has no A recipient under B", targets(s), "")
    C.Check.str(label ++ " preserves exact B error", W.Wn.key_text(s, "mail-error"), "B body unavailable")
    C.Check.str(label ++ " exposes actual alert role", W.Wn.key_attr(s, "mail-error", "role"), "alert")
    C.Check.str(label ++ " renders read-failure hint", read_hint(s), "Messages could not be loaded. See the mail error above.")

def cached_b(+s: D.Node, +label: String) -> IO(Unit):
  do IO<Unit>:
    C.Check.str(label ++ " retains only B body", bodies(s), "B cached body")
    C.Check.str(label ++ " retains only B/member/Room recipients", targets(s), "bot:bub|bot:member-b|room:B")
    C.Check.str(label ++ " does not replace cached text with empty hint", read_hint(s), "")

def main() -> IO(Unit):
  do IO<Unit>:
    +pending : D.Node = scenario(0n)
    C.Check.str("B before RPC has no cached A body", bodies(pending), "")
    C.Check.str("B before RPC has no cached A recipient", targets(pending), "")
    C.Check.str("B before RPC renders loading", read_hint(pending), "Loading message bodies…")
    failed_b(1n, "A success then B failure")
    failed_b(2n, "B failure then A success")
    failed_b(5n, "B failure then stale A error")
    failed_b(6n, "stale A error then B failure")
    +refresh : D.Node = scenario(3n)
    cached_b(refresh, "cached B refresh failure")
    C.Check.str("cached B refresh failure retains backend error alert", W.Wn.key_text(refresh, "mail-error"), "B body unavailable")
    cached_b(scenario(7n), "cached B pending refresh")
    +a : D.Node = scenario(4n)
    C.Check.str("reopen A restores its exact cached bodies", bodies(a), "A cached body|A late body")
    C.Check.str("reopen A restores its own recipients", targets(a), "bot:bub|bot:member-a|room:A")
    C.Check.str("B error does not leak into reopened A", W.Wn.key_text(a, "mail-error"), "")
