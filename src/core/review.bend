import Base
import ./json.bend as J
import ./model.bend as M

# Design review comments, pinned to a place in a design. Pure.
#
# A comment is a few Acts of tone "review" in the thread's log (filed under
# "@review:<thread>", M.State.reviews): the Act's kind is the op's name, its
# summary the op as JSON. Ops: add (a root, or a reply when it has a parent),
# resolve, reopen, edit, drop. Folding the ops oldest first gives the
# comments; a later op wins and an op on an unknown id is ignored.

# where a comment sits: a file (relative to the repo top), the commit it was
# made on ("" for the working copy), "board" or "schematic", a layer name
# ("" for a schematic), mm in the file's own coordinates, and the key of the
# item under the pin ("" for none)
type Anchor is Data:
  Anchor{file: String, commit: String, kind: String, layer: String, x: F32, y: F32, item: String}

# resolved is kept on roots; a reply has a parent (a root's id)
type Comment is Data:
  Comment{id: String, anchor: Anchor, text: String, by: String, at: Nat, parent: String, resolved: Bool}

type Op is Data:
  Add{c: Comment}
  Resolve{id: String, by: String}
  Reopen{id: String, by: String}
  Edit{id: String, text: String}
  Drop{id: String}

# what a viewer draws for a root: its place and state, replies counted
type Pin is Data:
  Pin{id: String, x: F32, y: F32, layer: String, item: String, resolved: Bool, count: Nat}

def Review.tone() -> String:
  "review"

def Review.k.add() -> String:
  "add"

def Review.k.resolve() -> String:
  "resolve"

def Review.k.reopen() -> String:
  "reopen"

def Review.k.edit() -> String:
  "edit"

def Review.k.drop() -> String:
  "drop"

# a deterministic id for a thread's nth comment
def Review.new_id(+th: String, +n: Nat) -> String:
  "rv:" ++ th ++ ":" ++ Nat.show(n)

# Encoding
# --------

def Rv.num(+v: F32) -> J.Json:
  J.Num{F32.show(v)}

def Rv.anchor.json(a: Anchor) -> J.Json:
  match a:
    case Anchor{+f, +c, +k, +l, +x, +y, +i}:
      J.Json.obj([J.KV{"file", J.Json.str(f)}, J.KV{"commit", J.Json.str(c)}, J.KV{"kind", J.Json.str(k)},
        J.KV{"layer", J.Json.str(l)}, J.KV{"x", Rv.num(x)}, J.KV{"y", Rv.num(y)}, J.KV{"item", J.Json.str(i)}])

def Review.op.add(+id: String, +a: Anchor, +text: String, +by: String, +parent: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"a", Rv.anchor.json(a)}, J.KV{"text", J.Json.str(text)},
    J.KV{"by", J.Json.str(by)}, J.KV{"parent", J.Json.str(parent)}]))

def Review.op.resolve(+id: String, +by: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"by", J.Json.str(by)}]))

def Review.op.reopen(+id: String, +by: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"by", J.Json.str(by)}]))

def Review.op.edit(+id: String, +text: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"text", J.Json.str(text)}]))

def Review.op.drop(+id: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"id", J.Json.str(id)}]))

# Decoding
# --------

def Rv.f32(+o: J.Json, +key: String) -> F32:
  Maybe.default(&2, F32, F32.read(J.Json.as_raw(J.Json.get(o, key), "")), 0.0)

def Rv.anchor.read(+o: J.Json) -> Anchor:
  Anchor{J.Json.get_str(o, "file", ""), J.Json.get_str(o, "commit", ""), J.Json.get_str(o, "kind", ""),
    J.Json.get_str(o, "layer", ""), Rv.f32(o, "x"), Rv.f32(o, "y"), J.Json.get_str(o, "item", "")}

def Rv.add.read(+o: J.Json, +at: Nat) -> Op:
  Add{Comment{J.Json.get_str(o, "id", ""), Rv.anchor.read(J.Json.get_obj(o, "a")), J.Json.get_str(o, "text", ""),
    J.Json.get_str(o, "by", ""), at, J.Json.get_str(o, "parent", ""), False{}}}

