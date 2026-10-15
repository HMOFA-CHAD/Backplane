import Base
import ./check.bend as C
import ../src/app/main.bend as MA
import ../src/app/nui.bend as N
import ../src/gfx/bitmap.bend as BM
import ../src/gfx/tiles.bend as TI

# The pictures under the UI (main.bend's Pics.over) draw as they did when
# every hit walked the values seen so far: the walk now runs only for image
# hits, and the result is the same image (each picture once, a value seen
# on any earlier hit skipped, as before).
#   bend test/pics_test.bend

# the old Pics.over, the reference
def Old.over(hs: List<&2, N.Hit>, +pics: Map<&2, BM.Bitmap>, +done: List<&2, String>, +ww: U32, +hh: U32, base: Image) -> Image:
  match hs:
    case Nil{}:
      base
    case N.Hit{+x0, +y0, +x1, +y1, +a, +v} <> t:
      Old.over(t, pics, v <> done, ww, hh,
        MA.Pics.over.k(Bool.and(Bool.and(String.eq(a, "img"), U32.is_gt((x1 - x0 : U32), 1)), Bool.not(MA.Pics.had(done, v))), x0, y0, (x1 - x0 : U32), (y1 - y0 : U32), v, pics, ww, hh, base))

def pic(+c: U32) -> BM.Bitmap:
  BM.Bitmap{2, 2, 1n, Pix{c}, 0, 0, 0, 0}

def pics() -> Map<&2, BM.Bitmap>:
  Map.set(&2, BM.Bitmap, Map.set(&2, BM.Bitmap, Map.set(&2, BM.Bitmap, Map.new(&2, BM.Bitmap), "a", pic(16711680)), "b", pic(65280)), "c", pic(255))

def hits() -> List<&2, N.Hit>:
  [N.Hit{0, 0, 30, 20, "row", "x"}, N.Hit{2, 2, 20, 20, "img", "a"}, N.Hit{30, 30, 60, 60, "img", "a"},
   N.Hit{0, 40, 10, 50, "open", "b"}, N.Hit{10, 40, 30, 60, "img", "b"}, N.Hit{40, 0, 41, 10, "img", "c"},
   N.Hit{40, 10, 64, 30, "img", "c"}, N.Hit{0, 0, 64, 64, "side", "c"}]

def same(+hs: List<&2, N.Hit>) -> Bool:
  TI.Eq.image(MA.Pics.over(hs, pics(), Nil{}, 64, 64, Pix{1118481}), Old.over(hs, pics(), Nil{}, 64, 64, Pix{1118481}))

def drew(+hs: List<&2, N.Hit>) -> Bool:
  Bool.not(TI.Eq.image(MA.Pics.over(hs, pics(), Nil{}, 64, 64, Pix{1118481}), Pix{1118481}))

def Q.eq(+a: Bool, +b: Bool) -> Bool:
  Bool.not(Bool.xor(a, b))

def want.all(+w: Bool, +d: List<&2, String>, +v: String) -> Bool:
  Bool.and(Bool.and(Q.eq(MA.Pics.want(True{}, w, d, v), Bool.and(Bool.and(True{}, w), Bool.not(MA.Pics.had(d, v)))),
    Q.eq(MA.Pics.want(False{}, w, d, v), Bool.and(Bool.and(False{}, w), Bool.not(MA.Pics.had(d, v))))), True{})

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("pictures as before", Bool.show(same(hits())), "True")
    C.Check.str("pictures drawn", Bool.show(drew(hits())), "True")
    C.Check.str("no hits", Bool.show(same(Nil{})), "True")
    C.Check.str("want as the old test", Bool.show(Bool.and(Bool.and(want.all(True{}, ["a", "b"], "b"), want.all(True{}, ["a"], "b")),
      Bool.and(want.all(False{}, ["b"], "b"), want.all(False{}, Nil{}, "b")))), "True")
