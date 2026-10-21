import Base
import ../../src/core/telemetry.bend as T
import ../../src/server/telemetry.bend as TI
import ../../src/server/argv.bend as A

# A telemetry-only worker: no hub, providers, clients, automation or event log.
# Credentials use the normal explicit loopback-test gate, never argv or stdout.
def Probe.start(on: Bool, cfg: List<&2, TI.TmCfg>, home: String, view: T.TmView, now: Nat) -> IO(Unit):
  match on:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        id : String <- TI.Tio.job(cfg, home, view, now, u => IO.pure(Bool, True{}))
        return Unit{}

def Probe.run(xs: List<String>) -> IO(Unit):
  match xs:
    case +home <> +ver <> +day <> +now <> +share <> +asked <> reset <> human <> Nil{}:
      do IO<Unit>:
        +cfg : List<&2, TI.TmCfg> <- TI.Tio.config(False{})
        Probe.start(TI.Tio.can(cfg, T.Tm.num(now)), Bool.pick(List<&2, TI.TmCfg>, Bool.and(String.eq(human, "human"), Bool.and(String.eq(share, "on"), String.eq(asked, "1"))), TI.Tio.human(cfg, T.Tm.num(now)), cfg), home, T.TmView{String.eq(share, "on"), String.eq(asked, "1"), reset, ver, "dev", "linux", "x64", day, T.Tm.num(now)}, T.Tm.num(now))
    case _:
      IO.die(Unit, 2, "expected temporary home, version, UTC day, time, share, asked, reset, human/idle")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, A.Argv.args(), xs => TI.Tio.main(xs, Probe.run))
