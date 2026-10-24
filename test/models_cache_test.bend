import Base
import ../src/core/boot.bend as BT

# Exercise the production cache walkers in the emitted JavaScript runtime.
def one(s: String) -> String:
  BT.Cache.one(s)

def json(s: String) -> String:
  BT.Cache.json(s)

def text(s: String) -> String:
  BT.Cache.text(s)

def cache(ms: String, mt: String) -> String:
  BT.Cache.of(ms, mt)
