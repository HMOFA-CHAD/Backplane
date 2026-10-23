import Base
import ./check.bend as C
import ../src/core/opencode.bend as O
import ../src/core/json.bend as J
import ../src/core/client.bend as U

# opencode's models as the hub reads them (core/opencode.bend's Ocm.*,
# from server.bend's Oc.models.sh lines), through the models info every
# client parses (Info.put) to what Settings lists and says. opencode 2
# dropped `opencode models --verbose`: listed as plain "provider/model"
# lines; a failed or empty listing says why in the CLI line Settings shows,
# never an empty list that worked.

def v2() -> String:
  "openai/gpt-5.6-fast\nxai/grok-4.5\ncerebras/gpt-oss-120b\n!auth\tCerebras\tAPI key\n!auth\tOpenAI\tOAuth\n"

def strs(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      J.Str{x} <> strs(t)

# the hub's models info with opencode's part made from a listing
def info(+version: String, +out: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"claude", J.Json.arr([J.Str{"opus"}])}, J.KV{"opencode", J.Json.arr(strs(O.Ocm.models(out)))},
    J.KV{"about", J.Json.obj([J.KV{"claude", J.Json.obj([J.KV{"cli", J.Str{"2.1"}}])}, J.KV{"opencode", O.Ocm.about(version, out)}])}]))

def nf(+version: String, +out: String) -> Map<&2, String>:
  U.Info.put(Map.new(&2, String), "models", info(version, out))

def oc(+version: String, +out: String) -> String:
  U.Models.of(nf(version, out), "opencode")

def cli(+version: String, +out: String) -> String:
  U.Models.cli(U.Str.get(nf(version, out), "models"), "opencode")

def err(+version: String, +out: String) -> String:
  J.Json.get_str(U.Models.about(oc(version, out), "opencode"), "error", "?")

# a hub models info as it stands, with providers this file knows nothing of
def before() -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse("{\"claude\":[\"opus\"],\"pi\":[\"pi/a\"],\"omp\":[\"omp/b\"],\"opencode\":[\"old/x\"],\"about\":{\"claude\":{\"cli\":\"2.1\"},\"pi\":{\"cli\":\"pi 1\"},\"omp\":{\"cli\":\"omp 2\"},\"opencode\":{\"cli\":\"opencode v2.1.4 · 1 model · no sign-ins\",\"version\":\"opencode v2.1.4\"}}}"), J.Null{})

def after(+out: String) -> J.Json:
  O.Ocm.patch(before(), out)

def strs.of(+j: J.Json, +k: String) -> String:
  J.Json.show(J.Json.get_obj(j, k))

