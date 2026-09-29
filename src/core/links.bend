import Base

# Links in a thread. A web address (http:// or https://) in a message, bare
# or as a markdown link `[label](url)`, is a link both clients draw and open
# (the web in a new tab, the window with the system's opener). A path to a
# file is a link too (Files below): it opens on the hub's machine. What
# counts as a link, and where it ends, is decided here, once, for all.

type Piece is Data:
  PText{text: String}
  PLink{label: String, url: String}

# only web addresses open (never javascript:, file:, ...)
def Link.is_web(+s: String) -> Bool:
  Bool.or(String.starts_with(s, "http://"), String.starts_with(s, "https://"))

# a web address with something after the scheme
def Link.valid(+s: String) -> Bool:
  Bool.and(Link.is_web(s), Bool.not(Bool.or(String.eq(s, "http://"), String.eq(s, "https://"))))

def Link.code(c: Char) -> U32:
  match c:
    case Chr{u}:
      u

# Files
# -----
# A path in a message is a link: bare, in backticks (Md.code in
# web/dom.bend) or as a markdown link's target. Its link keeps the path as
# written (a line may follow, :12 or #L12); a link that is not a web address
# is a file (Link.is_web decides). Clicking one asks the hub to open it
# (file.open); a relative path is in the thread's folder (Link.file.abs).

# what a path may hold besides letters and digits: . _ - / ~ + @ : #
def Link.pmark(+u: U32) -> Bool:
  Bool.or(Bool.or(Bool.or(U32.is_eq(u, 46), U32.is_eq(u, 95)), Bool.or(U32.is_eq(u, 45), U32.is_eq(u, 47))),
    Bool.or(Bool.or(U32.is_eq(u, 126), U32.is_eq(u, 43)), Bool.or(Bool.or(U32.is_eq(u, 64), U32.is_eq(u, 58)), U32.is_eq(u, 35))))

def Link.pchar(+c: Char) -> Bool:
  Bool.or(Bool.or(Char.is_alpha(c), Char.is_digit(c)), Link.pmark(Link.code(c)))

def Link.pchars(s: String, +ok: Bool) -> Bool:
  match s:
    case SNil{}:
      ok
    case SCon{+h, t}:
      Link.pchars(t, Bool.and(ok, Link.pchar(h)))

# the path part: up to a line (:) or an anchor (#), walked to the end so
# a long word costs no stack
type Pt is Data:
  Pt{done: Bool, acc: String}

def Link.part.step(st: Pt, +h: Char) -> Pt:
  match st:
    case Pt{True{}, acc}:
      Pt{True{}, acc}
    case Pt{False{}, +acc}:
      Bool.pick(Pt, Bool.or(U32.is_eq(Link.code(h), 58), U32.is_eq(Link.code(h), 35)), Pt{True{}, acc}, Pt{False{}, SCon{h, acc}})

def Link.part.go(s: String, st: Pt) -> Pt:
  match s:
    case SNil{}:
      st
    case SCon{+h, t}:
      Link.part.go(t, Link.part.step(st, h))

def Link.part.of(st: Pt) -> String:
  match st:
    case Pt{_, acc}:
      String.reverse(acc)

def Link.part(+s: String) -> String:
  Link.part.of(Link.part.go(s, Pt{False{}, SNil{}}))

# a file's extension: a dot then a letter
def Link.ext(s: String, +dot: Bool, +ok: Bool) -> Bool:
  match s:
    case SNil{}:
      ok
    case SCon{+h, t}:
      Link.ext(t, U32.is_eq(Link.code(h), 46), Bool.or(ok, Bool.and(dot, Char.is_alpha(h))))

def Link.digit(m: Maybe<&2, Char>) -> Bool:
  match m:
    case Some{c}:
      Char.is_digit(c)
    case None{}:
      False{}

# what may follow the path: nothing, a line (:12, :12:3) or #L12
def Link.sfx(+x: String) -> Bool:
  Bool.or(String.is_empty(x), Bool.or(String.starts_with(x, "#L"), Bool.and(String.starts_with(x, ":"), Link.digit(String.get(x, 1n)))))