def Rv.read.kind5(dr: Bool, +o: J.Json) -> Maybe<&2, Op>:
  match dr:
    case True{}:
      Some{Drop{J.Json.get_str(o, "id", "")}}
    case False{}:
      None{}

def Rv.read.kind4(ed: Bool, dr: Bool, +o: J.Json) -> Maybe<&2, Op>:
  match ed:
    case True{}:
      Some{Edit{J.Json.get_str(o, "id", ""), J.Json.get_str(o, "text", "")}}
    case False{}:
      Rv.read.kind5(dr, o)

def Rv.read.kind3(ro: Bool, ed: Bool, dr: Bool, +o: J.Json) -> Maybe<&2, Op>:
  match ro:
    case True{}:
      Some{Reopen{J.Json.get_str(o, "id", ""), J.Json.get_str(o, "by", "")}}
    case False{}:
      Rv.read.kind4(ed, dr, o)

def Rv.read.kind2(rs: Bool, ro: Bool, ed: Bool, dr: Bool, +o: J.Json) -> Maybe<&2, Op>:
  match rs:
    case True{}:
      Some{Resolve{J.Json.get_str(o, "id", ""), J.Json.get_str(o, "by", "")}}
    case False{}:
      Rv.read.kind3(ro, ed, dr, o)

def Rv.read.kind(a: Bool, rs: Bool, ro: Bool, ed: Bool, dr: Bool, +o: J.Json, +at: Nat) -> Maybe<&2, Op>:
  match a:
    case True{}:
      Some{Rv.add.read(o, at)}
    case False{}:
      Rv.read.kind2(rs, ro, ed, dr, o)

def Rv.read.k(+kind: String, +o: J.Json, +at: Nat) -> Maybe<&2, Op>:
  Rv.read.kind(String.eq(kind, Review.k.add()), String.eq(kind, Review.k.resolve()), String.eq(kind, Review.k.reopen()),
    String.eq(kind, Review.k.edit()), String.eq(kind, Review.k.drop()), o, at)

def Rv.parsed(m: Maybe<&2, J.Json>, +kind: String, +at: Nat) -> Maybe<&2, Op>:
  match m:
    case Some{+o}:
      Rv.read.k(kind, o, at)
    case None{}:
      None{}

# an op from its kind and JSON summary (the id must be there)
def Review.op.of(+kind: String, +summary: String, +at: Nat) -> Maybe<&2, Op>:
  Rv.parsed(J.Json.parse(summary), kind, at)

def Rv.of.k(rv: Bool, +kind: String, +summary: String, +at: Nat) -> Maybe<&2, Op>:
  match rv:
    case True{}:
      Review.op.of(kind, summary, at)
    case False{}:
      None{}

# a review Act read back (None for any other entry)
def Review.of(e: M.Entry) -> Maybe<&2, Op>:
  match e:
    case M.Act{_, _, +tone, +kind, +summary, +at}:
      Rv.of.k(String.eq(tone, Review.tone()), kind, summary, at)
    case M.Msg{_, _, _, _, _}:
      None{}

def Rv.put(m: Maybe<&2, Op>, acc: List<&2, Op>) -> List<&2, Op>:
  match m:
    case Some{o}:
      o <> acc
    case None{}:
      acc

# entries newest first (as M.State.reviews gives) -> ops oldest first
def Review.ops(es: List<&2, M.Entry>, acc: List<&2, Op>) -> List<&2, Op>:
  match es:
    case Nil{}:
      acc
    case e <> t:
      Review.ops(t, Rv.put(Review.of(e), acc))

# Folding
# -------

def Rv.id(+c: Comment) -> String:
  match c:
    case Comment{+i, _, _, _, _, _, _}:
      i

def Rv.parent(+c: Comment) -> String:
  match c:
    case Comment{_, _, _, _, _, +p, _}:
      p

def Rv.anchor(+c: Comment) -> Anchor:
  match c:
    case Comment{_, +a, _, _, _, _, _}:
      a

def Rv.resolved(+c: Comment) -> Bool:
  match c:
    case Comment{_, _, _, _, _, _, +r}:
      r

def Rv.root(+c: Comment) -> Bool:
  String.is_empty(Rv.parent(c))

