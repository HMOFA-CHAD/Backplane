import Base
import ./server.bend as S
import ../core/prompt.bend as Q
import ./plot.bend as PV
import ./review.bend as RVC

# `backplane serve`: the hub and the web server, no window.

def start(args: List<String>) -> IO(Unit):
  do IO<Unit>:
    +user : String <- S.Env.get("HOME", "/tmp")
    +exe : String <- S.Sys.exe_dir.io()
    b : S.Boot <- S.Main.prepare(user, exe)
    S.Main.boot(S.Main.config(user, exe, args, b), True{}, i => IO.pure(Unit, Unit{}))

# (`--plot KIND FILE` is the hub's own board reader, src/server/plot.bend;
# `--review bom OLD NEW` design review's, src/server/review.bend)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    RVC.Rvc.main(args, a2 => PV.Pv.main(a2, a => start(a)))
