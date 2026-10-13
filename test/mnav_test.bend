import Base
import ./check.bend as C
import ./mbots_test.bend as Bots
import ./mplane_test.bend as Plane
import ../src/core/json.bend as J
import ../src/mobile/hubs.bend as H

# Match the native destination key, including the focused hub's unqualified
# room/remote id. Each assertion opens the actual row through Hubs.act.
def nav(+s: J.Json) -> String:
  Bool.pick(String, String.eq(J.Json.get_str(J.Json.get_obj(s, "bot"), "kind", "bot"), "bot"),
    J.Json.get_str(s, "sel", ""),
    "@" ++ J.Json.get_str(J.Json.get_obj(s, "bot"), "kind", "") ++ ":" ++ J.Json.get_str(J.Json.get_obj(s, "bot"), "id", ""))

def row(rs: List<&2, J.Json>, +name: String) -> J.Json:
  match rs:
    case Nil{}:
      J.Null{}
    case +r <> t:
      Bool.pick(J.Json, String.eq(J.Json.get_str(r, "name", ""), name), r, row(t, name))

def from(+h: H.Hubs, +section: String, +name: String) -> J.Json:
  row(J.Json.elems(J.Json.get_obj(H.Hubs.screen(h), section)), name)

def opened(+h: H.Hubs, +r: J.Json, +action: String, +value: String) -> String:
  nav(H.Hubs.screen(H.Hubs.after(H.Hubs.act(h, action, value))))

def check(+label: String, +h: H.Hubs, +r: J.Json, +action: String, +value: String) -> IO(Unit):
  do IO<Unit>:
    C.Check.str(label ++ " present", Bool.show(Bool.not(String.is_empty(J.Json.get_str(r, "nav", "")))), "True")
    C.Check.str(label, opened(h, r, action, value), J.Json.get_str(r, "nav", ""))

def bot(+label: String, +h: H.Hubs, +name: String) -> IO(Unit):
  do IO<Unit>:
    check(label, h, from(h, "bots", name), J.Json.get_str(from(h, "bots", name), "act", "bot"), J.Json.get_str(from(h, "bots", name), "id", ""))

def room(+label: String, +h: H.Hubs) -> IO(Unit):
  do IO<Unit>:
    check(label, h, from(h, "rooms", "den"), "room", J.Json.get_str(from(h, "rooms", "den"), "id", ""))

def uber(+label: String, +h: H.Hubs) -> IO(Unit):
  do IO<Unit>:
    check(label, h, J.Json.get_obj(H.Hubs.screen(h), "uber"), "uber", J.Json.get_str(J.Json.get_obj(H.Hubs.screen(h), "uber"), "id", ""))

def plane.rows(rs: List<&2, J.Json>, +h: H.Hubs) -> IO(Unit):
  match rs:
    case Nil{}:
      do IO<Unit>:
        IO.pure(Unit, Unit{})
    case +r <> t:
      do IO<Unit>:
        check("plane " ++ J.Json.get_str(r, "title", ""), h, r, J.Json.get_str(r, "act", ""), J.Json.get_str(r, "value", ""))
        plane.rows(t, h)

def plane(+h: H.Hubs) -> IO(Unit):
  do IO<Unit>:
    plane.rows(J.Json.elems(J.Json.get_obj(J.Json.get_obj(H.Hubs.screen(h), "plane"), "bots")), h)
    plane.rows(J.Json.elems(J.Json.get_obj(J.Json.get_obj(H.Hubs.screen(h), "plane"), "rooms")), h)
    plane.rows(J.Json.elems(J.Json.get_obj(J.Json.get_obj(H.Hubs.screen(h), "plane"), "run")), h)
    plane.rows(J.Json.elems(J.Json.get_obj(J.Json.get_obj(H.Hubs.screen(h), "plane"), "routines")), h)

def main() -> IO(Unit):
  do IO<Unit>:
    # Restrict to box after loading so the exact same fixture covers one hub.
    bot("one bot", H.Hubs.set(Bots.two(), ["box:3787"]), "Kit")
    bot("two bot", Bots.two(), "Kit")
    room("one room", H.Hubs.set(Bots.two(), ["box:3787"]))
    room("two room", Bots.two())
    bot("one remote", H.Hubs.set(Bots.far(), ["box:3787"]), "Nori")
    bot("two remote", Bots.far(), "Nori")
    uber("one uber", Plane.one(Plane.box()))
    uber("two uber", Plane.two())
    plane(Plane.go(Plane.one(Plane.box()), "uber", "box:3787|b1"))
    plane(Plane.go(Plane.two(), "uber", "box:3787|b1"))
    IO.print("mobile nav tests passed\n")
