import Base
import ../src/core/glb.bend as G
import ../src/gfx/mesh.bend as MS
import ../src/core/plot.bend as P
import ../src/core/mech.bend as MC

# GLB files built here and parsed by the production loader, in the emitted
# JavaScript (test/tools/glb_stack.mjs runs each on a small stack, issue
# #362): an empty scene with a large BIN chunk, an indexed mesh of k
# triangles, and the same file cut short.

# Lists, in tail calls (the test's own, so it builds on any loader)
def T.onto(-A: Data, xs: List<&2, A>, acc: List<&2, A>) -> List<&2, A>:
  match xs:
    case Nil{}:
      acc
    case h <> t:
      T.onto(A, t, h <> acc)

def T.rev(-A: Data, xs: List<&2, A>) -> List<&2, A>:
  T.onto(A, xs, Nil{})

def T.len.go(-A: Data, xs: List<&2, A>, n: Nat) -> Nat:
  match xs:
    case Nil{}:
      n
    case _ <> t:
      T.len.go(A, t, Nat.add(n, 1n))

def T.len(-A: Data, xs: List<&2, A>) -> Nat:
  T.len.go(A, xs, 0n)

def T.take.go(n: Nat, xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n xs:
    case 1n+p h <> t:
      T.take.go(p, t, h <> acc)
    case _ _:
      T.rev(U32, acc)

# Bytes are pushed onto a reversed accumulator and reversed once.
def B.w(+w: U32, acc: List<&2, U32>) -> List<&2, U32>:
  U32.and(U32.shrn(w, 24n), 255) <> U32.and(U32.shrn(w, 16n), 255) <> U32.and(U32.shrn(w, 8n), 255) <> U32.and(w, 255) <> acc

def B.zeros(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      B.zeros(p, 0 <> acc)

def B.str(s: String, acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SCon{Chr{c}, t}:
      B.str(t, c <> acc)
    case SNil{}:
      acc

def B.pad(+n: Nat) -> Nat:
  Nat.mod(Nat.sub(4n, Nat.mod(n, 4n)), 4n)

def B.spaces(n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      " " ++ B.spaces(p)

# the BIN chunk (given reversed) onto the reversed head, then all in order
def B.cat(bin: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  T.rev(U32, T.onto(U32, T.rev(U32, bin), acc))

# a whole GLB, reversed: header, JSON chunk (padded with spaces), BIN chunk
def B.glb(+json: String, +bin: List<&2, U32>, +blen: Nat) -> List<&2, U32>:
  +j = json ++ B.spaces(B.pad(String.length(json)))
  +jl = U32.from_nat(String.length(j))
  +bl = U32.from_nat(blen)
  B.cat(bin, B.w(5130562, B.w(bl, B.str(j, B.w(1313821514, B.w(jl,
    B.w((((12 + 8 : U32) + jl : U32) + (8 + bl : U32) : U32), B.w(2, B.w(1179937895, Nil{})))))))))

def Empty.json(+n: Nat) -> String:
  "{\"asset\":{\"version\":\"2.0\"},\"scene\":0,\"scenes\":[{\"nodes\":[]}],\"buffers\":[{\"byteLength\":" ++ Nat.show(n) ++ "}]}"

# an empty scene whose BIN chunk is n zero bytes
def Empty.glb(+n: Nat) -> List<&2, U32>:
  B.glb(Empty.json(n), B.zeros(n, Nil{}), n)

# vertex v at (v, v mod 7, 1); positions then u32 indices 0..v-1, reversed
def Msh.pos(v: Nat, +i: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match v:
    case 0n:
      acc
    case 1n+p:
      Msh.pos(p, Nat.add(i, 1n), B.w(F32.bits(1.0), B.w(F32.bits(F32.from_nat(Nat.mod(i, 7n))), B.w(F32.bits(F32.from_nat(i)), acc))))

def Msh.idx(v: Nat, +i: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match v:
    case 0n:
      acc
    case 1n+p:
      Msh.idx(p, Nat.add(i, 1n), B.w(U32.from_nat(i), acc))

def Msh.json(+v: Nat) -> String:
  +p = Nat.mul(v, 12n)
  +q = Nat.mul(v, 4n)
  "{\"asset\":{\"version\":\"2.0\"},\"scene\":0,\"scenes\":[{\"nodes\":[0]}],\"nodes\":[{\"name\":\"part\",\"mesh\":0}],"
    ++ "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0},\"indices\":1}]}],"
    ++ "\"buffers\":[{\"byteLength\":" ++ Nat.show(Nat.add(p, q)) ++ "}],"
    ++ "\"bufferViews\":[{\"buffer\":0,\"byteOffset\":0,\"byteLength\":" ++ Nat.show(p) ++ "},"
    ++ "{\"buffer\":0,\"byteOffset\":" ++ Nat.show(p) ++ ",\"byteLength\":" ++ Nat.show(q) ++ "}],"
    ++ "\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":" ++ Nat.show(v) ++ ",\"type\":\"VEC3\"},"
    ++ "{\"bufferView\":1,\"componentType\":5125,\"count\":" ++ Nat.show(v) ++ ",\"type\":\"SCALAR\"}]}"

# k triangles, each with its own three vertices
def Msh.glb(+k: Nat) -> List<&2, U32>:
  +v = Nat.mul(k, 3n)
  B.glb(Msh.json(v), Msh.idx(v, 0n, Msh.pos(v, 0n, Nil{})), Nat.add(Nat.mul(v, 12n), Nat.mul(v, 4n)))

# triangle i starts at x = 3i: 1 while every one is in place, else 0
def Order.go(ts: List<&2, G.Tri3>, +i: Nat, ok: Bool) -> Bool:
  match ts:
    case Nil{}:
      ok
    case G.Tri3{+ax, _, _, _, _, _, _, _, _, _} <> t:
      Order.go(t, Nat.add(i, 1n), Bool.and(ok, F32.is_eq(ax, F32.from_nat(Nat.mul(i, 3n)))))

def Yes.n(b: Bool) -> Nat:
  match b:
    case True{}:
      1n
    case False{}:
      0n

# the file's length in bytes
def size_empty(n: Nat) -> Nat:
  T.len(U32, Empty.glb(n))

# parts and triangles of the empty scene: 0
def empty(n: Nat) -> Nat:
  +m = G.Glb.parse(Empty.glb(n))
  Nat.add(T.len(String, G.Mesh.parts(m)), T.len(G.Tri3, G.Mesh.tris(m)))

# the mesh's triangles
def tris(k: Nat) -> Nat:
  T.len(G.Tri3, G.Mesh.tris(G.Glb.parse(Msh.glb(k))))

# 1 when the triangles come out in file order
def order(k: Nat) -> Nat:
  Yes.n(Order.go(G.Mesh.tris(G.Glb.parse(Msh.glb(k))), 0n, True{}))

# the 3D viewer's model of them (its chunk tree and box)
def model(k: Nat) -> Nat:
  MS.Model.size(MS.Model.of(G.Mesh.tris(G.Glb.parse(Msh.glb(k)))))

# the mesh's file cut to its first n bytes: a bounded answer, never a crash
def cut(k: Nat, n: Nat) -> Nat:
  T.len(G.Tri3, G.Mesh.tris(G.Glb.parse(T.take.go(n, Msh.glb(k), Nil{}))))

# not a GLB at all (n zero bytes): no parts
def junk(n: Nat) -> Nat:
  T.len(String, G.Mesh.parts(G.Glb.parse(B.zeros(n, Nil{}))))

# random vertices (a linear congruential sequence, 0..65535 on each axis):
# triangles that span the model, so thinning keeps them
def Rnd.next(+s: U32) -> U32:
  ((s * 1664525 : U32) + 1013904223 : U32)

def Rnd.f(+s: U32) -> F32:
  F32.from_nat(U32.to_nat(U32.shrn(s, 16n)))

def Rnd.pos(v: Nat, +s: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match v:
    case 0n:
      acc
    case 1n+p:
      +a = Rnd.next(s)
      +b = Rnd.next(a)
      +c = Rnd.next(b)
      Rnd.pos(p, c, B.w(F32.bits(Rnd.f(c)), B.w(F32.bits(Rnd.f(b)), B.w(F32.bits(Rnd.f(a)), acc))))

def Rnd.glb(+k: Nat) -> List<&2, U32>:
  +v = Nat.mul(k, 3n)
  B.glb(Msh.json(v), Msh.idx(v, 0n, Rnd.pos(v, 362, Nil{})), Nat.add(Nat.mul(v, 12n), Nat.mul(v, 4n)))

def Rnd.thin(+k: Nat) -> List<&2, G.Tri3>:
  P.Solid.thin(MC.Mech.upright(MC.Mech.metres(G.Mesh.tris(G.Glb.parse(Rnd.glb(k))))))

# what the plot child sends the web, desktop and phones for a STEP's model
# (upright in metres, thinned): the triangles kept
def thin(k: Nat) -> Nat:
  T.len(G.Tri3, Rnd.thin(k))

# and its plot line, in characters
def solid(k: Nat) -> Nat:
  String.length(P.Line.plot(P.Plot.of.solid(P.Solid.of(Rnd.thin(k)))))