def Link.last(+p: String) -> String:
  Maybe.default(&2, String, List.last(&2, String, String.split(p, '/')), "")

# a path by its look: absolute with a folder or a file, under ~/, ./ or
# ../, or a folder then a file with an extension ("and/or", "1/2", "/s"
# and "origin/main" are not)
def Link.shape(+p: String) -> Bool:
  Bool.or(Bool.or(String.starts_with(p, "~/"), String.starts_with(p, "./")), Bool.or(String.starts_with(p, "../"),
    Bool.or(Bool.and(String.starts_with(p, "/"), String.contains(String.drop(p, 1n), "/")), Link.ext(Link.last(p), False{}, False{}))))

# loose (a markdown link's target) also takes a lone file name (notes.md)
def Link.ref.ok(+p: String, +sfx: String, +loose: Bool) -> Bool:
  Bool.and(Bool.and(Link.sfx(sfx), Bool.not(String.ends_with(p, "."))), Bool.and(Bool.not(String.starts_with(p, "//")),
    Bool.or(Bool.and(String.contains(p, "/"), Link.shape(p)), Bool.and(loose, Link.ext(p, False{}, False{})))))

def Link.ref(+s: String, +loose: Bool) -> Bool:
  Bool.and(Bool.and(Link.pchars(s, True{}), Bool.not(String.contains(s, "://"))),
    Link.ref.ok(Link.part(s), String.drop(s, String.length(Link.part(s))), loose))

# a path as a reader writes one: bare in a sentence, or in backticks
def Link.is_path(+s: String) -> Bool:
  Link.ref(s, False{})

# a markdown target: file:// is dropped
def Link.target(+u: String) -> String:
  Bool.pick(String, String.starts_with(u, "file://"), String.drop(u, 7n), u)

# the path a file link names, without its line or anchor
def Link.file.path(+raw: String) -> String:
  Link.part(raw)

# absolute, or under ~/ (by its first char, so laws over "/" ++ s reduce)
def Link.rooted(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+h, t}:
      Bool.or(U32.is_eq(Link.code(h), 47), Bool.and(U32.is_eq(Link.code(h), 126), String.starts_with(t, "/")))

def Link.file.abs.k(keep: Bool, +cwd: String, +p: String) -> String:
  match keep:
    case True{}:
      p
    case False{}:
      Bool.pick(String, String.ends_with(cwd, "/"), cwd, cwd ++ "/") ++ Bool.pick(String, String.starts_with(p, "./"), String.drop(p, 2n), p)

# where a file link's file is: as written when absolute or under ~/ (or
# with no folder to be in), else in the thread's folder cwd
def Link.file.abs(+cwd: String, +raw: String) -> String:
  Link.file.abs.k(Bool.or(Link.rooted(raw), String.is_empty(cwd)), cwd, Link.file.path(raw))

# the hub's shell for file.open: the path is its $1, never shell text; ~/
# is the hub's home. "open" opens it with the system's opener
# (BACKPLANE_OPEN names another), "reveal" shows it in its folder (the
# desktop's file manager over D-Bus, else the folder opened; Finder on a Mac)
def Link.file.sh() -> String:
  "p=\"$1\"; case \"$p\" in \"~/\"*) p=\"$HOME/${p#??}\";; esac; case \"$p\" in /*) ;; *) p=\"$PWD/$p\";; esac; " ++
  "[ -e \"$p\" ] || { echo \"No such file: $p\"; exit 1; }; "

def Link.file.desk() -> String:
  "[ -n \"$DISPLAY$WAYLAND_DISPLAY\" ] || { echo \"No desktop on this machine to open it on\"; exit 1; }; "

def Link.file.open() -> String:
  Link.file.sh() ++ "if [ \"$(uname)\" = Darwin ]; then open \"$p\"; exit $?; fi; " ++ Link.file.desk() ++
  "(${BACKPLANE_OPEN:-xdg-open} \"$p\" >/dev/null 2>&1 &)"

