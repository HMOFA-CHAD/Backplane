import Base
import ../src/core/board.bend as B
import ../src/core/pcb3d.bend as P
import ../src/core/glb.bend as G
import ../src/core/utf8.bend as U
import ../src/gfx/mesh.bend as M
import ../src/gfx/face.bend as F
import ../src/gfx/draw.bend as D

# Headless renderer entry points for the asymmetric bottom-silk fixture.
def scene.k(items: Maybe<&2, List<&2, B.Item>>, pcb: Maybe<&2, P.Pcb3>) -> F.Scene3:
  match items pcb:
    case Some{xs} Some{p}:
      F.Scene3.board(F.Face3.of(xs, p), 0n)
    case _ _:
      F.Scene3.none()

def scene(+s: String) -> F.Scene3:
  scene.k(B.Board.items(U.Utf8.encode(s)), P.Pcb3.of(U.Utf8.encode(s)))

def face.cam(+c: M.Cam, +bottom: Bool) -> M.Cam:
  M.Cam.face(c, Bool.pick(F32, bottom, F32.pi(), 0.0), Bool.pick(F32, bottom, F32.neg(1.570796), 1.570796))

def board(+s: String, +bottom: Bool) -> List<&2, U32>:
  +sc = scene(s)
  D.Snap.ppm(F.Scene3.render.q(True{}, 1000, 700, 0, 0, 1000, 700, sc, face.cam(F.Scene3.fit(sc), bottom), 10000n, 2105384), 1000, 700)

def glb(bs: List<&2, U32>, +bottom: Bool) -> List<&2, U32>:
  +m = M.Model.of(G.Mesh.tris(G.Glb.parse(bs)))
  D.Snap.ppm(M.Mesh.render(1000, 700, m, face.cam(M.Model.fit(m), bottom), 2105384), 1000, 700)

# Expose parsed stroke geometry: compare footprint text with independently
# authored board text at the same board-space pose, not with the layout code.
def text.k(p: Maybe<&2, P.Pcb3>) -> List<&2, B.Item>:
  match p:
    case Some{P.Pcb3{_, _, xs, _}}:
      xs
    case None{}:
      Nil{}

def text(s: String) -> List<&2, B.Item>:
  text.k(P.Pcb3.of(U.Utf8.encode(s)))
