import Base
import ./check.bend as C
import ./sidebar_region_test.bend as F

def main() -> IO(Unit):
  C.Check.str("Settings category reuses exact server sidebar with normal renderer stamp", F.slot_request(), "yes")