def Link.file.reveal() -> String:
  Link.file.sh() ++ "if [ \"$(uname)\" = Darwin ]; then open -R \"$p\"; exit $?; fi; " ++ Link.file.desk() ++
  "u=$(printf %s \"$p\" | sed 's/%/%25/g; s/ /%20/g; s/#/%23/g; s/?/%3F/g'); " ++
  "dbus-send --session --print-reply --reply-timeout=3000 --dest=org.freedesktop.FileManager1 --type=method_call /org/freedesktop/FileManager1 " ++
  "org.freedesktop.FileManager1.ShowItems array:string:\"file://$u\" string:\"\" >/dev/null 2>&1 || " ++
  "(${BACKPLANE_OPEN:-xdg-open} \"$(dirname \"$p\")\" >/dev/null 2>&1 &)"

def Link.file.cmd(+how: String) -> String:
  Bool.pick(String, String.eq(how, "reveal"), Link.file.reveal(), Link.file.open())

# Scanning
# --------
# One pass over the text, char by char. Text so far is kept reversed (acc),
# as is the address or label being read.

type Scan is Data:
  SText{acc: String}
  SUrl{acc: String, u: String}
  SLab{acc: String, l: String}
  SMid{acc: String, l: String}
  SHref{acc: String, l: String, u: String}

type Sc is Data:
  Sc{scan: Scan, out: List<&2, Piece>}

# a finished run of text (acc reversed)
def Link.text(acc: String, out: List<&2, Piece>) -> List<&2, Piece>:
  match acc:
    case SNil{}:
      out
    case SCon{h, t}:
      PText{String.reverse(SCon{h, t})} <> out

# the char before continues a word (so "xhttp://" is not a link)
def Link.word(acc: String) -> Bool:
  match acc:
    case SNil{}:
      False{}
    case SCon{+h, _}:
      Bool.or(Char.is_alpha(h), Char.is_digit(h))

# an address starts here: an "h" (already read) then "ttp://" or "ttps://"
def Link.starts(+acc: String, +t: String) -> Bool:
  Bool.and(Bool.not(Link.word(acc)), Bool.or(String.starts_with(t, "ttp://"), String.starts_with(t, "ttps://")))

def Link.text.k(k: Nat, acc: String, out: List<&2, Piece>, +c: Char) -> Sc:
  match k:
    case 1n:
      Sc{SUrl{acc, SCon{c, SNil{}}}, out}
    case 2n:
      Sc{SLab{acc, SNil{}}, out}
    case _:
      Sc{SText{SCon{c, acc}}, out}

def Link.text.step(+acc: String, out: List<&2, Piece>, +c: Char, +t: String) -> Sc:
  Link.text.k(Bool.pick(Nat, Bool.and(U32.is_eq(Link.code(c), 104), Link.starts(acc, t)), 1n, Bool.pick(Nat, U32.is_eq(Link.code(c), 91), 2n, 0n)), acc, out, c)

# what ends a bare address: space, < > " `
def Link.stops(+c: Char) -> Bool:
  Bool.or(Char.is_space(c), Bool.or(Bool.or(U32.is_eq(Link.code(c), 60), U32.is_eq(Link.code(c), 62)), Bool.or(U32.is_eq(Link.code(c), 34), U32.is_eq(Link.code(c), 96))))

def Link.count(s: String, +x: U32) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{+h, t}:
      Nat.add(Bool.pick(Nat, U32.is_eq(Link.code(h), x), 1n, 0n), Link.count(t, x))

# what a sentence puts after an address: . , ; : ! ? ' ] and a ) it did not open
def Link.punct(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.or(U32.is_eq(c, 46), U32.is_eq(c, 44)), Bool.or(U32.is_eq(c, 59), U32.is_eq(c, 58))),
    Bool.or(Bool.or(U32.is_eq(c, 33), U32.is_eq(c, 63)), Bool.or(U32.is_eq(c, 39), U32.is_eq(c, 93))))

# u: the address up to and including its last char c, reversed
def Link.trims(+c: U32, +u: String) -> Bool:
  Bool.or(Link.punct(c), Bool.and(U32.is_eq(c, 41), Nat.is_gt(Link.count(u, 41), Link.count(u, 40))))

# trimming walks the reversed address from its end: trailing punctuation
# moves to the text after it (kept reversed), the rest is the address
type Tr is Data:
  Tr{done: Bool, keep: String, moved: String}

