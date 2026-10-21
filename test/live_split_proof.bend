import Base
import ../src/core/model.bend as M
import ../src/app/layout.bend as L

# The original production renderer remains the independent specification.
# Arbitrary typeface, memo, width, phase and text; no append-only premise.
law live_split_exact:
  for +ty: L.Ty
  for empty: Bool
  for +ph: M.Phase
  for +text: String
  for +memo: L.LiveMemo
  for +px: U32
  {L.TL.live.single(ty, empty, ph, text, memo, px) == L.TL.live.m(ty, empty, ph, text, memo, px) : List<&2, L.TLine>}

def live_split_exact(ty, empty, ph, text, memo, px):
  match empty:
    case False{}: {==}
    case True{}: {==}