def Rv.has.go(cs: List<&2, Comment>, found: Bool, +id: String) -> Bool:
  match cs:
    case Nil{}:
      found
    case +c <> t:
      Rv.has.go(t, Bool.or(found, String.eq(Rv.id(c), id)), id)

def Rv.has(cs: List<&2, Comment>, +id: String) -> Bool:
  Rv.has.go(cs, False{}, id)

def Rv.set.res(+c: Comment, +r: Bool) -> Comment:
  match c:
    case Comment{+i, +a, +t, +b, +at, +p, _}:
      Comment{i, a, t, b, at, p, r}

def Rv.set.text(+c: Comment, +tx: String) -> Comment:
  match c:
    case Comment{+i, +a, _, +b, +at, +p, +r}:
      Comment{i, a, tx, b, at, p, r}

def Rv.res.pick(hit: Bool, +c: Comment, +r: Bool) -> Comment:
  match hit:
    case True{}:
      Rv.set.res(c, r)
    case False{}:
      c

def Rv.text.pick(hit: Bool, +c: Comment, +tx: String) -> Comment:
  match hit:
    case True{}:
      Rv.set.text(c, tx)
    case False{}:
      c

def Rv.resolve(cs: List<&2, Comment>, +id: String, +r: Bool) -> List<&2, Comment>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Rv.res.pick(String.eq(Rv.id(c), id), c, r) <> Rv.resolve(t, id, r)

def Rv.retext(cs: List<&2, Comment>, +id: String, +tx: String) -> List<&2, Comment>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Rv.text.pick(String.eq(Rv.id(c), id), c, tx) <> Rv.retext(t, id, tx)

# a comment without the one dropped and the replies to it
def Rv.drop.keep(gone: Bool, +c: Comment, rest: List<&2, Comment>) -> List<&2, Comment>:
  match gone:
    case True{}:
      rest
    case False{}:
      c <> rest

def Rv.drop(cs: List<&2, Comment>, +id: String) -> List<&2, Comment>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Rv.drop.keep(Bool.or(String.eq(Rv.id(c), id), String.eq(Rv.parent(c), id)), c, Rv.drop(t, id))

# an add: ignored when its id exists, or it replies to an unknown comment
# (or to a reply: a reply's parent is a root)
def Rv.root.has.go(cs: List<&2, Comment>, found: Bool, +id: String) -> Bool:
  match cs:
    case Nil{}:
      found
    case +c <> t:
      Rv.root.has.go(t, Bool.or(found, Bool.and(String.eq(Rv.id(c), id), Rv.root(c))), id)

def Rv.root.has(cs: List<&2, Comment>, +id: String) -> Bool:
  Rv.root.has.go(cs, False{}, id)

def Rv.add.parent.k(none: Bool, +p: String, cs: List<&2, Comment>) -> Bool:
  match none:
    case True{}:
      True{}
    case False{}:
      Rv.root.has(cs, p)

def Rv.add.parent(+p: String, cs: List<&2, Comment>) -> Bool:
  Rv.add.parent.k(String.is_empty(p), p, cs)

def Rv.add.ok(+c: Comment, +cs: List<&2, Comment>) -> Bool:
  Bool.and(Bool.and(Bool.not(String.is_empty(Rv.id(c))), Bool.not(Rv.has(cs, Rv.id(c)))), Rv.add.parent(Rv.parent(c), cs))

# acc is oldest first; adds go on the end
def Rv.add(ok: Bool, +c: Comment, cs: List<&2, Comment>) -> List<&2, Comment>:
  match ok:
    case True{}:
      List.append(&2, Comment, cs, [c])
    case False{}:
      cs

def Rv.step(+cs: List<&2, Comment>, o: Op) -> List<&2, Comment>:
  match o:
    case Add{+c}:
      Rv.add(Rv.add.ok(c, cs), c, cs)
    case Resolve{+id, _}:
      Rv.resolve(cs, id, True{})
    case Reopen{+id, _}:
      Rv.resolve(cs, id, False{})
    case Edit{+id, +tx}:
      Rv.retext(cs, id, tx)
    case Drop{+id}:
      Rv.drop(cs, id)