def Link.tr.done(st: Tr) -> Bool:
  match st:
    case Tr{d, _, _}:
      d

def Link.tr.cut(done: Bool, +h: Char, +u: String) -> Bool:
  match done:
    case True{}:
      False{}
    case False{}:
      Link.trims(Link.code(h), u)

def Link.tr.k(cut: Bool, +h: Char, st: Tr) -> Tr:
  match cut st:
    case True{} Tr{d, k, m}:
      Tr{d, k, String.append(m, SCon{h, SNil{}})}
    case False{} Tr{_, k, m}:
      Tr{True{}, SCon{h, k}, m}

def Link.tr(u: String, +st: Tr) -> Tr:
  match u:
    case SNil{}:
      st
    case SCon{+h, +t}:
      Link.tr(t, Link.tr.k(Link.tr.cut(Link.tr.done(st), h, SCon{h, t}), h, st))

def Link.url_end.v(ok: Bool, +url: String, acc: String, moved: String, out: List<&2, Piece>) -> Sc:
  match ok:
    case True{}:
      Sc{SText{moved}, PLink{url, url} <> Link.text(acc, out)}
    case False{}:
      Sc{SText{String.append(moved, String.append(String.reverse(url), acc))}, out}

def Link.url_end.k(tr: Tr, acc: String, out: List<&2, Piece>) -> Sc:
  match tr:
    case Tr{_, +url, moved}:
      Link.url_end.v(Link.valid(url), url, acc, moved, out)

# a bare address ended (u reversed)
def Link.url_end(acc: String, u: String, out: List<&2, Piece>) -> Sc:
  Link.url_end.k(Link.tr(u, Tr{False{}, SNil{}, SNil{}}), acc, out)

# the text step after an address ended at c
def Link.again(sc: Sc, +c: Char, +t: String) -> Sc:
  match sc:
    case Sc{SText{+acc}, out}:
      Link.text.step(acc, out, c, t)
    case Sc{s, out}:
      Sc{s, out}

def Link.url.k(stop: Bool, acc: String, u: String, out: List<&2, Piece>, +c: Char, +t: String) -> Sc:
  match stop:
    case True{}:
      Link.again(Link.url_end(acc, u, out), c, t)
    case False{}:
      Sc{SUrl{acc, SCon{c, u}}, out}

# a [label that went nowhere, back to text
def Link.lab.raw(l: String, acc: String) -> String:
  String.append(l, SCon{'[', acc})

def Link.lab.k(k: Nat, +acc: String, +l: String, out: List<&2, Piece>, +c: Char, +t: String) -> Sc:
  match k:
    case 1n:
      Sc{SMid{acc, l}, out}
    case 2n:
      Link.text.step(Link.lab.raw(l, acc), out, c, t)
    case _:
      Sc{SLab{acc, SCon{c, l}}, out}

def Link.mid.k(open: Bool, +acc: String, +l: String, out: List<&2, Piece>, +c: Char, +t: String) -> Sc:
  match open:
    case True{}:
      Sc{SHref{acc, l, SNil{}}, out}
    case False{}:
      Link.text.step(SCon{']', Link.lab.raw(l, acc)}, out, c, t)

# [label](u that went nowhere, back to text
def Link.href.raw(acc: String, l: String, u: String) -> String:
  String.append(u, SCon{'(', SCon{']', Link.lab.raw(l, acc)}})

def Link.label(+l: String, +u: String) -> String:
  Bool.pick(String, String.is_empty(l), String.reverse(u), String.reverse(l))

# a markdown image (![alt](path)) stays text: the image shows under it
def Link.bang(acc: String) -> Bool:
  match acc:
    case SNil{}:
      False{}
    case SCon{+h, _}:
      U32.is_eq(Link.code(h), 33)

# a markdown link's target: a web address, or a file (not an image's)
def Link.href.ok(+u: String, +acc: String) -> Bool:
  Bool.or(Link.valid(u), Bool.and(Bool.not(Link.bang(acc)), Link.ref(Link.target(u), True{})))

