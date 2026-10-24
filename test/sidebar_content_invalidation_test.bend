import Base
import ./check.bend as C
import ./sidebar_content_test.bend as F
import ./sidebar_wire_test.bend as B
import ../src/server/thin-sidebar-wire.bend as W
import ../src/server/thin-actor.bend as A
import ../src/core/json.bend as J

def informed() -> A.Actor:
  A.Actor.info(F.initial(), J.Json.obj([J.KV{"info", J.Json.obj([J.KV{"models", J.Str{"fresh models"}}])}]))
def sheeted() -> A.Actor:
  A.Actor.sheets(F.initial(), J.Json.obj([J.KV{"t", J.Str{"sheets"}}, J.KV{"items", J.Json.arr(Nil{})}]))
def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("targeted info retains only last sent receipt", F.retained(informed()), "1")
    C.Check.str("targeted info drops full picture authority", W.Region.key(A.Sidebar.memos(informed())), "")
    C.Check.str("fresh exact sidebar after info can reuse sent receipt", F.token(F.next(informed(), F.request(True{}, "1", "2"), B.picture()), "base"), "1")
    C.Check.str("fresh changed sidebar after info stays full", F.token(F.next(informed(), F.request(True{}, "1", "2"), F.changed()), "base"), "")
    C.Check.str("sheet notification retains sent receipt", F.retained(sheeted()), "1")
    C.Check.str("sheet notification drops full picture authority", W.Region.key(A.Sidebar.memos(sheeted())), "")
    C.Check.str("fresh exact sidebar after sheets can reuse receipt", F.token(F.next(sheeted(), F.request(True{}, "1", "2"), B.picture()), "base"), "1")
    C.Check.str("dirty command still discards receipt", F.retained(A.Actor.mark_dirty(F.initial())), "0")
