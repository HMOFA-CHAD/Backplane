import Base
import ../core/client.bend as U
import ../core/model.bend as M
import ../core/json.bend as J
import ../web/app.bend as A
import ../web/presentation.bend as P

def Output.limit() -> Nat:
  281474976710655n

def Output.sequence(+u: U.Ui) -> Nat:
  M.Switch.num(U.Ui.info(u, "local.terminal.sequence"), 0n)

# An explicit connection-owned display capability, never key permission.
# Exhaustion returns to the ordinary renderer; no watermark wraps backwards.
def Output.bound(+web: Bool, +u: U.Ui, +owner: String) -> Bool:
  Bool.and(web, Bool.and(String.eq(U.Ui.info(u, "local.terminal.output"), "pane-v1"),
    Bool.and(U.Ui.flag(u, "term"), Bool.and(Bool.not(String.is_empty(owner)),
      Bool.and(String.eq(U.Ui.scratch(u, "@terminal.owner"), owner),
        Bool.and(Nat.is_gt(M.Switch.num(U.Ui.info(u, "local.terminal.incarnation"), 0n), 0n),
          Nat.is_lt(M.Switch.num(U.Ui.info(u, "local.terminal.incarnation"), 0n), Output.limit())))))))

def Output.enabled(+web: Bool, +u: U.Ui, +owner: String) -> Bool:
  Bool.and(Output.bound(web, u, owner), Nat.is_lt(Output.sequence(u), Output.limit()))

def Output.pending(+web: Bool, +u: U.Ui, +owner: String, +written: Nat) -> Bool:
  Bool.and(Output.bound(web, u, owner), Bool.and(Nat.is_le(Output.sequence(u), Output.limit()),
    Bool.and(String.eq(U.Ui.info(u, "local.terminal.pending"), "1"), Nat.is_ge(written, M.Switch.num(U.Ui.info(u, "local.terminal.offered"), 0n)))))

def Output.offered(u: U.Ui, ordinal: Nat) -> U.Ui:
  U.Ui.info_set(U.Ui.info_set(u, "local.terminal.pending", ""), "local.terminal.offered", Nat.show(ordinal))

def Output.next(+u: U.Ui) -> U.Ui:
  U.Ui.info_set(U.Ui.info_set(u, "local.terminal.pending", "1"), "local.terminal.sequence", Nat.show(Nat.add(Output.sequence(u), 1n)))

def Output.message(+u: U.Ui, +owner: String, +generation: String, +epoch: String, +view: String, target: J.Json) -> J.Json:
  J.Json.obj([J.KV{"t", J.Str{"view.terminal"}}, J.KV{"version", J.Json.nat(1n)},
    J.KV{"generation", J.Str{generation}}, J.KV{"epoch", J.Str{epoch}}, J.KV{"viewId", J.Str{view}}, J.KV{"target", target},
    J.KV{"owner", J.Str{owner}}, J.KV{"incarnation", J.Str{U.Ui.info(u, "local.terminal.incarnation")}}, J.KV{"pid", J.Str{U.Ui.info(u, "local.terminal.pid")}}, J.KV{"sequence", J.Str{Nat.show(Output.sequence(u))}},
    J.KV{"pane", P.Node.write(A.terminal_node(u))}])

law output_not_native(+u: U.Ui, +owner: String):
  Output.enabled(False{}, u, owner) == False{}
proof:
  reflexivity
