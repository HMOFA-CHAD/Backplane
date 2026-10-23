import Base
import ./check.bend as C
import ./thin_browser_handback_test.bend as F
import ../src/core/browser-tabs.bend as T
import ../src/core/cef.bend as CF
import ../src/core/json.bend as J
import ../src/core/client.bend as U
import ../src/server/thin-actor.bend as TA

# Only the new canonical toolbar state path, not the settled native input,
# ownership or history acceptance. The sole controller runs these cases.
def event(+owner: String, +title: String, +url: String) -> J.Json:
  J.Json.obj([J.KV{"page", J.Str{owner}}, J.KV{"url", J.Str{url}}, J.KV{"lease", J.Str{"PRIVATE-MARKER"}},
    J.KV{"tabs", J.Json.arr([J.Json.obj([J.KV{"id", J.Str{"tab-A"}}, J.KV{"title", J.Str{title}}, J.KV{"url", J.Str{url}}, J.KV{"active", J.Flag{True{}}}, J.KV{"grant", J.Str{"PRIVATE-MARKER"}}])])}])

def refresh(+actors: List<&2, TA.Actor>, +session: CF.CefSession) -> TA.Actor:
  TA.Actor.refresh(actors, True{}, F.state(), J.Json.obj(CF.Cef.session.info(session)), J.Json.obj(Nil{}), 2n, F.request(), "browser-view")

def title(+actor: TA.Actor, +owner: String) -> String:
  J.Json.get_str(Maybe.default(&2, J.Json, List.head(&2, J.Json, U.Browse.tabs(TA.Actor.ui(actor), owner)), J.Null{}), "title", "")

def populate(+left: Nat, +session: CF.CefSession) -> CF.CefSession:
  match left:
    case 0n: session
    case 1n+n: populate(n, CF.Cef.session.tabs_set(session, event(Nat.show(n), "Page", "/page")))

def check(name: String, ok: Bool) -> IO(Unit):
  C.Check.str(name, Bool.show(ok), "True")

def main() -> IO(Unit):
  do IO<Unit>:
    +two : CF.CefSession = CF.Cef.session.tabs_set(CF.Cef.empty(), event("review", "Shared Browser two", "/two"))
    +actor : TA.Actor = refresh(Nil{}, two)
    C.Check.str("new thin actor receives current tab title", title(actor, "review"), "Shared Browser two")
    C.Check.str("new thin actor receives current address", U.Browse.url(TA.Actor.ui(actor), "review"), "/two")
    +one : CF.CefSession = CF.Cef.session.tabs_set(two, event("review", "Shared Browser one", "/one"))
    +updated : TA.Actor = refresh([actor], one)
    C.Check.str("canonical metadata replaces previous actor title", title(updated, "review"), "Shared Browser one")
    C.Check.str("renderer reconnect gets latest address without actor cache", U.Browse.url(TA.Actor.ui(refresh(Nil{}, one)), "review"), "/one")
    +other : CF.CefSession = CF.Cef.session.tabs_set(one, event("other", "Other page", "/other"))
    check("owner inventories remain independent", Bool.and(String.eq(title(refresh([updated], other), "review"), "Shared Browser one"), String.eq(title(refresh(Nil{}, other), "other"), "Other page")))
    +closed : CF.CefSession = CF.Cef.session.tabs_set(other, J.Json.obj([J.KV{"page", J.Str{"review"}}, J.KV{"url", J.Str{""}}, J.KV{"tabs", J.Json.arr(Nil{})}]))
    +empty : U.Ui = TA.Actor.ui(refresh([updated], closed))
    check("empty inventory clears tabs and address", Bool.and(List.is_empty(&2, J.Json, U.Browse.tabs(empty, "review")), String.is_empty(U.Browse.url(empty, "review"))))
    check("canonical public metadata excludes private fields", Bool.not(String.contains(J.Json.show(J.Json.obj(CF.Cef.session.info(two))), "PRIVATE-MARKER")))
    check("identical inventory does not invalidate views", Bool.not(CF.Cef.session.tabs_changed(two, event("review", "Shared Browser two", "/two"))))
    check("title or address changes invalidate views", CF.Cef.session.tabs_changed(two, event("review", "Shared Browser one", "/one")))
    check("canonical metadata cache is bounded to 64 owners", Nat.is_eq(List.length(&2, J.KV, CF.Cef.session.tabs(populate(65n, CF.Cef.empty()))), 64n))
    C.Check.str("browser placement and engine lifecycle preserve metadata", title(refresh(Nil{}, CF.Cef.session.done(CF.Cef.session.place_set(two, J.Json.obj(Nil{}), "1"), "chrome", "")), "review"), "Shared Browser two")
    C.Check.str("metadata does not change engine selection", CF.Cef.session.live(two), CF.Cef.session.live(CF.Cef.empty()))
