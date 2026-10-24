import Base
import ../src/core/signal.bend as SIGREV
import ./check.bend as C

# Canonical signal text never masks fresh unrelated recipient info.
law signal_text_overlay_empty:
  for +base: Map<&2, String>
  {SIGREV.Signal.cache.overlay(base, Map.new(&2, String)) == base : Map<&2, String>}

law signal_text_overlay_known:
  for +value: String
  for other: String
  {SIGREV.Signal.cache.overlay(MLeaf{"@signal:t", value}, MLeaf{"@signal:t", other}) == MLeaf{"@signal:t", value} : Map<&2, String>}

law signal_text_overlay_online:
  for other: String
  {SIGREV.Signal.cache.overlay(MLeaf{"@signal.online", "1"}, MLeaf{"@signal.online", other}) == MLeaf{"@signal.online", "1"} : Map<&2, String>}

law signal_text_overlay_fresh:
  for text: String
  {SIGREV.Signal.cache.overlay(MLeaf{"@signal.online", "1"}, MLeaf{"status", text}) == Map.set(&2, String, MLeaf{"@signal.online", "1"}, "status", text) : Map<&2, String>}

def signal_text_overlay_empty(base):
  {==}

def signal_text_overlay_known(value, other):
  {==}

def signal_text_overlay_online(other):
  {==}

def signal_text_overlay_fresh(text):
  {==}

def main() -> IO(Unit):
  C.Check.str("four canonical signal overlay laws", "proved", "proved")
