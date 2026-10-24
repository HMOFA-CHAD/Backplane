import Base
import ../core/json.bend as J
import ../core/thin-live.bend as TL
import ../core/thin-wire.bend as W

# A complete, private picture for an ordinary web-thread read. Its key is
# the full canonical/request/info key, never a metadata or transport receipt.
# The render clock must be exactly equal; this is not an age-based lease.
type Picture is Data:
  Picture{key: String, clock: Nat, result: J.Json}

def Picture.empty_commands(cs: J.Json) -> Bool:
  match cs:
    case J.Arr{J.End{}}: True{}
    case _: False{}

# Size the retained value only after the cheap eligibility guards pass.
def Picture.bounds(eligible: Bool, +key: String, +res: J.Json) -> Bool:
  match eligible:
    case False{}: False{}
    case True{}: Bool.and(W.Wire.within(key, 32768n), Nat.is_le(J.Json.bytes(res), 262144n))

def Picture.allowed(+web: Bool, +p: J.Json, +res: J.Json, +stream: TL.Stream, +key: String) -> Bool:
  Picture.bounds(Bool.and(web, Bool.and(String.eq(J.Json.get_str(J.Json.get_obj(p, "target"), "kind", ""), "thread"),
    Bool.and(String.is_empty(J.Json.get_str(p, "action", "")),
    Bool.and(Nat.is_eq(TL.Stream.size(stream), 0n),
    Bool.and(J.Json.get_bool(res, "remoteReady", False{}),
    Bool.and(Bool.not(Maybe.is_some(&2, J.Json, J.Json.get(res, "nextTarget"))),
    Picture.empty_commands(J.Json.get_obj(res, "cmds")))))))), key, res)

def Picture.select(valid: Bool, res: J.Json) -> Maybe<&2, J.Json>:
  match valid:
    case False{}: None{}
    case True{}: Some{res}

def Picture.read(+update: Bool, picture: Picture, +key: String, +clock: Nat, +stream: TL.Stream) -> Maybe<&2, J.Json>:
  match picture:
    case Picture{saved, at, res}:
      Picture.select(Bool.and(update, Bool.and(String.eq(saved, key),
        Bool.and(Nat.is_eq(at, clock), Nat.is_eq(TL.Stream.size(stream), 0n)))), res)