def Link.close(ok: Bool, +acc: String, +l: String, +u: String, out: List<&2, Piece>) -> Sc:
  match ok:
    case True{}:
      Sc{SText{SNil{}}, PLink{Link.label(l, u), Link.target(String.reverse(u))} <> Link.text(acc, out)}
    case False{}:
      Sc{SText{SCon{')', Link.href.raw(acc, l, u)}}, out}

def Link.href.k(k: Nat, +acc: String, +l: String, +u: String, out: List<&2, Piece>, +c: Char, +t: String) -> Sc:
  match k:
    case 1n:
      Link.close(Link.href.ok(String.reverse(u), acc), acc, l, u, out)
    case 2n:
      Link.text.step(Link.href.raw(acc, l, u), out, c, t)
    case _:
      Sc{SHref{acc, l, SCon{c, u}}, out}

def Link.step(sc: Sc, +c: Char, +t: String) -> Sc:
  match sc:
    case Sc{SText{+acc}, out}:
      Link.text.step(acc, out, c, t)
    case Sc{SUrl{acc, u}, out}:
      Link.url.k(Link.stops(c), acc, u, out, c, t)
    case Sc{SLab{acc, l}, out}:
      Link.lab.k(Bool.pick(Nat, U32.is_eq(Link.code(c), 93), 1n, Bool.pick(Nat, Bool.or(U32.is_eq(Link.code(c), 10), U32.is_eq(Link.code(c), 91)), 2n, 0n)), acc, l, out, c, t)
    case Sc{SMid{acc, l}, out}:
      Link.mid.k(U32.is_eq(Link.code(c), 40), acc, l, out, c, t)
    case Sc{SHref{acc, l, u}, out}:
      Link.href.k(Bool.pick(Nat, U32.is_eq(Link.code(c), 41), 1n, Bool.pick(Nat, Link.stops(c), 2n, 0n)), acc, l, u, out, c, t)

def Link.fin.text(sc: Sc) -> List<&2, Piece>:
  match sc:
    case Sc{SText{acc}, out}:
      List.reverse(&2, Piece, Link.text(acc, out))
    case Sc{_, out}:
      List.reverse(&2, Piece, out)

def Link.fin(sc: Sc) -> List<&2, Piece>:
  match sc:
    case Sc{SText{acc}, out}:
      List.reverse(&2, Piece, Link.text(acc, out))
    case Sc{SUrl{acc, u}, out}:
      Link.fin.text(Link.url_end(acc, u, out))
    case Sc{SLab{acc, l}, out}:
      List.reverse(&2, Piece, Link.text(Link.lab.raw(l, acc), out))
    case Sc{SMid{acc, l}, out}:
      List.reverse(&2, Piece, Link.text(SCon{']', Link.lab.raw(l, acc)}, out))
    case Sc{SHref{acc, l, u}, out}:
      List.reverse(&2, Piece, Link.text(Link.href.raw(acc, l, u), out))

def Link.go(s: String, sc: Sc) -> List<&2, Piece>:
  match s:
    case SNil{}:
      Link.fin(sc)
    case SCon{+c, +t}:
      Link.go(t, Link.step(sc, c, t))

# Bare paths
# ----------
# After the scan, each run of text is cut into words at spaces; a word
# that is a path (Link.is_path) once what wraps it is dropped (a leading
# ( [ " ' * < ` and a trailing . , ; : ! ? ' " ) ] * >) becomes a link.
# Text so far (txt), the word being read and the pieces are kept reversed.

type Bw is Data:
  Bw{txt: String, word: String, out: List<&2, Piece>}

def Link.wrap(+u: U32) -> Bool:
  Bool.or(Bool.or(Bool.or(U32.is_eq(u, 40), U32.is_eq(u, 91)), Bool.or(U32.is_eq(u, 34), U32.is_eq(u, 39))),
    Bool.or(Bool.or(U32.is_eq(u, 42), U32.is_eq(u, 60)), U32.is_eq(u, 96)))

def Link.after(+u: U32) -> Bool:
  Bool.or(Bool.or(Link.punct(u), U32.is_eq(u, 34)), Bool.or(Bool.or(U32.is_eq(u, 41), U32.is_eq(u, 42)), Bool.or(U32.is_eq(u, 62), U32.is_eq(u, 96))))

