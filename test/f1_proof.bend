import Base
import ../src/core/model.bend as M
import ../src/core/far.bend as FR
import ../src/core/json.bend as J
import ../src/core/hot.bend as HOTF
import ../src/core/farsnap.bend as FSNAP

# F1's laws on their own, to time them apart from PROOF.bend (bend f1_proof.bend)
# ---- F1: far mirrors keep only what is live (hot.bend, farsnap.bend) ----
# A snapshot folded shows the same live view as the state it was made from
law far_snap_live:
  {HOTF.Hot.view(FSNAP.Snap.fold(FSNAP.Snap.of.at(FSNAP.Snap.demo(), 2n)), 2n) == HOTF.Hot.view(FSNAP.Snap.demo(), 2n) : List<&2, HOTF.HRow>}

# and a snapshot of that fold is the snapshot again
law far_snap_fix:
  {FSNAP.Snap.of.at(FSNAP.Snap.fold(FSNAP.Snap.of.at(FSNAP.Snap.demo(), 2n)), 2n) == FSNAP.Snap.of.at(FSNAP.Snap.demo(), 2n) : List<&2, M.Change>}

# a mirror compacted from a machine's whole log shows what that log does live
law far_compact_live:
  {HOTF.Hot.view(FR.Fr.items.fold(FR.In.items(FR.In.compact(FR.Fr.demo.in())), M.State.empty()), FSNAP.Snap.k()) == HOTF.Hot.view(FSNAP.Snap.demo(), FSNAP.Snap.k()) : List<&2, HOTF.HRow>}

# compacting keeps the head and the epoch, and leaves no tail
law far_compact_head:
  {FR.In.head(FR.In.compact(FR.Fr.demo.in())) == FR.In.head(FR.Fr.demo.in()) : Nat}

law far_compact_tail:
  {FR.In.tail(FR.In.compact(FR.Fr.demo.in())) == 0n : Nat}

# a mirror's fold, kept as batches come (FR.In.view), is the fold of what
# it holds: Xref and machine_list read it instead of folding again
law far_view_put_threads:
  {FR.Fr.view.threads(FR.In.view(FR.Fr.demo.put())) == FR.Fr.view.threads(FR.Fr.apply(FR.In.items(FR.Fr.demo.put()), "p1", M.State.empty())) : List<&2, M.Thread>}

law far_view_put_projects:
  {FR.Fr.view.projects(FR.In.view(FR.Fr.demo.put())) == FR.Fr.view.projects(FR.Fr.apply(FR.In.items(FR.Fr.demo.put()), "p1", M.State.empty())) : List<&2, M.Project>}

law far_view_compact:
  {FR.Fr.view.threads(FR.In.view(FR.In.compact(FR.Fr.demo.put()))) == FR.Fr.view.threads(FR.Fr.apply(FR.In.items(FR.In.compact(FR.Fr.demo.put())), "p1", M.State.empty())) : List<&2, M.Thread>}

# /far/log v3: a new or changed history gets the snapshot, else the tail
law far_v3_snap_when:
  {[FR.Fr.v3.snap(0n, "e", "e"), FR.Fr.v3.snap(5n, "e", "e"), FR.Fr.v3.snap(5n, "x", "e"), FR.Fr.v3.snap(5n, "", "e")] == [True{}, False{}, True{}, True{}] : List<&2, Bool>}

# the snapshot sent holds only what Fr.shared lets go (all of the demo's)
law far_v3_snap_shared:
  {FR.Fr.snap.shared(FSNAP.Snap.demo()) == FSNAP.Snap.of(FSNAP.Snap.demo()) : List<&2, M.Change>}

# it ends at the log's length, one number each, in one page
law far_v3_snap_numbers:
  {FR.Fr.items.ns(FR.Fr.snap.items([M.ProjectCreated{"p", "a", "/", 1n}, M.ProjectRemoved{"p", 2n}], 5n)) == [4n, 5n] : List<&2, Nat>}

law far_v3_snap_page:
  {FR.Page.where(FR.Fr.snap.page([M.ProjectCreated{"p", "a", "/", 1n}], 9n)) == [9n, 1n, 0n] : List<&2, Nat>}

