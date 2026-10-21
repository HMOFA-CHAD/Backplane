import Base
import ../src/core/bot.bend as BOT

# The independent right side is the exact strict expression before this change.
def stop_choice(stop: Bool, +w: String, +hay: String, +text: String) ->
  {BOT.Mem.score.w.k(stop, w, hay, text) == Bool.pick(Nat, stop, 0n,
    Nat.add(Bool.pick(Nat, String.contains(hay, w), 3n, 0n), Bool.pick(Nat, String.contains(text, w), 1n, 0n))) : Nat}:
  match stop:
    case True{}:
      {==}
    case False{}:
      {==}

law strict_equivalence:
  for +w: String
  for +hay: String
  for +text: String
  {BOT.Mem.score.w(w, hay, text) == Bool.pick(Nat, BOT.Room.has(BOT.Words.stop(), w), 0n,
    Nat.add(Bool.pick(Nat, String.contains(hay, w), 3n, 0n), Bool.pick(Nat, String.contains(text, w), 1n, 0n))) : Nat}

def strict_equivalence(w, hay, text):
  stop_choice(BOT.Room.has(BOT.Words.stop(), w), w, hay, text)
