import Base
import ../app/render.bend as RN

# `backplane-render MODEL... [--size WxH]`: a part's standard views as PNG
# files (src/app/render.bend), in a binary of its own so neither the hub
# nor the window carries the renderer. `backplane-render --render MODEL`
# is taken too, the form the window binary answered.

def Args.copy(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> Args.copy(t)

def start.k(render: Bool, +xs: List<&2, String>) -> IO(Unit):
  match render:
    case True{}:
      RN.Render.main(xs)
    case False{}:
      RN.Render.main("--render" <> xs)

def start(+xs: List<&2, String>) -> IO(Unit):
  start.k(RN.Render.wants(xs), xs)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(Args.copy(args))
