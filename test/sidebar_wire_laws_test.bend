import Base
import ./check.bend as C
import ../src/server/thin-sidebar-wire.bend as SWR

# A sidebar transport reference needs an actually issued, matching receipt.
law sidebar_wire_unissued:
  {SWR.Region.can_reuse("", "") == False{} : Bool}

law sidebar_wire_wrong_ack:
  {SWR.Region.can_reuse("7", "8") == False{} : Bool}

def sidebar_wire_unissued(): {==}
def sidebar_wire_wrong_ack(): {==}

def main() -> IO(Unit):
  C.Check.str("two new sidebar transport laws", "proved", "proved")
