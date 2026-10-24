import Base
import ../src/core/client.bend as U
import ../src/core/json.bend as J

law model_labels_given:
  for +info: String
  for +provider: String
  for +model: String
  {U.Models.label.given(U.Models.labels(info, provider), model) == J.Json.get_str(J.Json.get_obj(U.Models.about(info, provider), "labels"), Bool.pick(String, String.is_empty(model), "default", model), "") : String}

def model_labels_given(info, provider, model):
  {==}

def main() -> IO(Unit):
  IO.print("ok model_labels_given")
