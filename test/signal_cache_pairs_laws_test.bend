import Base
import ./check.bend as C
import ../src/core/signal.bend as SIGREV

# Signal pair traversal keeps offline activity visibility unchanged.
law signal_pair_offline_work_hidden:
  for +id: String
  for +info: Map<&2, String>
  {SIGREV.Signal.cache.pairs([(id, 1n)], False{}, info) == Map.set(&2, String, info, SIGREV.Signal.key(id), "0") : Map<&2, String>}

law signal_pair_offline_block_kept:
  for +id: String
  for +info: Map<&2, String>
  {SIGREV.Signal.cache.pairs([(id, 3n)], False{}, info) == Map.set(&2, String, info, SIGREV.Signal.key(id), "2") : Map<&2, String>}

def signal_pair_offline_work_hidden(id, info):
  {==}

def signal_pair_offline_block_kept(id, info):
  {==}

def main() -> IO(Unit):
  C.Check.str("two offline pair visibility laws", "proved", "proved")
