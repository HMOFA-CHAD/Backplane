import Base
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/server/thin-actor.bend as CHATSIDE
import ../src/server/thin-sidebar.bend as CHATDERIVED
import ../src/server/thin-sidebar-wire.bend as SWR

# A private rendered sidebar never becomes ordinary wire-picture authority.
law chat_sidebar_image_key:
  for +u: U.Ui
  for +epoch: String
  for +view: String
  for revision: Nat
  {CHATSIDE.SidebarImage.key(False{}, u, epoch, view, revision) == CHATDERIVED.Sidebar.key.revision(u, epoch, view, revision) : String}

law chat_sidebar_image_settings_separate:
  for u: U.Ui
  for epoch: String
  for view: String
  for revision: Nat
  {CHATSIDE.SidebarImage.key(True{}, u, epoch, view, revision) == "" : String}

law chat_sidebar_image_no_wire_authority:
  for key: String
  for node: J.Json
  for +rest: List<&2, CHATSIDE.Memo>
  {SWR.Region.key(CHATSIDE.SidebarImage{key, node} <> rest) == SWR.Region.key(rest) : String}

def chat_sidebar_image_key(u, epoch, view, revision):
  {==}

def chat_sidebar_image_settings_separate(u, epoch, view, revision):
  {==}

def chat_sidebar_image_no_wire_authority(key, node, rest):
  {==}

def main() -> IO(Unit):
  IO.print("ok three sidebar image authority fences")
