import Base
import ../src/core/desktop-browser.bend as DBGUI
import ../src/server/desktop-broker.bend as DBBROKER
import ../src/core/json.bend as J

# Desktop Browser controls never publish private recorder or grant identities.
law desktop_public_row_no_document:
  for +row: J.Json
  for index: Nat
  {J.Json.get(DBBROKER.Broker.public_row(row, index), "documentNonce") == None{} : Maybe<&2, J.Json>}

law desktop_public_row_no_lease:
  for +row: J.Json
  for index: Nat
  {J.Json.get(DBBROKER.Broker.public_row(row, index), "controllerLease") == None{} : Maybe<&2, J.Json>}

law desktop_public_row_no_capture:
  for +row: J.Json
  for index: Nat
  {J.Json.get(DBBROKER.Broker.public_row(row, index), "captureRevision") == None{} : Maybe<&2, J.Json>}

# Lost mandatory interception can retain safety close but no new code authority.
law desktop_lost_guard_no_cdp:
  for +b: DBBROKER.Broker
  for +owner: String
  {J.Json.get_obj(DBBROKER.Broker.target_payload_guard(True{}, b, owner), "cdpMethods") == J.Json.arr(Nil{}) : J.Json}

law desktop_lost_guard_no_reinitialize:
  for +b: DBBROKER.Broker
  for +owner: String
  {J.Json.get_obj(DBBROKER.Broker.target_payload_guard(True{}, b, owner), "initializationMethods") == J.Json.arr(Nil{}) : J.Json}

law desktop_no_generic_file_assignment:
  {DBGUI.Desktop.member(DBGUI.Desktop.methods(), "DOM.setFileInputFiles") == False{} : Bool}

law desktop_no_public_interception_toggle:
  {DBGUI.Desktop.member(DBGUI.Desktop.methods(), "Page.setInterceptFileChooserDialog") == False{} : Bool}

law desktop_unknown_owner_has_no_drive:
  for +drive: String
  {DBGUI.Desktop.drive(False{}, drive) == "none" : String}

def desktop_public_row_no_document(row, index): {==}
def desktop_public_row_no_lease(row, index): {==}
def desktop_public_row_no_capture(row, index): {==}
def desktop_lost_guard_no_cdp(b, owner): {==}
def desktop_lost_guard_no_reinitialize(b, owner): {==}
def desktop_no_generic_file_assignment(): {==}
def desktop_no_public_interception_toggle(): {==}
def desktop_unknown_owner_has_no_drive(drive): {==}
