import Base
import ./check.bend as C
import ../src/core/bot.bend as BT

# Keep the original strict expression as the test oracle, independent of the helper.
def strict_word(+w: String, +hay: String, +text: String) -> Nat:
  Bool.pick(Nat, BT.Room.has(BT.Words.stop(), w), 0n,
    Nat.add(Bool.pick(Nat, String.contains(hay, w), 3n, 0n), Bool.pick(Nat, String.contains(text, w), 1n, 0n)))

def texts() -> List<&2, String>:
  ["", "the invoice cat", "theory and THE", "東京 猫", "straße invoice", "invoice invoice cat"]

def bodies(ts: List<&2, String>, +w: String, +hay: String) -> IO(Unit):
  match ts:
    case Nil{}: IO.pure(Unit, Unit{})
    case +text <> t:
      do IO<Unit>:
        C.Check.str("score " ++ w ++ " / " ++ hay ++ " / " ++ text,
          Nat.show(BT.Mem.score.w(w, hay, text)), Nat.show(strict_word(w, hay, text)))
        bodies(t, w, hay)

def hays(hs: List<&2, String>, +w: String) -> IO(Unit):
  match hs:
    case Nil{}: IO.pure(Unit, Unit{})
    case +hay <> t:
      do IO<Unit>:
        bodies(texts(), w, hay)
        hays(t, w)

def words(ws: List<&2, String>) -> IO(Unit):
  match ws:
    case Nil{}: IO.pure(Unit, Unit{})
    case +w <> t:
      do IO<Unit>:
        hays(texts(), w)
        words(t)

def strict_sum(qs: List<&2, String>, +hay: String, +text: String) -> Nat:
  match qs:
    case Nil{}: 0n
    case q <> t: Nat.add(strict_word(q, hay, text), strict_sum(t, hay, text))

def strict_hits(ms: List<&2, BT.Mem>, +qs: List<&2, String>) -> List<&2, BT.Hit>:
  match ms:
    case Nil{}: Nil{}
    case +m <> t:
      BT.Hit.scored.k(strict_sum(qs, String.to_lower(BT.Mem.hay(m)), String.to_lower(BT.Mem.text(m))), m, strict_hits(t, qs))

def corpus() -> List<&2, BT.Mem>:
  [BT.Mem{"b", "invoice", "fact", "cat invoice", "billing", 1n, 1n},
   BT.Mem{"b", "billing", "fact", "Invoice invoice", "", 2n, 2n},
   BT.Mem{"b", "cat", "fact", "theory and THE", "invoice", 3n, 3n},
   BT.Mem{"b", "東京", "fact", "東京 猫", "", 4n, 4n},
   BT.Mem{"b", "tie-a", "fact", "cat", "", 5n, 5n},
   BT.Mem{"b", "tie-b", "fact", "cat", "", 6n, 6n}]

def keys(ms: List<&2, BT.Mem>) -> String:
  match ms:
    case Nil{}: ""
    case m <> t: BT.Mem.key(m) ++ "|" ++ keys(t)

def rank(qs: List<&2, String>) -> IO(Unit):
  match qs:
    case Nil{}: IO.pure(Unit, Unit{})
    case +q <> t:
      do IO<Unit>:
        C.Check.str("ranking " ++ q, keys(BT.Mem.recall(corpus(), q, 6n)),
          keys(BT.Hit.mems(List.take(&2, BT.Hit, List.sort(~BT.Hit, ~BT.Hit.before, strict_hits(corpus(), BT.Words.of(q))), 6n))))
        rank(t)

def main() -> IO(Unit):
  do IO<Unit>:
    words(List.append(&2, String, BT.Words.stop(), ["", "invoice", "invoice invoice", "東京", "straße", "theory", "THE", "cat"]))
    C.Check.str("stop match in both stays zero", Nat.show(BT.Mem.score.w("the", "the", "the")), "0")
    C.Check.str("nonstop match in both stays four", Nat.show(BT.Mem.score.w("invoice", "invoice", "invoice")), "4")
    C.Check.str("nonstop hay stays three", Nat.show(BT.Mem.score.w("invoice", "invoice", "cat")), "3")
    C.Check.str("nonstop body stays one", Nat.show(BT.Mem.score.w("invoice", "cat", "invoice")), "1")
    C.Check.str("duplicate query words keep weight", Nat.show(BT.Mem.score.go(BT.Words.of("invoice invoice"), "invoice", "invoice")), "8")
    rank(["", "the and for", "invoice", "invoice invoice cat", "cat invoice", "CAT", "東京", "theory", "cat cat cat"])