# how many of s's first chars wrap it
def Link.lead(s: String, +n: Nat, +on: Bool) -> Nat:
  match s:
    case SNil{}:
      n
    case SCon{+h, t}:
      Link.lead(t, Bool.pick(Nat, Bool.and(on, Link.wrap(Link.code(h))), 1n+n, n), Bool.and(on, Link.wrap(Link.code(h))))

# how many of a reversed word's first chars follow it
def Link.tail(s: String, +n: Nat, +on: Bool) -> Nat:
  match s:
    case SNil{}:
      n
    case SCon{+h, t}:
      Link.tail(t, Bool.pick(Nat, Bool.and(on, Link.after(Link.code(h))), 1n+n, n), Bool.and(on, Link.after(Link.code(h))))

def Link.mid(+w: String, +lead: Nat, +trail: Nat) -> String:
  String.take(String.drop(w, lead), Nat.sub(Nat.sub(String.length(w), lead), trail))

def Link.bare.hit(ok: Bool, +w: String, +lead: Nat, +core: String, txt: String, out: List<&2, Piece>) -> Bw:
  match ok:
    case True{}:
      Bw{String.reverse(String.drop(w, Nat.add(lead, String.length(core)))), SNil{}, PLink{core, core} <> Link.text(String.append(String.reverse(String.take(w, lead)), txt), out)}
    case False{}:
      Bw{String.append(String.reverse(w), txt), SNil{}, out}

def Link.bare.core(+w: String, +lead: Nat, +trail: Nat, txt: String, out: List<&2, Piece>) -> Bw:
  Link.bare.hit(Link.is_path(Link.mid(w, lead, trail)), w, lead, Link.mid(w, lead, trail), txt, out)

def Link.bare.word(+rev: String, txt: String, out: List<&2, Piece>) -> Bw:
  Link.bare.core(String.reverse(rev), Link.lead(String.reverse(rev), 0n, True{}), Link.tail(rev, 0n, True{}), txt, out)

def Link.bare.flush(txt: String, word: String, out: List<&2, Piece>) -> Bw:
  match word:
    case SNil{}:
      Bw{txt, SNil{}, out}
    case SCon{h, t}:
      Link.bare.word(SCon{h, t}, txt, out)

def Link.bare.push(b: Bw, +c: Char) -> Bw:
  match b:
    case Bw{txt, w, out}:
      Bw{SCon{c, txt}, w, out}

def Link.bare.k(sp: Bool, +c: Char, txt: String, word: String, out: List<&2, Piece>) -> Bw:
  match sp:
    case True{}:
      Link.bare.push(Link.bare.flush(txt, word, out), c)
    case False{}:
      Bw{txt, SCon{c, word}, out}

def Link.bare.step(st: Bw, +c: Char) -> Bw:
  match st:
    case Bw{txt, word, out}:
      Link.bare.k(Char.is_space(c), c, txt, word, out)

def Link.bare.go(s: String, st: Bw) -> Bw:
  match s:
    case SNil{}:
      st
    case SCon{+c, t}:
      Link.bare.go(t, Link.bare.step(st, c))

def Link.bare.end(b: Bw) -> List<&2, Piece>:
  match b:
    case Bw{txt, _, out}:
      List.reverse(&2, Piece, Link.text(txt, out))

def Link.bare.fin(st: Bw) -> List<&2, Piece>:
  match st:
    case Bw{txt, word, out}:
      Link.bare.end(Link.bare.flush(txt, word, out))

# a run of text with its bare paths as links (a run with no / has none)
def Link.bare.text.k(slash: Bool, +s: String) -> List<&2, Piece>:
  match slash:
    case True{}:
      Link.bare.fin(Link.bare.go(s, Bw{SNil{}, SNil{}, Nil{}}))
    case False{}:
      [PText{s}]

def Link.files(ps: List<&2, Piece>) -> List<&2, Piece>:
  match ps:
    case Nil{}:
      Nil{}
    case PText{+s} <> t:
      List.append(&2, Piece, Link.bare.text.k(String.contains(s, "/"), s), Link.files(t))
    case PLink{l, u} <> t:
      PLink{l, u} <> Link.files(t)

