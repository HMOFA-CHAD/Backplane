import Base
import ./check.bend as C
import ../src/core/order.bend as OR

# The viewer's board picker offers a project's real boards (order.bend's
# Boards.pick): a real project's layout (from a wristband project with 34
# board files: archived revisions, build outputs, an agent's snapshots
# before a reroute, size variants each with its own project file).

def found() -> List<&2, String>:
  ["archive/neurband_electrodes_revB/build/static_L.kicad_pcb",
   "archive/neurband_electrodes_revB/build/static_L.kicad_pro",
   "archive/neurband_electrodes_revB/neurband_electrodes.kicad_pcb",
   "archive/neurband_electrodes_revB/neurband_electrodes.kicad_pro",
   "archive/neurband_main_revA/neurband_main.kicad_pcb",
   "archive/neurband_main_revA/neurband_main.kicad_pro",
   "boards/neurband_c/layout/build/before-stackup.kicad_pcb",
   "boards/neurband_c/neurband_c.kicad_pcb",
   "boards/neurband_c/neurband_c.kicad_pro",
   "boards/neurband_c_flex/neurband_c_flex.kicad_pro",
   "boards/neurband_electrodes/build/static_M.kicad_pcb",
   "boards/neurband_electrodes/build/static_M.kicad_pro",
   "boards/neurband_electrodes/neurband_electrodes.kicad_pcb",
   "boards/neurband_electrodes/neurband_electrodes.kicad_pro",
   "boards/neurband_electrodes/neurband_electrodes_L.kicad_pcb",
   "boards/neurband_electrodes/neurband_electrodes_L.kicad_pro",
   "boards/neurband_main/layout/build/revB-before-native-routing.kicad_pcb",
   "boards/neurband_main/neurband_main.kicad_pcb",
   "boards/neurband_main/neurband_main.kicad_pro"]

def lines(xs: List<&2, String>) -> String:
  String.join(xs, " | ")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("a project's own boards, the default first; no archive, build or snapshot",
      lines(OR.Boards.pick(found(), "boards/neurband_main/neurband_main.kicad_pcb")),
      "boards/neurband_main/neurband_main.kicad_pcb | boards/neurband_c/neurband_c.kicad_pcb | boards/neurband_electrodes/neurband_electrodes.kicad_pcb | boards/neurband_electrodes/neurband_electrodes_L.kicad_pcb")
    C.Check.str("no default: in name order",
      lines(OR.Boards.pick(found(), "")),
      "boards/neurband_c/neurband_c.kicad_pcb | boards/neurband_electrodes/neurband_electrodes.kicad_pcb | boards/neurband_electrodes/neurband_electrodes_L.kicad_pcb | boards/neurband_main/neurband_main.kicad_pcb")
    C.Check.str("boards with no project files: every one outside the copies",
      lines(OR.Boards.pick(["build/a.kicad_pcb", "main.kicad_pcb", "Backups/main-1.kicad_pcb", "power/power.kicad_pcb"], "")),
      "main.kicad_pcb | power/power.kicad_pcb")
    C.Check.str("only copies: all of them rather than none",
      lines(OR.Boards.pick(["build/a.kicad_pcb", "archive/b.kicad_pcb"], "")),
      "build/a.kicad_pcb | archive/b.kicad_pcb")
    C.Check.str("a file named like a folder of copies is no copy",
      lines(OR.Boards.pick(["build.kicad_pcb", "build.kicad_pro"], "")),
      "build.kicad_pcb")
    C.Check.str("a default board in a build folder still leads",
      lines(OR.Boards.pick(found(), "boards/neurband_c/layout/build/before-stackup.kicad_pcb")),
      "boards/neurband_c/layout/build/before-stackup.kicad_pcb | boards/neurband_c/neurband_c.kicad_pcb | boards/neurband_electrodes/neurband_electrodes.kicad_pcb | boards/neurband_electrodes/neurband_electrodes_L.kicad_pcb | boards/neurband_main/neurband_main.kicad_pcb")
    C.Check.str("nothing found: nothing offered", lines(OR.Boards.pick(Nil{}, "")), "")
