import Base
import ./check.bend as C
import ../src/core/client.bend as U

law select_same_leaves_settings:
  {U.Ui.flag(U.Ui.select.nav(U.Ui.flag_on(U.Ui.select.k(U.Ui.init(0n), "t1"), "settings"), "t1"), "settings") == False{} : Bool}

law select_same_keeps_thread:
  {U.Ui.sel(U.Ui.select.nav(U.Ui.flag_on(U.Ui.select.k(U.Ui.init(0n), "t1"), "settings"), "t1")) == "t1" : String}

def select_same_leaves_settings(): {==}
def select_same_keeps_thread(): {==}

def main() -> IO(Unit):
  C.Check.str("two selection navigation laws", "proved", "proved")