def Rv.fold.go(os: List<&2, Op>, cs: List<&2, Comment>) -> List<&2, Comment>:
  match os:
    case Nil{}:
      cs
    case o <> t:
      Rv.fold.go(t, Rv.step(cs, o))

# ops oldest first -> the comments, in the order they were made
def Review.fold(os: List<&2, Op>) -> List<&2, Comment>:
  Rv.fold.go(os, Nil{})

# a thread's comments
def Review.of_state(+s: M.State, +th: String) -> List<&2, Comment>:
  Review.fold(Review.ops(M.State.reviews(s, th), Nil{}))

# Queries
# -------

def Rv.roots.k(root: Bool, +c: Comment, rest: List<&2, Comment>) -> List<&2, Comment>:
  match root:
    case True{}:
      c <> rest
    case False{}:
      rest

def Review.roots(cs: List<&2, Comment>) -> List<&2, Comment>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Rv.roots.k(Rv.root(c), c, Review.roots(t))

def Review.open(cs: List<&2, Comment>) -> List<&2, Comment>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Rv.roots.k(Bool.and(Rv.root(c), Bool.not(Rv.resolved(c))), c, Review.open(t))

def Review.resolved(cs: List<&2, Comment>) -> List<&2, Comment>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Rv.roots.k(Bool.and(Rv.root(c), Rv.resolved(c)), c, Review.resolved(t))

def Review.count.open(cs: List<&2, Comment>) -> Nat:
  List.length(&2, Comment, Review.open(cs))

def Review.replies(cs: List<&2, Comment>, +id: String) -> List<&2, Comment>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Rv.roots.k(String.eq(Rv.parent(c), id), c, Review.replies(t, id))

def Rv.file(+c: Comment) -> String:
  match c:
    case Comment{_, +a, _, _, _, _, _}:
      match a:
        case Anchor{+f, _, _, _, _, _, _}:
          f

def Rv.layer(+c: Comment) -> String:
  match c:
    case Comment{_, +a, _, _, _, _, _}:
      match a:
        case Anchor{_, _, _, +l, _, _, _}:
          l

def Rv.item(+c: Comment) -> String:
  match c:
    case Comment{_, +a, _, _, _, _, _}:
      match a:
        case Anchor{_, _, _, _, _, _, +i}:
          i

def Rv.commit(+c: Comment) -> String:
  match c:
    case Comment{_, +a, _, _, _, _, _}:
      match a:
        case Anchor{_, +m, _, _, _, _, _}:
          m

# the roots on a file
def Review.for_file(cs: List<&2, Comment>, +rel: String) -> List<&2, Comment>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Rv.roots.k(Bool.and(Rv.root(c), String.eq(Rv.file(c), rel)), c, Review.for_file(t, rel))

def Rv.pin.k(cs: List<&2, Comment>, +id: String, a: Anchor, +r: Bool) -> Pin:
  match a:
    case Anchor{_, _, _, +l, +x, +y, +i}:
      Pin{id, x, y, l, i, r, List.length(&2, Comment, Review.replies(cs, id))}

def Rv.pin(cs: List<&2, Comment>, +c: Comment) -> Pin:
  match c:
    case Comment{+id, +a, _, _, _, _, +r}:
      Rv.pin.k(cs, id, a, r)

def Rv.pins.go(+all: List<&2, Comment>, rs: List<&2, Comment>) -> List<&2, Pin>:
  match rs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Rv.pin(all, c) <> Rv.pins.go(all, t)

# a layer filter "" shows every pin; else the pins on that layer, and the
# ones with no layer (a schematic's)
def Rv.layer.ok(+want: String, +l: String) -> Bool:
  Bool.or(String.is_empty(want), Bool.or(String.is_empty(l), String.eq(want, l)))

def Rv.on_layer(rs: List<&2, Comment>, +want: String) -> List<&2, Comment>:
  match rs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Rv.roots.k(Rv.layer.ok(want, Rv.layer(c)), c, Rv.on_layer(t, want))

