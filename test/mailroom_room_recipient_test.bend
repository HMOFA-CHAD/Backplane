import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/mailview.bend as MV
import ../src/core/json.bend as J

def opts() -> List<&2, MV.Opt>:
  [MV.Opt{"bot:bb", "Beta"}, MV.Opt{"thread:run", "Active worker"}]

def show(xs: List<&2, MV.Opt>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case MV.Opt{a, label} <> t: show(t, acc ++ a ++ "=" ++ label ++ ";")

def unchanged(+conv: String) -> IO(Unit):
  C.Check.str("nonroom target list unchanged " ++ conv, show(U.Mailv.room.targets(conv, opts()), ""), "bot:bb=Beta;thread:run=Active worker;")

def response(+conv: String) -> J.Json:
  J.Json.obj([J.KV{"conv", J.Json.obj([J.KV{"id", J.Str{conv}}, J.KV{"parts", J.Json.arr([J.Str{"person"}, J.Str{"bot:bb"}, J.Str{"thread:worker"}])}])}, J.KV{"mails", J.Json.arr([])}, J.KV{"more", J.Flag{False{}}}])

def read(+u: U.Ui, +conv: String) -> U.Ui:
  U.Mailv.put(u, U.Mailv.read.put(U.Mailv.data(u), MV.Mv.put_read(U.Mailv.cache(u), response(conv), False{}), conv, Map.new(&2, String), ["thread:run"]))

def payload(cs: List<&2, U.Cmd>) -> J.Json:
  match cs:
    case Nil{}: J.Null{}
    case U.Send{s} <> _: Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})
    case _ <> t: payload(t)

def body_response(+conv: String, +body: String) -> J.Json:
  J.Json.obj([J.KV{"conv", J.Json.obj([J.KV{"id", J.Str{conv}}, J.KV{"parts", J.Json.arr([J.Str{"person"}, J.Str{"bot:onlyA"}])}])}, J.KV{"mails", J.Json.arr([J.Json.obj([J.KV{"id", J.Str{"public-A-id"}}, J.KV{"from", J.Str{"bot:onlyA"}}, J.KV{"to", J.Str{"person"}}, J.KV{"text", J.Str{body}}, J.KV{"at", J.Num{"1"}}])])}, J.KV{"more", J.Flag{False{}}}])

def cached(+u: U.Ui, +conv: String, +text: String) -> U.Ui:
  U.Mailv.put(u, U.Mailv.read.put(U.Mailv.data(u), MV.Mv.put_read(U.Mailv.cache(u), body_response(conv, text), False{}), conv, Map.new(&2, String), Nil{}))

def reply(+id: String, +ok: Bool, result: J.Json) -> J.Json:
  J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{id}}, J.KV{"ok", J.Flag{ok}}, J.KV{"error", J.Str{"mail body unavailable: public-B"}}, J.KV{"result", result}])

def body_text(bs: List<&2, MV.Bub>) -> String:
  match bs:
    case Nil{}: ""
    case MV.Bub{_, _, _, _, _, _, text, _} <> t: text ++ body_text(t)

def binding() -> IO(Unit):
  do IO<Unit>:
    +a : U.Ui = cached(U.Ui.scratch_set(U.Ui.init(100n), "@f.mrreply", "retained newer draft"), "room:A", "A full é🙂 private-to-A fixture")
    +a_open : U.Ui = U.Act.ui(U.Ui.act(a, "mail-open", "room:A"))
    +a_id : String = U.Ui.scratch(a_open, "@mr.read")
    +b_open : U.Ui = U.Act.ui(U.Ui.act(a_open, "mail-open", "room:B"))
    +b_id : String = U.Ui.scratch(b_open, "@mr.read")
    C.Check.str("uncached B has no A text before RPC", body_text(U.Mailv.bubbles(b_open)), "")
    C.Check.str("uncached B has no A recipients before RPC", show(U.Mailv.targets(b_open), ""), "")
    C.Check.str("open retains newer draft", U.Ui.scratch(b_open, "@f.mrreply"), "retained newer draft")
    +stale_a : U.Ui = U.Ui.recv(b_open, reply(a_id, True{}, body_response("room:A", "A full é🙂 private-to-A fixture")))
    C.Check.str("late successful A cannot bind under current B", body_text(U.Mailv.bubbles(stale_a)), "")
    C.Check.str("late A cannot bind recipients under B", show(U.Mailv.targets(stale_a), ""), "")
    C.Check.str("late A leaves B selected", U.Ui.scratch(stale_a, "@mr.conv"), "room:B")
    +failed_b : U.Ui = U.Ui.recv(stale_a, reply(b_id, False{}, J.Null{}))
    C.Check.str("current B failure has no old A text", body_text(U.Mailv.bubbles(failed_b)), "")
    C.Check.str("current B failure has no old A recipients", show(U.Mailv.targets(failed_b), ""), "")
    C.Check.str("current B failure closes its pending slot", U.Ui.scratch(failed_b, "@mr.read"), "")
    +reverse_b : U.Ui = U.Ui.recv(b_open, reply(b_id, False{}, J.Null{}))
    C.Check.str("B failure before late A has no A text", body_text(U.Mailv.bubbles(reverse_b)), "")
    C.Check.str("B failure before late A has no A recipients", show(U.Mailv.targets(reverse_b), ""), "")
    +reverse_a : U.Ui = U.Ui.recv(reverse_b, reply(a_id, True{}, body_response("room:A", "A full é🙂 private-to-A fixture")))
    C.Check.str("reversed B failure then A success remains B-empty", body_text(U.Mailv.bubbles(reverse_a)), "")
    C.Check.str("reversed reply cannot leak recipients", show(U.Mailv.targets(reverse_a), ""), "")
    +known_b : U.Ui = cached(a, "room:B", "B own cached full 漢字")
    +known_open : U.Ui = U.Act.ui(U.Ui.act(known_b, "mail-open", "room:B"))
    C.Check.str("known B cache binds before refresh", body_text(U.Mailv.bubbles(known_open)), "B own cached full 漢字")
    +known_fail : U.Ui = U.Ui.recv(known_open, reply(U.Ui.scratch(known_open, "@mr.read"), False{}, J.Null{}))
    C.Check.str("known B cache survives refresh failure", body_text(U.Mailv.bubbles(known_fail)), "B own cached full 漢字")
    C.Check.str("known B failure does not edit newer draft", U.Ui.scratch(known_fail, "@f.mrreply"), "retained newer draft")
    +reopen_a : U.Ui = U.Act.ui(U.Ui.act(failed_b, "mail-open", "room:A"))
    C.Check.str("reopen A uses A cached latest reply only", body_text(U.Mailv.bubbles(reopen_a)), "A full é🙂 private-to-A fixture")

