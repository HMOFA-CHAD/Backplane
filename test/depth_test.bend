import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/codec.bend as CD
import ../src/core/hub.bend as B
import ../src/core/bot.bend as BT
import ../src/core/bothub.bend as BH
import ../src/core/mcp.bend as MC

# Conversation depth in rooms (docs/bots.md): one post that N bots each
# answer once is one hop for every answer, however the answers interleave;
# a back-and-forth between bots still stops at BT.Hop.max(), and the one
# past it is held in the room for the person, heard by no bot.

def yes(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

def run(s: M.State, st: B.Step) -> M.State:
  match st:
    case B.Step{cs, _}:
      M.State.replay(cs, s)

def json(+t: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(t), J.Null{})

def req(+m: String, +p: String) -> J.Json:
  json("{\"id\":1,\"m\":\"" ++ m ++ "\",\"p\":" ++ p ++ "}")

def ask(+s: M.State, +now: Nat, +m: String, +p: String) -> B.Step:
  BH.Bots.request(s, now, 1, req(m, p))

def mcp(+s: M.State, +now: Nat, +thread: String, +tool: String, +args: String) -> MC.McpOut:
  BH.Bots.mcp(s, now, thread, J.Null{}, "t", J.Json.arr(Nil{}), Nil{}, "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"" ++ tool ++ "\",\"arguments\":" ++ args ++ "}}")

def out.reply(o: MC.McpOut) -> String:
  match o:
    case MC.McpOut{r, _, _}:
      r

def out.step(o: MC.McpOut) -> B.Step:
  match o:
    case MC.McpOut{_, st, _}:
      st

def post(+s: M.State, +now: Nat, +thread: String, +room: String, +text: String) -> MC.McpOut:
  mcp(s, now, thread, "room_post", "{\"room\":\"" ++ room ++ "\",\"text\":\"" ++ text ++ "\"}")

# the hop of the step's first post, and how many bots it wakes
def hop.of(cs: List<&2, M.Change>) -> String:
  match cs:
    case Nil{}:
      "none"
    case M.RoomPosted{_, _, _, _, h, _} <> _:
      Nat.show(h)
    case _ <> t:
      hop.of(t)

def wakes(cs: List<&2, M.Change>) -> Nat:
  match cs:
    case Nil{}:
      0n
    case M.BotWoke{_, _, _} <> t:
      1n+wakes(t)
    case _ <> t:
      wakes(t)

def step.hop(st: B.Step) -> String:
  match st:
    case B.Step{cs, _}:
      hop.of(cs)

def text.of(cs: List<&2, M.Change>) -> String:
  match cs:
    case Nil{}:
      ""
    case M.RoomPosted{_, _, _, t, _, _} <> _:
      t
    case _ <> t:
      text.of(t)

def step.text(st: B.Step) -> String:
  match st:
    case B.Step{cs, _}:
      text.of(cs)

def step.wakes(st: B.Step) -> String:
  match st:
    case B.Step{cs, _}:
      Nat.show(wakes(cs))

def sends(os: List<&2, B.Out>) -> Nat:
  match os:
    case Nil{}:
      0n
    case B.BotFx{k, _, _, _} <> t:
      Nat.add(Bool.pick(Nat, String.eq(k, "send"), 1n, 0n), sends(t))
    case _ <> t:
      sends(t)

def step.sends(st: B.Step) -> String:
  match st:
    case B.Step{_, os}:
      Nat.show(sends(os))

def hop(+s: M.State, +bot: String) -> String:
  Nat.show(BT.World.hop(M.State.bots(s), bot))

def bot(+i: String, +name: String) -> List<&2, M.Change>:
  [M.ThreadCreated{"t" ++ i, "", name, M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"b" ++ i, name, "t" ++ i, 3n, "", 100n}]

# #staff: Bub, four more bots here, and Pebble on the linked machine
# "backplane"
def staff() -> M.State:
  M.State.replay(List.concat(&2, M.Change, [bot("1", "Bub"), bot("2", "Calendar"), bot("3", "Email-Whipper"), bot("4", "Household"), bot("5", "Bible-Bot"),
    [M.PeerSet{"p9", "backplane", "http://backplane:3787", False{}, 100n},
     M.RoomSet{"r1", "staff", "b1\nb2\nb3\nb4\nb5\nPebble@backplane", 110n},
     M.RoomSet{"r2", "pair", "b1\nb2", 110n}]]), M.State.empty())

def said(+s: M.State, +now: Nat, +bot: String, +text: String) -> M.State:
  run(s, ask(s, now, "bots.say", "{\"bot\":\"" ++ bot ++ "\",\"text\":\"" ++ text ++ "\"}"))

# a bot's turn ends (and, when `takes`, its next one takes what waited)
def done(takes: Bool, +s: M.State, +th: String, +now: Nat) -> M.State:
  run(s, B.Step{List.append(&2, M.Change, [M.TurnChanged{th, M.Completed{}, now}],
    Bool.pick(List<&2, M.Change>, takes, [M.QueueTaken{th, now}, M.TurnChanged{th, M.Running{}, now}], Nil{})), Nil{}})

def label(+o: MC.McpOut) -> String:
  Bool.pick(String, String.contains(out.reply(o), "held"), "held", step.hop(out.step(o)))

# A and B in "pair" answer each other n times. idle: each ends its turn
# after posting, so the other is at rest when the answer comes; busy: each
# is still in its turn when answered and takes the answer in its next
def talk.next(busy: Bool, +s: M.State, +me: String, +other: String, +now: Nat) -> M.State:
  match busy:
    case True{}:
      done(True{}, run(s, out.step(post(s, now, "t" ++ me, "pair", "and you?"))), "t" ++ other, now)
    case False{}:
      done(False{}, run(s, out.step(post(s, now, "t" ++ me, "pair", "and you?"))), "t" ++ me, now)

def talk(n: Nat, +busy: Bool, +s: M.State, +me: String, +other: String, +now: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+k:
      label(post(s, now, "t" ++ me, "pair", "and you?")) ++ " " ++ talk(k, busy, talk.next(busy, s, me, other, now), other, me, 1n+now)

# the other machine's copy of a post: Pebble answers the room
def pebble(+hop: Nat) -> J.Json:
  json("{\"from\":\"Pebble\",\"tos\":[\"Bub\",\"Calendar\",\"Email-Whipper\",\"Household\",\"Bible-Bot\"],\"members\":[\"Bub\",\"Calendar\",\"Email-Whipper\",\"Household\",\"Bible-Bot\",\"Pebble@\"],\"room\":\"r1\",\"roomName\":\"staff\",\"text\":\"Pebble: here\",\"hop\":" ++ Nat.show(hop) ++ "}")

def posts(+s: M.State, +room: String) -> String:
  Nat.show(List.length(&2, BT.Post, BT.World.posts(M.State.bots(s), room, 50n)))

def main() -> IO(Unit):
  do IO<Unit>:
    # the person asks Bub; Bub asks the room to answer once each
    +s0 : M.State = said(staff(), 1000n, "b1", "check in with the staff")
    +ask : B.Step = out.step(post(s0, 1001n, "t1", "staff", "reply once each"))
    C.Check.str("request hop", step.hop(ask), "1")
    C.Check.str("request wakes four here", step.wakes(ask), "4")
    C.Check.str("request goes to backplane", step.sends(ask), "1")
    +s1 : M.State = run(s0, ask)
    # each answers while the others are still working on theirs
    +a2 : MC.McpOut = post(s1, 1002n, "t2", "staff", "Calendar: here")
    C.Check.str("first answer one deeper", step.hop(out.step(a2)), "2")
    +s2 : M.State = run(s1, out.step(a2))
    C.Check.str("sibling answer does not deepen a busy bot", hop(s2, "b3"), "1")
    +a3 : MC.McpOut = post(s2, 1003n, "t3", "staff", "Email: here")
    +s3 : M.State = run(s2, out.step(a3))
    +a4 : MC.McpOut = post(s3, 1004n, "t4", "staff", "Household: here")
    +s4 : M.State = run(s3, out.step(a4))
    # Pebble's answer from the linked machine, at its hop
    +pb : B.Step = BH.Bots.incoming(s4, 1005n, "p9", pebble(2n))
    C.Check.str("remote answer logged", step.hop(pb), "2")
    C.Check.str("remote answer heard here", step.wakes(pb), "5")
    +s5 : M.State = run(s4, pb)
    C.Check.str("remote answer does not deepen", hop(s5, "b5"), "1")
    +a5 : MC.McpOut = post(s5, 1006n, "t5", "staff", "Bible-Bot: here")
    C.Check.str("every answer one hop deep", step.hop(out.step(a3)) ++ step.hop(out.step(a4)) ++ step.hop(out.step(a5)), "222")
    C.Check.str("no answer held", label(a2) ++ label(a3) ++ label(a4) ++ label(a5), "2222")
    +s6 : M.State = run(s5, out.step(a5))
    C.Check.str("all six in the room", posts(s6, "r1"), "6")
    # Bub, still on the person's turn, sums up at hop 1
    C.Check.str("chief sums up", step.hop(out.step(post(s6, 1007n, "t1", "staff", "thanks all"))), "1")
    # a bot's next turn takes the answers that waited: the lowest hop
    C.Check.str("next turn at lowest wait", hop(done(True{}, s6, "t3", 1008n), "b3"), "2")
    # a back-and-forth between two bots stops at the bound (the held one
    # wakes no one, so the talk is over)
    +p0 : M.State = said(staff(), 2000n, "b1", "talk to Calendar")
    C.Check.str("loop at rest stops", talk(7n, False{}, p0, "1", "2", 2001n), "1 2 3 4 5 6 held ")
    C.Check.str("loop busy stops", talk(7n, True{}, p0, "1", "2", 2001n), "1 2 3 4 5 6 held ")
    # a person starts a new exchange: the next turn is at hop 0 again
    +deep : M.State = run(p0, B.Step{[M.TurnChanged{"t1", M.Completed{}, 2100n}, M.BotWoke{"b1", 6n, 2100n}], Nil{}})
    C.Check.str("deep bot held", label(post(deep, 2101n, "t1", "pair", "more")), "held")
    C.Check.str("person resets", label(post(said(done(False{}, deep, "t1", 2102n), 2103n, "b1", "new question"), 2104n, "t1", "pair", "fresh")), "1")
    # a held post stays in the room for the person, and no bot hears it
    +held : MC.McpOut = post(deep, 2101n, "t1", "pair", "more")
    C.Check.str("held wakes none", step.wakes(out.step(held)), "0")
    C.Check.str("held logged", step.hop(out.step(held)), "7")
    C.Check.str("held marked", yes(String.starts_with(step.text(out.step(held)), "[held: 6 messages between bots")), "yes")
    C.Check.str("held told plainly", yes(String.contains(out.reply(held), "don't send it again or anywhere else")), "yes")
    C.Check.str("held not an error", yes(String.contains(out.reply(held), "\"isError\":true")), "no")
    +dheld : MC.McpOut = mcp(deep, 2101n, "t1", "bot_send", "{\"to\":\"Calendar\",\"text\":\"more\"}")
    C.Check.str("held send wakes none", step.wakes(out.step(dheld)), "0")
    C.Check.str("held send told", yes(String.contains(out.reply(dheld), "no bot was woken")), "yes")
    # a held post in a shared room goes to the other machine, which logs it
    # for the person and wakes no one there
    +sdeep : M.State = run(done(False{}, s1, "t2", 1002n), B.Step{[M.BotWoke{"b2", 6n, 1002n}], Nil{}})
    +sh : B.Step = out.step(post(sdeep, 1002n, "t2", "staff", "too deep"))
    C.Check.str("held shared sent on", step.sends(sh), "1")
    C.Check.str("held shared wakes none", step.wakes(sh), "0")
    C.Check.str("remote held logged", step.hop(BH.Bots.incoming(s4, 1005n, "p9", pebble(7n))), "7")
    C.Check.str("remote held wakes none", step.wakes(BH.Bots.incoming(s4, 1005n, "p9", pebble(7n))), "0")
    C.Check.str("remote hop capped", step.hop(BH.Bots.incoming(s4, 1005n, "p9", pebble(40n))), "7")
    C.Check.str("remote dm held", step.wakes(BH.Bots.incoming(s4, 1005n, "p9", json("{\"from\":\"Pebble\",\"to\":\"Bub\",\"text\":\"yo\",\"hop\":9}"))), "0")