# what a viewer showing `rel` draws, for one layer ("" for all)
def Review.pins(+cs: List<&2, Comment>, +rel: String, +layer: String) -> List<&2, Pin>:
  Rv.pins.go(cs, Rv.on_layer(Review.for_file(cs, rel), layer))

def Review.pin.id(p: Pin) -> String:
  match p:
    case Pin{+i, _, _, _, _, _, _}:
      i

def Review.pin.count(p: Pin) -> Nat:
  match p:
    case Pin{_, _, _, _, _, _, +n}:
      n

def Review.pin.resolved(p: Pin) -> Bool:
  match p:
    case Pin{_, _, _, _, _, +r, _}:
      r

# Version link
# ------------

def Rv.in.go(keys: List<&2, String>, found: Bool, +k: String) -> Bool:
  match keys:
    case Nil{}:
      found
    case +h <> t:
      Rv.in.go(t, Bool.or(found, String.eq(h, k)), k)

def Rv.in(keys: List<&2, String>, +k: String) -> Bool:
  Rv.in.go(keys, False{}, k)

def Rv.moved.k(has: Bool, +item: String, keys: List<&2, String>) -> Bool:
  match has:
    case True{}:
      Rv.in(keys, item)
    case False{}:
      False{}

# True when the item the pin was put on is among `changed` (the keys
# Hist.mark marked removed or changed between its commit and the version
# shown)
def Review.moved(+c: Comment, changed: List<&2, String>) -> Bool:
  Rv.moved.k(Bool.not(String.is_empty(Rv.item(c))), Rv.item(c), changed)

# Text for agents and people
# --------------------------

def Rv.mm(+v: F32) -> String:
  F32.show(F32.div(F32.round(F32.mul(v, 100.0)), 100.0))

