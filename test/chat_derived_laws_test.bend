import Base
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/server/thin-sidebar.bend as CHATDERIVED

law chat_derived_read:
  for u: U.Ui
  {CHATDERIVED.Sidebar.derived(J.Json.obj([J.KV{"action", J.Str{""}}]), u) == True{} : Bool}

law chat_picture_full_sequence:
  for +u: U.Ui
  for +epoch: String
  for +view: String
  for revision: Nat
  {CHATDERIVED.Sidebar.key.for(False{}, u, epoch, view, revision) == CHATDERIVED.Sidebar.key(u, epoch, view) : String}

def chat_derived_read(u):
  {==}

def chat_picture_full_sequence(u, epoch, view, revision):
  {==}

def main() -> IO(Unit):
  IO.print("ok two chat-derived fence laws")