# text as runs of plain text and links, in order
def Link.pieces(+s: String) -> List<&2, Piece>:
  Link.files(Link.go(s, Sc{SText{SNil{}}, Nil{}}))

# the text a reader sees (a link shows its label)
def Link.plain(ps: List<&2, Piece>) -> String:
  match ps:
    case Nil{}:
      ""
    case PText{s} <> t:
      s ++ Link.plain(t)
    case PLink{l, _} <> t:
      l ++ Link.plain(t)

# the addresses, in order
def Link.urls(ps: List<&2, Piece>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case PText{_} <> t:
      Link.urls(t)
    case PLink{_, u} <> t:
      u <> Link.urls(t)

# Lines
# -----
# The window wraps a paragraph's text into lines first, then finds in each
# line the labels of the paragraph's links. A label cut by a wrap is not a
# link on either line.

# the first link whose label starts s
def Link.at(ls: List<&2, Piece>, +s: String) -> Maybe<&2, Piece>:
  match ls:
    case Nil{}:
      None{}
    case PText{_} <> t:
      Link.at(t, s)
    case PLink{+l, +u} <> t:
      Bool.pick(Maybe<&2, Piece>, Bool.and(Bool.not(String.is_empty(l)), String.starts_with(s, l)), Some{PLink{l, u}}, Link.at(t, s))

type Ct is Data:
  Ct{acc: String, skip: Nat, out: List<&2, Piece>}

def Link.cut.hit(m: Maybe<&2, Piece>, +c: Char, st: Ct) -> Ct:
  match m st:
    case Some{PLink{+l, u}} Ct{acc, _, out}:
      Ct{SNil{}, Nat.sub(String.length(l), 1n), PLink{l, u} <> Link.text(acc, out)}
    case _ Ct{acc, k, out}:
      Ct{SCon{c, acc}, k, out}

def Link.cut.step(skip: Nat, +ls: List<&2, Piece>, +c: Char, +s: String, st: Ct) -> Ct:
  match skip st:
    case 1n+k Ct{acc, _, out}:
      Ct{acc, k, out}
    case 0n _:
      Link.cut.hit(Link.at(ls, s), c, st)

def Link.cut.skip(st: Ct) -> Nat:
  match st:
    case Ct{_, k, _}:
      k

def Link.cut.fin(st: Ct) -> List<&2, Piece>:
  match st:
    case Ct{acc, _, out}:
      List.reverse(&2, Piece, Link.text(acc, out))

def Link.cut.go(s: String, +ls: List<&2, Piece>, +st: Ct) -> List<&2, Piece>:
  match s:
    case SNil{}:
      Link.cut.fin(st)
    case SCon{+c, +t}:
      Link.cut.go(t, ls, Link.cut.step(Link.cut.skip(st), ls, c, SCon{c, t}, st))

# a drawn line as runs of text and the links whose labels it shows
def Link.cut(+line: String, ls: List<&2, Piece>) -> List<&2, Piece>:
  match ls:
    case Nil{}:
      [PText{line}]
    case +h <> t:
      Link.cut.go(line, h <> t, Ct{SNil{}, 0n, Nil{}})

# links carried in a string (a laid-out line's spare field): label US url,
# joined by RS
def Link.enc(ls: List<&2, Piece>) -> String:
  match ls:
    case Nil{}:
      ""
    case PText{_} <> t:
      Link.enc(t)
    case PLink{l, u} <> t:
      l ++ SCon{Chr{31}, u} ++ SCon{Chr{30}, Link.enc(t)}

def Link.dec.one(+s: String) -> List<&2, Piece>:
  Bool.pick(List<&2, Piece>, String.is_empty(s), Nil{},
    [PLink{Maybe.default(&2, String, List.get(&2, String, String.split(s, Chr{31}), 0n), ""), Maybe.default(&2, String, List.get(&2, String, String.split(s, Chr{31}), 1n), "")}])

def Link.dec.all(xs: List<&2, String>) -> List<&2, Piece>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      List.append(&2, Piece, Link.dec.one(x), Link.dec.all(t))

def Link.dec(+s: String) -> List<&2, Piece>:
  Link.dec.all(String.split(s, Chr{30}))