def Rv.sep.k(none: Bool, +l: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      ", " ++ l

def Rv.sep(+l: String) -> String:
  Rv.sep.k(String.is_empty(l), l)

def Rv.where.k(a: Anchor) -> String:
  match a:
    case Anchor{_, _, _, +l, +x, +y, _}:
      "(" ++ Rv.mm(x) ++ ", " ++ Rv.mm(y) ++ " mm" ++ Rv.sep(l) ++ ")"

# "(x, y mm, layer)" or "(x, y mm)"
def Rv.where(+c: Comment) -> String:
  match c:
    case Comment{_, +a, _, _, _, _, _}:
      Rv.where.k(a)

def Rv.text(+c: Comment) -> String:
  match c:
    case Comment{_, _, +t, _, _, _, _}:
      t

def Rv.by(+c: Comment) -> String:
  match c:
    case Comment{_, _, _, +b, _, _, _}:
      b

def Rv.by.note.k(none: Bool, +b: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      " _(" ++ b ++ ")_"

def Rv.by.note(+c: Comment) -> String:
  Rv.by.note.k(String.is_empty(Rv.by(c)), Rv.by(c))

def Rv.rep.lines(rs: List<&2, Comment>, +pre: String) -> String:
  match rs:
    case Nil{}:
      ""
    case +r <> t:
      pre ++ Rv.text(r) ++ Rv.by.note(r) ++ "\n" ++ Rv.rep.lines(t, pre)

def Rv.prompt.one(all: List<&2, Comment>, +c: Comment) -> String:
  "- " ++ Rv.id(c) ++ " " ++ Rv.file(c) ++ " " ++ Rv.where(c) ++ ": " ++ Rv.text(c) ++ Rv.by.note(c) ++ "\n"
    ++ Rv.rep.lines(Review.replies(all, Rv.id(c)), "    reply: ")

def Rv.prompt.go(+all: List<&2, Comment>, rs: List<&2, Comment>) -> String:
  match rs:
    case Nil{}:
      ""
    case +c <> t:
      Rv.prompt.one(all, c) ++ Rv.prompt.go(all, t)

def Rv.prompt.k(none: Bool, +body: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      "<review_comments>\nOpen comments on the design (id, file, place, text). Answer or fix them, then reply or resolve with review_comment.\n" ++ body ++ "</review_comments>"

# the open roots as a block for the agent's prompt, "" when none
def Review.prompt(+cs: List<&2, Comment>) -> String:
  Rv.prompt.k(List.is_empty(&2, Comment, Review.open(cs)), Rv.prompt.go(cs, Review.open(cs)))

def Rv.files.add(has: Bool, +f: String, seen: List<&2, String>) -> List<&2, String>:
  match has:
    case True{}:
      seen
    case False{}:
      List.append(&2, String, seen, [f])

# markdown, grouped by file in order of first appearance
def Rv.files.go(rs: List<&2, Comment>, +seen: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}:
      seen
    case +c <> t:
      Rv.files.go(t, Rv.files.add(Rv.in(seen, Rv.file(c)), Rv.file(c), seen))

def Rv.md.one(all: List<&2, Comment>, +c: Comment) -> String:
  "- **" ++ Rv.file(c) ++ "** " ++ Rv.where(c) ++ " — " ++ Rv.text(c) ++ Rv.by.note(c) ++ "\n"
    ++ Rv.rep.lines(Review.replies(all, Rv.id(c)), "  - ")

def Rv.md.group(+all: List<&2, Comment>, rs: List<&2, Comment>) -> String:
  match rs:
    case Nil{}:
      ""
    case +c <> t:
      Rv.md.one(all, c) ++ Rv.md.group(all, t)

# the roots of one file, grouped by file in order of first appearance
def Rv.md.files(+all: List<&2, Comment>, +rs: List<&2, Comment>, fs: List<&2, String>) -> String:
  match fs:
    case Nil{}:
      ""
    case +f <> t:
      Rv.md.group(all, Review.for_file(rs, f)) ++ Rv.md.files(all, rs, t)

def Rv.md.part(+all: List<&2, Comment>, +rs: List<&2, Comment>) -> String:
  Rv.md.files(all, rs, Rv.files.go(rs, Nil{}))

def Rv.md.resolved(none: Bool, +body: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      "\nResolved\n\n" ++ body

# a list of the open comments, then "Resolved" and the rest, for a PR
# comment or an export; "" when there are none
def Review.md(+cs: List<&2, Comment>) -> String:
  Rv.md.part(cs, Review.open(cs)) ++ Rv.md.resolved(List.is_empty(&2, Comment, Review.resolved(cs)), Rv.md.part(cs, Review.resolved(cs)))

def Rv.line(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      ""
    case +h <> _:
      h

def Rv.chars(+s: String) -> List<&2, String>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{+h, +t}:
      SCon{h, SNil{}} <> Rv.chars(t)

def Rv.cut.k(long: Bool, +s: String) -> String:
  match long:
    case True{}:
      String.join(List.take(&2, String, Rv.chars(s), 72n), "") ++ "..."
    case False{}:
      s

def Rv.cut(+s: String) -> String:
  Rv.cut.k(Nat.is_gt(String.length(s), 72n), s)

# the title and body of an issue for a comment: the first line of its text
# (cut at 72 characters), then the place and the thread of replies
def Rv.first(+t: String) -> String:
  Rv.cut(Rv.line(String.split(t, '\n')))

type Issue is Data:
  Issue{title: String, body: String}

def Rv.commit.k(none: Bool, +m: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      " @ " ++ m

def Rv.commit.note(+c: Comment) -> String:
  Rv.commit.k(String.is_empty(Rv.commit(c)), Rv.commit(c))

def Review.issue(all: List<&2, Comment>, +c: Comment) -> Issue:
  Issue{Rv.first(Rv.text(c)), Rv.text(c) ++ "\n\n" ++ Rv.file(c) ++ " " ++ Rv.where(c) ++ Rv.commit.note(c) ++ "\n"
    ++ Rv.rep.lines(Review.replies(all, Rv.id(c)), "- ")}

def Review.issue.title(i: Issue) -> String:
  match i:
    case Issue{+t, _}:
      t

def Review.issue.body(i: Issue) -> String:
  match i:
    case Issue{_, +b}:
      b

# a comment on "f" at (1, 2) mm on F.Cu, by "p" (for tests and laws)
def Review.mk(+id: String, +parent: String) -> Comment:
  Comment{id, Anchor{"f", "", "board", "F.Cu", 1.0, 2.0, "i"}, "t", "p", 0n, parent, False{}}
