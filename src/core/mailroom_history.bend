import Base
import ./model.bend as M
import ./mail.bend as ML
import ./mailbody.bend as MB
import ./bot.bend as BT

# Room headers include legacy RoomPosted records whose full text remains in
# World.posts rather than the body journal. Resolve only a requested page.
type RoomPage is Data:
  RoomPage{headers: List<&2, ML.Mail>, more: Bool}

def RoomHistory.take(ms: List<&2, ML.Mail>, n: Nat, acc: List<&2, ML.Mail>) -> RoomPage:
  match ms n:
    case Nil{} _: RoomPage{List.reverse(&2, ML.Mail, acc), False{}}
    case _ 0n: RoomPage{List.reverse(&2, ML.Mail, acc), True{}}
    case h <> t 1n+k: RoomHistory.take(t, k, h <> acc)

def RoomHistory.seek(ms: List<&2, ML.Mail>, +before: String, found: Bool) -> Maybe<&2, List<&2, ML.Mail>>:
  match ms found:
    case xs True{}: Some{xs}
    case Nil{} False{}: None{}
    case +h <> t False{}: RoomHistory.seek(t, before, String.eq(ML.Mail.id(h), before))

def RoomHistory.selected(ms: Maybe<&2, List<&2, ML.Mail>>, +n: Nat) -> Maybe<&2, RoomPage>:
  do Maybe<&2, RoomPage>:
    hs : List<&2, ML.Mail> <- ms
    return RoomHistory.take(hs, n, Nil{})

def RoomHistory.known(known: Bool, hs: List<&2, ML.Mail>, +before: String, n: Nat) -> Maybe<&2, RoomPage>:
  match known:
    case False{}: None{}
    case True{}: RoomHistory.selected(RoomHistory.seek(hs, before, String.is_empty(before)), n)

def RoomHistory.page(+s: M.State, +conv: String, +before: String, +n: Nat) -> Maybe<&2, RoomPage>:
  RoomHistory.known(Bool.not(String.is_empty(ML.Conv.id(ML.Box.conv(M.State.mail(s), conv)))), ML.Box.headers(M.State.mail(s), conv), before, Bool.pick(Nat, Nat.is_gt(n, 200n), 200n, n))

def RoomHistory.wanted(ms: List<&2, ML.Mail>, acc: Map<&2, Bool>) -> Map<&2, Bool>:
  match ms:
    case Nil{}: acc
    case +h <> t: RoomHistory.wanted(t, Map.set(&2, Bool, acc, ML.Mail.id(h), True{}))

type RoomSources is Data:
  RoomSources{wanted: Map<&2, Bool>, left: Nat, texts: Map<&2, String>}

def RoomHistory.source.hit(hit: Bool, +id: String, text: String, wanted: Map<&2, Bool>, left: Nat, texts: Map<&2, String>) -> RoomSources:
  match hit:
    case False{}: RoomSources{wanted, left, texts}
    case True{}: RoomSources{Map.del(&2, Bool, wanted, id), Nat.sub(left, 1n), Map.set(&2, String, texts, id, text)}

def RoomHistory.source.step(p: BT.Post, +room: String, scan: RoomSources) -> RoomSources:
  match p scan:
    case BT.Post{+id, r, _, text, _, _} RoomSources{+wanted, left, texts}:
      RoomHistory.source.hit(Bool.and(String.eq(r, room), ML.Get.has(Map.has(&2, Bool, wanted, id))), id, text, wanted, left, texts)

def RoomHistory.sources.go(ps: List<&2, BT.Post>, +room: String, scan: RoomSources) -> Map<&2, String>:
  match ps scan:
    case _ RoomSources{_, 0n, texts}: texts
    case Nil{} RoomSources{_, _, texts}: texts
    case p <> t st: RoomHistory.sources.go(t, room, RoomHistory.source.step(p, room, st))

def RoomHistory.sources.world(w: BT.World, room: String, +ms: List<&2, ML.Mail>) -> Map<&2, String>:
  match w:
    case BT.World{_, _, ps, _, _, _, _, _, _, _, _, _}:
      RoomHistory.sources.go(ps, room, RoomSources{RoomHistory.wanted(ms, Map.new(&2, Bool)), List.length(&2, ML.Mail, ms), Map.new(&2, String)})

def RoomHistory.sources(+s: M.State, conv: String, ms: List<&2, ML.Mail>) -> Map<&2, String>:
  RoomHistory.sources.world(M.State.bots(s), String.drop(conv, 5n), ms)

def RoomHistory.text.got(r: Map<&2, String> & Maybe<&2, String>) -> Maybe<&2, String>:
  (_, text) = r
  text

def RoomHistory.text(texts: Map<&2, String>, id: String) -> Maybe<&2, String>:
  RoomHistory.text.got(Map.pop(&2, String, texts, id))

def RoomHistory.body(c: ML.Conv, m: ML.Mail, text: String) -> MB.Body:
  MB.Body{c, m, text}
