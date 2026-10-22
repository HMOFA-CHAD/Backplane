import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/presentation.bend as P
import ../src/core/json.bend as J

# A thin view's session keeps a thread's ordering card (presentation.bend's
# Session.info.key): the fab.look reply sets fab.* info, and a session that
# dropped it never showed the Ready to order bar or the header's Buy it.

def session(+info: List<&2, J.KV>) -> J.Json:
  J.Json.obj([J.KV{"sel", J.Json.str("t1")}, J.KV{"info", J.Json.obj(info)}])

def kept(+k: String) -> String:
  J.Json.get_str(J.Json.get_obj(P.Session.pack(P.Session.adopt(U.Ui.init(0n), session([J.KV{k, J.Json.str("x")}]))), "info"), k, "")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("a session keeps the Ready to order line", kept("fab.ready:t1"), "x")
    C.Check.str("and the Buy it label", kept("fab.buy:t1"), "x")
    C.Check.str("and the card's line", kept("fab.line:t1"), "x")
    C.Check.str("folds are still kept", kept("fold:a1"), "x")
    C.Check.str("other info is still dropped", kept("models"), "")
