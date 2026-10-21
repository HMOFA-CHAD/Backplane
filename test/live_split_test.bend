import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/app/layout.bend as L

def same.line(a: L.TLine, b: L.TLine) -> Bool:
  match a b:
    case L.TLine{ta, ca, ka, pa, wa} L.TLine{tb, cb, kb, pb, wb}:
      Bool.and(Bool.and(String.eq(ta, tb), String.eq(pa, pb)), Bool.and(U32.is_eq(ca, cb), Bool.and(U32.is_eq(ka, kb), U32.is_eq(wa, wb))))

def same(a: List<&2, L.TLine>, b: List<&2, L.TLine>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: Bool.and(same.line(x, y), same(xs, ys))
    case _ _: False{}

def check(+ty: L.Ty, +label: String, +text: String, +before: String, +w: U32) -> IO(Unit):
  +memo = L.TL.live.get(ty, L.TL.live.none(), U.Live.head(before), w)
  C.Check.str(label, Bool.show(same(
    L.TL.live.single(ty, String.is_empty(text), M.PhWorking{}, text, memo, w),
    L.TL.live.m(ty, String.is_empty(text), M.PhWorking{}, text, memo, w))), "True")

def main() -> IO(Unit):
  do IO<Unit>:
    +ty: L.Ty <- L.Ty.load()
    check(ty, "empty phase fallback", "", "", 360)
    check(ty, "live paragraph", "some **bold** and `code` words", "", 360)
    check(ty, "unchanged", "one\n\ntail", "one\n\ntail", 360)
    check(ty, "append", "one\n\ntail grows", "one\n\ntail", 360)
    check(ty, "correction", "one\n\nchanged ending", "one\n\ntail", 360)
    check(ty, "truncation", "one", "one\n\ntail", 360)
    check(ty, "settled paragraph", "one\n\ntail\n\nnext", "one\n\ntail", 360)
    check(ty, "opening fence", "one\n\n```\ncode", "one\n\ntail", 360)
    check(ty, "closed fence", "one\n\n```\ncode\n```\n\nafter", "one\n\n```\ncode", 360)
    check(ty, "blank inside fence", "```\ncode\n\nmore\n```", "", 360)
    check(ty, "different width", "one\n\nwords that wrap in a different column", "one\n\ntail", 180)
    check(ty, "Unicode", "日本語\n\n続き🙂", "日本語\n\n続", 360)
    check(ty, "stale prefix", "new prefix\n\nnew tail", "old prefix\n\nold tail", 620)
