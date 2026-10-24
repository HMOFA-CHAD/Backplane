import Base

# The server sidebar reads scratch fields, including arbitrary future @ keys.
# Conversation draft bodies still belong to the complete current main Ui.
# This transient input is used only for the private sidebar image identity.
type Input is Data:
  Input{scratch: List<&2, Sigma<&2, &2, String, _ => String>>}

def Input.keep(on: Bool, key: String, value: String, rest: List<&2, Sigma<&2, &2, String, _ => String>>) -> List<&2, Sigma<&2, &2, String, _ => String>>:
  match on:
    case True{}: (key, value) <> rest
    case False{}: rest

def Input.filter(xs: List<&2, Sigma<&2, &2, String, _ => String>>) -> List<&2, Sigma<&2, &2, String, _ => String>>:
  match xs:
    case Nil{}: Nil{}
    case (+key, value) <> rest:
      Input.keep(String.starts_with(key, "@"), key, value, Input.filter(rest))

def Input.of(xs: List<&2, Sigma<&2, &2, String, _ => String>>) -> Input:
  Input{Input.filter(xs)}

def Input.fields(input: Input) -> List<&2, Sigma<&2, &2, String, _ => String>>:
  match input:
    case Input{scratch}: scratch