def main() -> IO(Unit):
  +ver = {"opencode v2.1.4" : String}
  +usage = {"DESCRIPTION\n  List all available models\n\nUSAGE\n  opencode models [flags]\n\nFLAGS\n  --standalone       Run with a private server instead of the background service\n" : String}
  +fail = {"!exit 1\tUnrecognized flag: --verbose in command opencode models\n!auth\tOpenAI\tOAuth\n" : String}
  do IO<Unit>:
    C.Check.str("ocm v2 models", String.join(O.Ocm.models(v2()), ","), "openai/gpt-5.6-fast,xai/grok-4.5,cerebras/gpt-oss-120b")
    C.Check.str("ocm v2 settings lists", String.join(U.Models.settings(oc(ver, v2()), "opencode", "", ""), ","), ",openai/gpt-5.6-fast,xai/grok-4.5,cerebras/gpt-oss-120b")
    C.Check.str("ocm v2 cli line", cli(ver, v2()), "opencode v2.1.4 · 3 models · sign-ins: Cerebras (API key), OpenAI (OAuth)")
    C.Check.str("ocm v2 no error", err(ver, v2()), "")
    C.Check.str("ocm picked kept", String.join(U.Models.settings(oc(ver, v2()), "opencode", "", "xai/grok-4.5"), ","), ",openai/gpt-5.6-fast,xai/grok-4.5,cerebras/gpt-oss-120b")
    C.Check.str("ocm failed lists only default", String.join(U.Models.settings(oc(ver, fail), "opencode", "", "xai/grok-4.5"), ","), "")
    C.Check.str("ocm one model", cli(ver, "a/b\n"), "opencode v2.1.4 · 1 model · no sign-ins")
    C.Check.str("ocm usage is not models", Nat.show(List.length(&2, String, O.Ocm.models(usage))), "0")
    C.Check.str("ocm named lines", U.Models.label_of(oc(ver, "a/b\tModel B\n"), "opencode", "a/b"), "Model B")
    C.Check.str("ocm unnamed no label", U.Models.label_of(oc(ver, v2()), "opencode", "xai/grok-4.5"), "")
    C.Check.str("ocm failed cli", cli(ver, fail), "opencode v2.1.4 · could not list models (`opencode models` exited 1: Unrecognized flag: --verbose in command opencode models)")
    C.Check.str("ocm failed error", err(ver, fail), "could not list models (`opencode models` exited 1: Unrecognized flag: --verbose in command opencode models)")
    C.Check.str("ocm failed no models", Nat.show(List.length(&2, String, O.Ocm.models(fail))), "0")
    C.Check.str("ocm timeout", cli(ver, "!exit 124\t\n"), "opencode v2.1.4 · timed out listing models")
    C.Check.str("ocm script failed", cli(ver, "!exit 2\tthe listing script failed\n"), "opencode v2.1.4 · could not list models (`opencode models` exited 2: the listing script failed)")
    C.Check.str("ocm empty", cli(ver, ""), "opencode v2.1.4 · lists no models: sign in with `opencode auth login`")
    C.Check.str("ocm empty error", err(ver, ""), "lists no models: sign in with `opencode auth login`")
    C.Check.str("ocm not installed", cli("", ""), "")
    C.Check.str("ocm not installed no error", err("", ""), "")
    C.Check.str("ocm version kept", J.Json.get_str(O.Ocm.about(ver, fail), "version", ""), "opencode v2.1.4")
    C.Check.str("ocm other providers untouched", String.join(U.Models.list(U.Str.get(nf(ver, fail), "models"), "claude"), ","), "opus")
    C.Check.str("ocm refresh keeps pi", strs.of(after(v2()), "pi"), "[\"pi/a\"]")
    C.Check.str("ocm refresh keeps omp", strs.of(after(v2()), "omp"), "[\"omp/b\"]")
    C.Check.str("ocm refresh keeps claude", strs.of(after(v2()), "claude"), "[\"opus\"]")
    C.Check.str("ocm refresh keeps about pi", J.Json.get_str(J.Json.get_obj(J.Json.get_obj(after(v2()), "about"), "pi"), "cli", ""), "pi 1")
    C.Check.str("ocm refresh keeps about omp", J.Json.get_str(J.Json.get_obj(J.Json.get_obj(after(v2()), "about"), "omp"), "cli", ""), "omp 2")
    C.Check.str("ocm refresh replaces list", strs.of(after(v2()), "opencode"), "[\"openai/gpt-5.6-fast\",\"xai/grok-4.5\",\"cerebras/gpt-oss-120b\"]")
    C.Check.str("ocm refresh replaces about", J.Json.get_str(J.Json.get_obj(J.Json.get_obj(after(v2()), "about"), "opencode"), "cli", ""), "opencode v2.1.4 · 3 models · sign-ins: Cerebras (API key), OpenAI (OAuth)")
    C.Check.str("ocm refresh failed says", J.Json.get_str(J.Json.get_obj(J.Json.get_obj(after(fail), "about"), "opencode"), "cli", ""), "opencode v2.1.4 · could not list models (`opencode models` exited 1: Unrecognized flag: --verbose in command opencode models)")
    C.Check.str("ocp provider auth hint", O.Ocp.hint("Authentication required: provider authentication required"),
      "Authentication required: provider authentication required (the model's provider refused opencode's sign-in, as an expired OAuth sign-in does: run `opencode auth login` for that provider; with no model picked, opencode's configured default agent chose it)")