def main() -> IO(Unit):
  do IO<Unit>:
    binding()
    C.Check.str("room appended after unchanged member order", show(U.Mailv.room.targets("room:r", opts()), ""), "bot:bb=Beta;thread:run=Active worker;room:r=Room;")
    C.Check.str("opaque room ID remains exact", show(U.Mailv.room.targets("room:dm:alpha|beta", opts()), ""), "bot:bb=Beta;thread:run=Active worker;room:dm:alpha|beta=Room;")
    C.Check.str("room option available with zero members", show(U.Mailv.room.targets("room:r", Nil{}), ""), "room:r=Room;")
    C.Check.str("existing room relabeled and deduplicated", show(U.Mailv.room.targets("room:r", [MV.Opt{"bot:bb", "Beta"}, MV.Opt{"room:r", "Old label"}, MV.Opt{"room:r", "Duplicate"}, MV.Opt{"thread:run", "Active worker"}]), ""), "bot:bb=Beta;room:r=Room;thread:run=Active worker;")
    unchanged("pair:bot:a|bot:b")
    unchanged("launch:t")
    unchanged("thread:t")
    unchanged("room:")
    unchanged("room:r/extra")
    unchanged("")
    +u : U.Ui = U.Ui.scratch_set(U.Ui.scratch_set(U.Ui.scratch_set(U.Ui.init(100n), "@mr.conv", "room:r"), "@mr.to", "thread:worker"), "@f.mrreply", "newer é🙂 draft")
    +got : U.Ui = read(u, "room:r")
    C.Check.str("read.put selected individual recipient retained", U.Ui.scratch(got, "@mr.to"), "thread:worker")
    C.Check.str("read.put newer draft retained", U.Ui.scratch(got, "@f.mrreply"), "newer é🙂 draft")
    C.Check.str("read.put existing member and live target prefix retained", show(List.take(&2, MV.Opt, U.Mailv.targets(got), 3n), ""), show(MV.Mv.targets(["person", "bot:bb", "thread:worker"], ["thread:run"], Map.new(&2, String)), ""))
    C.Check.str("read.put single canonical Room at end", show(List.drop(&2, MV.Opt, U.Mailv.targets(got), 3n), ""), "room:r=Room;")
    +nonroom : U.Ui = read(u, "pair:bot:a|bot:b")
    C.Check.str("nonroom read.put targets byte-compatible", show(U.Mailv.targets(nonroom), ""), show(MV.Mv.targets(["person", "bot:bb", "thread:worker"], ["thread:run"], Map.new(&2, String)), ""))
    +selected : U.Ui = U.Act.ui(U.Ui.act(got, "mail-to", "room:r"))
    C.Check.str("explicit Room chip selects canonical target", U.Ui.scratch(selected, "@mr.to"), "room:r")
    C.Check.str("Room choice does not edit draft", U.Ui.scratch(selected, "@f.mrreply"), "newer é🙂 draft")
    +send : J.Json = payload(U.Act.cmds(U.Ui.act(selected, "mail-send", "")))
    C.Check.str("explicit Room uses existing mail RPC", J.Json.get_str(send, "m", ""), "mail.send")
    C.Check.str("explicit Room payload exact to", J.Json.get_str(J.Json.get_obj(send, "p"), "to", ""), "room:r")
    C.Check.str("explicit Room payload same conversation", J.Json.get_str(J.Json.get_obj(send, "p"), "conv", ""), "room:r")
    C.Check.str("explicit Room payload complete Unicode", J.Json.get_str(J.Json.get_obj(send, "p"), "text", ""), "newer é🙂 draft")