# a full read says more and ends at its last row; a short one ends at the log
law far_v3_page_full:
  {[FR.Page.where(FR.Fr.v3.page([FR.Line{3n, "{}"}, FR.Line{4n, "{}"}], 2n, 9n, 400000n, True{})), FR.Page.where(FR.Fr.v3.page([FR.Line{3n, "{}"}, FR.Line{4n, "{}"}], 2n, 9n, 400000n, False{}))]
    == [[4n, 2n, 1n], [9n, 2n, 0n]] : List<&2, List<&2, Nat>>}

law far_v3_page_empty:
  {FR.Page.where(FR.Fr.v3.page(Nil{}, 9n, 9n, 400000n, False{})) == [9n, 0n, 0n] : List<&2, Nat>}

# rows of a store answer as lines, and the projects' last numbers
law far_v3_rows:
  {FR.Fr.rows.lines(FR.Fr.rows.of([["12", "0", "5", ""], ["30", "20", "3", ""], ["31", "24", "2", "{w}"]], Nil{}), ["c", "b", "a"])
    == [FR.Line{12n, "a"}, FR.Line{30n, "b"}, FR.Line{31n, "{w}"}] : List<&2, FR.Line>}

# the log is read from the first row's start to the last's end, skipping
# the other lines between them
law far_v3_range:
  {[FR.Fr.rows.from(FR.Fr.rows.of([["12", "0", "5", ""], ["30", "20", "3", ""], ["31", "24", "2", ""]], Nil{})),
    FR.Fr.rows.to(FR.Fr.rows.of([["12", "0", "5", ""], ["30", "20", "3", ""], ["31", "24", "2", ""]], Nil{}), 0n)] == [0n, 26n] : List<&2, Nat>}

law far_v3_skips:
  {FR.Fr.rows.skips(FR.Fr.rows.of([["12", "0", "5", ""], ["30", "20", "3", ""], ["31", "24", "2", ""]], Nil{})) == ["6", "20"] : List<&2, String>}

law far_v3_lasts:
  {[FR.Fr.nat.got(Map.get(Nat, 0n, FR.Fr.lasts.rows([["p1", "7"], ["p2", "30"], ["", "9"]], Map.new(&2, Nat)), "p1")),
    FR.Fr.nat.got(Map.get(Nat, 0n, FR.Fr.lasts.rows([["p1", "7"], ["p2", "30"], ["", "9"]], Map.new(&2, Nat)), "p2"))] == [7n, 30n] : List<&2, Nat>}

# live: settled, archived and deleted threads are not; a task, a bot and a
# running turn keep one
# a pushed batch with a project change is followed by a pull (the catalog)
law far_items_projects:
  {[FR.Fr.items.projects([FR.Item{1n, J.Json.obj([J.KV{"$", J.Str{"MessagePosted"}}])}, FR.Item{2n, J.Json.obj([J.KV{"$", J.Str{"ProjectCreated"}}])}]),
    FR.Fr.items.projects([FR.Item{1n, J.Json.obj([J.KV{"$", J.Str{"MessagePosted"}}])}])] == [True{}, False{}] : List<&2, Bool>}

law hot_demo_threads:
  {[HOTF.Hot.thread.of(FSNAP.Snap.demo(), "t6"), HOTF.Hot.thread.of(FSNAP.Snap.demo(), "t7"), HOTF.Hot.thread.of(FSNAP.Snap.demo(), "t8"),
    HOTF.Hot.thread.of(FSNAP.Snap.demo(), "t10"), HOTF.Hot.thread.of(FSNAP.Snap.demo(), "t2"), HOTF.Hot.thread.of(FSNAP.Snap.demo(), "t4")]
    == [False{}, False{}, False{}, True{}, True{}, True{}] : List<&2, Bool>}

def far_snap_live(): {==}

def far_snap_fix(): {==}

def far_compact_live(): {==}

def far_compact_head(): {==}

def far_compact_tail(): {==}

def hot_demo_threads(): {==}

def far_view_put_threads(): {==}

def far_view_put_projects(): {==}

def far_view_compact(): {==}

def far_v3_snap_when(): {==}

def far_v3_snap_shared(): {==}

def far_v3_snap_numbers(): {==}

def far_v3_snap_page(): {==}

def far_v3_page_full(): {==}

def far_v3_page_empty(): {==}

def far_v3_rows(): {==}

def far_v3_lasts(): {==}

def far_v3_range(): {==}

def far_v3_skips(): {==}

def far_items_projects(): {==}
