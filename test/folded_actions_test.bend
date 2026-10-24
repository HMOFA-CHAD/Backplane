import Base
import ./check.bend as T
import ../src/core/json.bend as J
import ../src/mobile/folded-actions.bend as F

def js(s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def main() -> IO(Unit):
  do IO<Unit>:
    +row : String = "{\"id\":\"real-row\",\"title\":\"Fresh 日本語\",\"status\":\"complete\",\"children\":3,\"lead\":[{\"action\":\"row-unsettle\"}],\"trail\":[{\"action\":\"row-delete\"}],\"@future\":\"keep\"}"
    +plain : String = "{\"id\":\"real-row\",\"title\":\"Fresh 日本語\",\"status\":\"complete\",\"children\":3,\"lead\":[],\"trail\":[],\"@future\":\"keep\"}"
    T.Check.str("folded rows keep real IDs, titles, status, hierarchy and unknown fields", J.Json.show(F.Folded.rows(False{}, js("[" ++ row ++ "]"))), "[" ++ plain ++ "]")
    T.Check.str("opened rows retain every current action exactly", J.Json.show(F.Folded.rows(True{}, js("[" ++ row ++ "]"))), "[" ++ row ++ "]")
    +project : String = "{\"open\":false,\"archOpen\":true,\"settled\":[" ++ row ++ "],\"archived\":[" ++ row ++ "],\"threads\":[" ++ row ++ "],\"snoozed\":[" ++ row ++ "]}"
    +result : J.Json = F.Folded.project(js(project))
    T.Check.str("closed shelf changes only its hidden actions", J.Json.show(J.Json.get_obj(result, "settled")), "[" ++ plain ++ "]")
    T.Check.str("independently open archive remains complete", J.Json.show(J.Json.get_obj(result, "archived")), "[" ++ row ++ "]")
    T.Check.str("visible live rows are untouched", J.Json.show(J.Json.get_obj(result, "threads")), "[" ++ row ++ "]")
    T.Check.str("visible snoozed rows are untouched", J.Json.show(J.Json.get_obj(result, "snoozed")), "[" ++ row ++ "]")
    +screen : J.Json = F.Folded.screen(js("{\"projects\":[" ++ project ++ "],\"thread\":{\"draft\":\"unsent\"},\"@unknown\":\"preserved\"}"))
    T.Check.str("selected main thread and draft remain fresh", J.Json.show(J.Json.get_obj(screen, "thread")), "{\"draft\":\"unsent\"}")
    T.Check.str("unknown screen fields survive", J.Json.get_str(screen, "@unknown", ""), "preserved")
    T.Check.str("projection is idempotent", J.Json.show(F.Folded.screen(screen)), J.Json.show(screen))
