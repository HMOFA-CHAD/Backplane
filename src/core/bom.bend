import Base
import ./sexpr.bend as S
import ./utf8.bend as U

# Bill of materials from KiCad schematics (pure). A sheet's placed symbols
# become Parts (one per instance reference), sorted in natural order
# (C2 before C10), grouped into BOM lines, diffed by reference, checked by
# a few rules, and written as CSV or GFM tables. Laws `bom_*`.

type Fld is Data:
  Fld{k: String, v: String}

# unit: the symbol's unit number (a multi-unit part is one Part per
# reference once collapsed); inbom: KiCad's in_bom flag
type Part is Data:
  Part{ref: String, value: String, footprint: String, mpn: String, mfr: String, fields: List<&2, Fld>, dnp: Bool, inbom: Bool, lib: String, sheet: String, unit: Nat}

# a sheet file: its path and its bytes
type Sheet is Data:
  Sheet{path: String, text: List<&2, U32>}

type Inst is Data:
  Inst{ref: String, unit: Nat}

# Natural order of references
# ---------------------------

type RK is Data:
  RK{pre: String, num: Nat, post: String}

# the walk's state: prefix and suffix (reversed), the number, the phase
# (0 prefix, 1 digits, 2 suffix)
type RS is Data:
  RS{pre: String, num: Nat, post: String, ph: Nat}

def Bom.digit(+c: Char) -> Nat:
  match c:
    case Chr{x}:
      U32.to_nat((x - 48 : U32))

def Bom.rev(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      acc
    case SCon{c, t}:
      Bom.rev(t, SCon{c, acc})

def Bom.step.k(ph: Nat, d: Bool, pre: String, num: Nat, post: String, +c: Char) -> RS:
  match ph d:
    case 0n True{}:
      RS{pre, Bom.digit(c), post, 1n}
    case 0n False{}:
      RS{SCon{c, pre}, num, post, 0n}
    case 1n True{}:
      RS{pre, Nat.add(Nat.mul(num, 10n), Bom.digit(c)), post, 1n}
    case 1n False{}:
      RS{pre, num, SCon{c, post}, 2n}
    case _ _:
      RS{pre, num, SCon{c, post}, 2n}

def Bom.step(st: RS, +c: Char) -> RS:
  match st:
    case RS{pre, num, post, ph}:
      Bom.step.k(ph, Char.is_digit(c), pre, num, post, c)

def Bom.rk.go(s: String, st: RS) -> RK:
  match s:
    case SNil{}:
      match st:
        case RS{pre, num, post, _}:
          RK{Bom.rev(pre, ""), num, Bom.rev(post, "")}
    case SCon{+c, t}:
      Bom.rk.go(t, Bom.step(st, c))

# "R12a" is ("R", 12, "a")
def Bom.rk(s: String) -> RK:
  Bom.rk.go(s, RS{"", 0n, "", 0n})

def Bom.then(c: Cmp, d: Cmp) -> Cmp:
  match c:
    case EQ{}:
      d
    case _:
      c

def Bom.cmp.rk(a: RK, b: RK) -> Cmp:
  match a b:
    case RK{p1, n1, s1} RK{p2, n2, s2}:
      Bom.then(String.order(p1, p2), Bom.then(Nat.cmp(n1, n2), String.order(s1, s2)))

# natural comparison of two references
def Bom.cmp.ref(a: String, b: String) -> Cmp:
  Bom.cmp.rk(Bom.rk(a), Bom.rk(b))

def Bom.before(a: String, b: String) -> Bool:
  Cmp.is_lt(Bom.cmp.ref(a, b))

def Bom.cmp.part(a: Part, b: Part) -> Cmp:
  match a b:
    case Part{r1, _, _, _, _, _, _, _, l1, s1, u1} Part{r2, _, _, _, _, _, _, _, l2, s2, u2}:
      Bom.then(Bom.cmp.ref(r1, r2), Bom.then(Nat.cmp(u1, u2), Bom.then(String.order(s1, s2), String.order(l1, l2))))

def Bom.le(a: Part, b: Part) -> Bool:
  Cmp.is_le(Bom.cmp.part(a, b))

# parts in natural reference order
def Bom.sort(+ps: List<&2, Part>) -> List<&2, Part>:
  List.sort(~Part, ~Bom.le, ps)

# Accessors
# ---------

def Bom.ref(p: Part) -> String:
  match p:
    case Part{r, _, _, _, _, _, _, _, _, _, _}:
      r

def Bom.value(p: Part) -> String:
  match p:
    case Part{_, v, _, _, _, _, _, _, _, _, _}:
      v

def Bom.footprint(p: Part) -> String:
  match p:
    case Part{_, _, f, _, _, _, _, _, _, _, _}:
      f

def Bom.mpn(p: Part) -> String:
  match p:
    case Part{_, _, _, m, _, _, _, _, _, _, _}:
      m

def Bom.mfr(p: Part) -> String:
  match p:
    case Part{_, _, _, _, m, _, _, _, _, _, _}:
      m

def Bom.fields(p: Part) -> List<&2, Fld>:
  match p:
    case Part{_, _, _, _, _, fs, _, _, _, _, _}:
      fs

def Bom.dnp(p: Part) -> Bool:
  match p:
    case Part{_, _, _, _, _, _, d, _, _, _, _}:
      d

def Bom.inbom(p: Part) -> Bool:
  match p:
    case Part{_, _, _, _, _, _, _, b, _, _, _}:
      b

def Bom.unit(p: Part) -> Nat:
  match p:
    case Part{_, _, _, _, _, _, _, _, _, _, u}:
      u

def Bom.yes(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

# Sorting, collapsing, deduping
# -----------------------------

def Bom.keep(same: Bool, +p: Part, acc: List<&2, Part>) -> List<&2, Part>:
  match same:
    case True{}:
      acc
    case False{}:
      p <> acc

# the first part of each reference of a sorted list
def Bom.uniq.go(ps: List<&2, Part>, last: String, acc: List<&2, Part>) -> List<&2, Part>:
  match ps:
    case Nil{}:
      List.reverse(&2, Part, acc)
    case +p <> t:
      Bom.uniq.go(t, Bom.ref(p), Bom.keep(String.eq(Bom.ref(p), last), p, acc))

def Bom.uniq(ps: List<&2, Part>) -> List<&2, Part>:
  Bom.uniq.go(ps, "\0", Nil{})

# sorted and one part a reference: what a diff compares
def Bom.norm(ps: List<&2, Part>) -> List<&2, Part>:
  Bom.uniq(Bom.sort(ps))

# another unit of the same reference folds into the first; a unit seen
# twice stays (the duplicate rule reports it)
def Bom.fold.go(ps: List<&2, Part>, lr: String, lu: Nat, acc: List<&2, Part>) -> List<&2, Part>:
  match ps:
    case Nil{}:
      List.reverse(&2, Part, acc)
    case +p <> t:
      Bom.fold.go(t, Bom.ref(p), Bom.unit(p), Bom.keep(Bool.and(String.eq(Bom.ref(p), lr), Bool.not(Nat.is_eq(Bom.unit(p), lu))), p, acc))

def Bom.fold(ps: List<&2, Part>) -> List<&2, Part>:
  Bom.fold.go(ps, "\0", 0n, Nil{})

# Reading a symbol
# ----------------

def Bom.nz.k(blank: Bool, s: String) -> String:
  match blank:
    case True{}:
      ""
    case False{}:
      s

# KiCad writes "~" for an empty field
def Bom.nz(+s: String) -> String:
  Bom.nz.k(String.eq(s, "~"), s)

# a property form as a field
def Bom.fld(+p: S.Sx) -> Fld:
  Fld{S.Sx.arg(p, 0n), S.Sx.arg(p, 1n)}

def Bom.flds(ps: List<&2, S.Sx>) -> List<&2, Fld>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      Bom.fld(p) <> Bom.flds(t)

def Bom.hit(xs: List<&2, Fld>, +name: String) -> Bool:
  match xs:
    case Fld{k, _} <> _:
      String.eq(String.to_lower(k), name)
    case Nil{}:
      False{}

def Bom.get.go(xs: List<&2, Fld>, hit: Bool, +name: String) -> String:
  match xs hit:
    case Fld{_, v} <> _ True{}:
      v
    case _ <> +t False{}:
      Bom.get.go(t, Bom.hit(t, name), name)
    case Nil{} _:
      ""

# the value of the first field called name (lower case), "" when none
def Bom.get(+xs: List<&2, Fld>, +name: String) -> String:
  Bom.get.go(xs, Bom.hit(xs, name), name)

def Bom.first.if(none: Bool, acc: String, v: String) -> String:
  match none:
    case True{}:
      Bom.nz(v)
    case False{}:
      acc

def Bom.first.pick(+acc: String, v: String) -> String:
  Bom.first.if(String.is_empty(acc), acc, v)

# the first of several names that has a value
def Bom.first(names: List<&2, String>, +fs: List<&2, Fld>, acc: String) -> String:
  match names:
    case Nil{}:
      acc
    case +n <> t:
      Bom.first(t, fs, Bom.first.pick(acc, Bom.get(fs, n)))

def Bom.mpn.names() -> List<&2, String>:
  ["mpn", "manufacturer_part_number", "manufacturer part number", "mfr pn", "pn"]

def Bom.mfr.names() -> List<&2, String>:
  ["manufacturer", "mfr"]

def Bom.supplier.of(+k: String) -> Bool:
  Bool.or(String.eq(k, "lcsc"), Bool.or(String.eq(k, "mouser"), String.eq(k, "digikey")))

def Bom.supplier(+k: String) -> Bool:
  Bom.supplier.of(String.to_lower(k))

def Bom.keep.fld(ok: Bool, +f: Fld, rest: List<&2, Fld>) -> List<&2, Fld>:
  match ok:
    case True{}:
      f <> rest
    case False{}:
      rest

def Bom.sup.of(f: Fld) -> Bool:
  match f:
    case Fld{k, v}:
      Bool.and(Bom.supplier(k), Bool.not(String.is_empty(Bom.nz(v))))

# the supplier part-number fields, under the names the sheet gives them
def Bom.sups(fs: List<&2, Fld>) -> List<&2, Fld>:
  match fs:
    case Nil{}:
      Nil{}
    case +f <> t:
      Bom.keep.fld(Bom.sup.of(f), f, Bom.sups(t))

# Instances
# ---------

def Bom.num.go(s: String, acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{+c, t}:
      Bom.num.go(t, Nat.add(Nat.mul(acc, 10n), Bom.digit(c)))

def Bom.num.k(blank: Bool, s: String, d: Nat) -> Nat:
  match blank:
    case True{}:
      d
    case False{}:
      Bom.num.go(s, 0n)

# a number written in digits, d when blank
def Bom.num(+s: String, d: Nat) -> Nat:
  Bom.num.k(String.is_empty(s), s, d)

def Bom.paths(ps: List<&2, S.Sx>) -> List<&2, Inst>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Inst{S.Sx.attr(p, "reference"), Bom.num(S.Sx.attr(p, "unit"), 1n)} <> Bom.paths(t)

def Bom.proj.paths(+pr: S.Sx) -> List<&2, Inst>:
  Bom.paths(S.Sx.all(S.Sx.args(pr), "path"))

def Bom.all.paths(prs: List<&2, S.Sx>) -> List<&2, Inst>:
  match prs:
    case Nil{}:
      Nil{}
    case pr <> t:
      List.append(&2, Inst, Bom.proj.paths(pr), Bom.all.paths(t))

def Bom.mine.k(same: Bool, +p: S.Sx, rest: List<&2, S.Sx>) -> List<&2, S.Sx>:
  match same:
    case True{}:
      p <> rest
    case False{}:
      rest

# the projects named `project`
def Bom.mine(prs: List<&2, S.Sx>, +project: String) -> List<&2, S.Sx>:
  match prs:
    case Nil{}:
      Nil{}
    case +p <> t:
      Bom.mine.k(String.eq(S.Sx.arg(p, 0n), project), p, Bom.mine(t, project))

def Bom.choose(all: List<&2, S.Sx>, mine: List<&2, S.Sx>) -> List<&2, S.Sx>:
  match mine:
    case Nil{}:
      all
    case _:
      mine

def Bom.insts.of(+prs: List<&2, S.Sx>, +project: String) -> List<&2, Inst>:
  Bom.all.paths(Bom.choose(prs, Bom.mine(prs, project)))

# every instance (reference, unit) of a symbol; those of `project` when the
# symbol has any, else all
def Bom.insts(+x: S.Sx, +project: String) -> List<&2, Inst>:
  Bom.insts.of(S.Sx.all(S.Sx.args(S.Sx.get(x, "instances")), "project"), project)

# power symbols and flags are not parts
def Bom.skip(+lib: String, +ref: String) -> Bool:
  Bool.or(String.starts_with(lib, "power:"), String.starts_with(ref, "#"))

def Bom.part(sheet: String, lib: String, +fs: List<&2, Fld>, dnp: Bool, inb: Bool, +ref: String, unit: Nat) -> Part:
  Part{ref, Bom.nz(Bom.get(fs, "value")), Bom.nz(Bom.get(fs, "footprint")), Bom.first(Bom.mpn.names(), fs, ""), Bom.first(Bom.mfr.names(), fs, ""), Bom.sups(fs), dnp, inb, lib, sheet, unit}

def Bom.row.k(skip: Bool, p: Part) -> List<&2, Part>:
  match skip:
    case True{}:
      Nil{}
    case False{}:
      [p]

def Bom.rows(ins: List<&2, Inst>, +sheet: String, +lib: String, +fs: List<&2, Fld>, +dnp: Bool, +inb: Bool) -> List<&2, Part>:
  match ins:
    case Nil{}:
      Nil{}
    case Inst{+r, u} <> t:
      List.append(&2, Part, Bom.row.k(Bom.skip(lib, r), Bom.part(sheet, lib, fs, dnp, inb, r, u)), Bom.rows(t, sheet, lib, fs, dnp, inb))

def Bom.insts.or(ins: List<&2, Inst>, d: Inst) -> List<&2, Inst>:
  match ins:
    case Nil{}:
      [d]
    case _:
      ins

def Bom.sym.k(sheet: String, lib: String, +fs: List<&2, Fld>, dnp: Bool, inb: Bool, ins: List<&2, Inst>, unit: Nat) -> List<&2, Part>:
  Bom.rows(Bom.insts.or(ins, Inst{Bom.get(fs, "reference"), unit}), sheet, lib, fs, dnp, inb)

def Bom.sym(+sheet: String, +project: String, +x: S.Sx) -> List<&2, Part>:
  Bom.sym.k(sheet, S.Sx.attr(x, "lib_id"), Bom.flds(S.Sx.all(S.Sx.args(x), "property")), String.eq(S.Sx.attr(x, "dnp"), "yes"), Bool.not(String.eq(S.Sx.attr(x, "in_bom"), "no")), Bom.insts(x, project), Bom.num(S.Sx.attr(x, "unit"), 1n))

# a top-level form's first bytes say whether it ins a placed symbol
# ("(symbol " and not "(symbol_instances" or "(lib_symbols")
def Bom.issym.k(+s: String) -> Bool:
  Bool.or(Bool.or(String.starts_with(s, "(symbol "), String.starts_with(s, "(symbol\n")), Bool.or(String.starts_with(s, "(symbol\t"), String.starts_with(s, "(symbol\r")))

def Bom.issym(bs: List<&2, U32>) -> Bool:
  Bom.issym.k(U.Utf8.decode(List.take(&2, U32, bs, 8n)))

def Bom.one.k(sy: Bool, bs: List<&2, U32>, sheet: String, project: String) -> List<&2, Part>:
  match sy:
    case True{}:
      Bom.sym(sheet, project, S.Sx.parse(bs))
    case False{}:
      Nil{}

def Bom.one(+bs: List<&2, U32>, sheet: String, project: String) -> List<&2, Part>:
  Bom.one.k(Bom.issym(bs), bs, sheet, project)

def Bom.syms(fs: List<&2, List<&2, U32>>, +sheet: String, +project: String) -> List<&2, Part>:
  match fs:
    case Nil{}:
      Nil{}
    case f <> t:
      List.append(&2, Part, Bom.one(f, sheet, project), Bom.syms(t, sheet, project))

def Bom.sheet.k(m: Maybe<&2, List<&2, List<&2, U32>>>, sheet: String, project: String) -> List<&2, Part>:
  match m:
    case Some{fs}:
      Bom.syms(fs, sheet, project)
    case None{}:
      Nil{}

# every part of one sheet file, unsorted; project "" takes all instances
def Bom.sheet(project: String, sh: Sheet) -> List<&2, Part>:
  match sh:
    case Sheet{path, bs}:
      Bom.sheet.k(S.Sx.forms(bs), path, project)

def Bom.sheets(+project: String, shs: List<&2, Sheet>) -> List<&2, Part>:
  match shs:
    case Nil{}:
      Nil{}
    case sh <> t:
      List.append(&2, Part, Bom.sheet(project, sh), Bom.sheets(project, t))

# the design's parts: natural order, a multi-unit part once. A reference
# that two symbols share stays twice (the duplicate rule says so).
def Bom.parts(project: String, shs: List<&2, Sheet>) -> List<&2, Part>:
  Bom.fold(Bom.sort(Bom.sheets(project, shs)))

# BOM lines
# ---------

# parts that are alike: refs in natural order, qty the count
type Line is Data:
  Line{refs: List<&2, String>, qty: Nat, value: String, footprint: String, mpn: String, mfr: String, dnp: Bool}

def Bom.yn(b: Bool) -> Nat:
  match b:
    case True{}:
      1n
    case False{}:
      0n

def Bom.cmp.key(+a: Part, +b: Part) -> Cmp:
  Bom.then(String.order(Bom.value(a), Bom.value(b)), Bom.then(String.order(Bom.footprint(a), Bom.footprint(b)), Bom.then(String.order(Bom.mpn(a), Bom.mpn(b)), Nat.cmp(Bom.yn(Bom.dnp(a)), Bom.yn(Bom.dnp(b))))))

# alike for the BOM: value, footprint, MPN and DNP
def Bom.alike(a: Part, b: Part) -> Bool:
  Cmp.is_eq(Bom.cmp.key(a, b))

def Bom.key.le.k(+a: Part, +b: Part) -> Bool:
  Cmp.is_le(Bom.then(Bom.cmp.key(a, b), Bom.cmp.part(a, b)))

def Bom.key.le(a: Part, b: Part) -> Bool:
  Bom.key.le.k(a, b)

def Bom.line.of(+p: Part) -> Line:
  Line{[Bom.ref(p)], 1n, Bom.value(p), Bom.footprint(p), Bom.mpn(p), Bom.mfr(p), Bom.dnp(p)}

def Bom.line.add(l: Line, +p: Part) -> Line:
  match l:
    case Line{rs, q, v, f, m, mf, d}:
      Line{Bom.ref(p) <> rs, Nat.add(q, 1n), v, f, m, mf, d}

def Bom.line.part(l: Line) -> Part:
  match l:
    case Line{_, _, v, f, m, mf, d}:
      Part{"", v, f, m, mf, Nil{}, d, True{}, "", "", 0n}

def Bom.line.fin(l: Line) -> Line:
  match l:
    case Line{rs, q, v, f, m, mf, d}:
      Line{List.reverse(&2, String, rs), q, v, f, m, mf, d}

def Bom.line.first(l: Line) -> String:
  match l:
    case Line{r <> _, _, _, _, _, _, _}:
      r
    case _:
      ""

def Bom.line.le(a: Line, b: Line) -> Bool:
  Cmp.is_le(Bom.cmp.ref(Bom.line.first(a), Bom.line.first(b)))

# the line being built (refs newest first) and the finished ones
type Gs is Data:
  Gs{cur: Line, acc: List<&2, Line>}

def Bom.gstep.k(alike: Bool, cur: Line, +p: Part, acc: List<&2, Line>) -> Gs:
  match alike:
    case True{}:
      Gs{Bom.line.add(cur, p), acc}
    case False{}:
      Gs{Bom.line.of(p), Bom.line.fin(cur) <> acc}

def Bom.gstep(st: Gs, +p: Part) -> Gs:
  match st:
    case Gs{+cur, acc}:
      Bom.gstep.k(Bom.alike(Bom.line.part(cur), p), cur, p, acc)

def Bom.group.go(ps: List<&2, Part>, st: Gs) -> List<&2, Line>:
  match ps:
    case Nil{}:
      match st:
        case Gs{cur, acc}:
          Bom.line.fin(cur) <> acc
    case +p <> t:
      Bom.group.go(t, Bom.gstep(st, p))

def Bom.group.sorted(ps: List<&2, Part>) -> List<&2, Line>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Bom.group.go(t, Gs{Bom.line.of(p), Nil{}})

# BOM lines: parts with the same value, footprint, MPN and DNP together,
# the lines by their first reference
def Bom.group(ps: List<&2, Part>) -> List<&2, Line>:
  List.sort(~Line, ~Bom.line.le, Bom.group.sorted(List.sort(~Part, ~Bom.key.le, Bom.uniq(Bom.sort(ps)))))

def Bom.refs(l: Line) -> String:
  match l:
    case Line{rs, _, _, _, _, _, _}:
      String.join(rs, ", ")

# Diff
# ----

# one field that moved: its name, what it was, what it is
type Dl is Data:
  Dl{field: String, was: String, now: String}

# kind: "added", "removed" or "changed"; added and removed list what the
# part is, changed lists only what moved
type Chg is Data:
  Chg{ref: String, kind: String, deltas: List<&2, Dl>}

def Bom.dl.if(differ: Bool, d: Dl, rest: List<&2, Dl>) -> List<&2, Dl>:
  match differ:
    case True{}:
      d <> rest
    case False{}:
      rest

def Bom.dl(field: String, +was: String, +now: String, rest: List<&2, Dl>) -> List<&2, Dl>:
  Bom.dl.if(Bool.not(String.eq(was, now)), Dl{field, was, now}, rest)

# fields of the old part, then those only the new one has
def Bom.fdiff.old(fs: List<&2, Fld>, +ns: List<&2, Fld>) -> List<&2, Dl>:
  match fs:
    case Nil{}:
      Nil{}
    case Fld{+k, +v} <> t:
      Bom.dl(k, v, Bom.get(ns, String.to_lower(k)), Bom.fdiff.old(t, ns))

def Bom.fdiff.new(ns: List<&2, Fld>, +os: List<&2, Fld>) -> List<&2, Dl>:
  match ns:
    case Nil{}:
      Nil{}
    case Fld{+k, +v} <> t:
      Bom.dl.if(String.is_empty(Bom.get(os, String.to_lower(k))), Dl{k, "", v}, Bom.fdiff.new(t, os))

def Bom.changes(+o: Part, +n: Part) -> List<&2, Dl>:
  +c0 = List.append(&2, Dl, Bom.fdiff.old(Bom.fields(o), Bom.fields(n)), Bom.fdiff.new(Bom.fields(n), Bom.fields(o)))
  +c1 = Bom.dl("dnp", Bom.yes(Bom.dnp(o)), Bom.yes(Bom.dnp(n)), c0)
  +c2 = Bom.dl("mfr", Bom.mfr(o), Bom.mfr(n), c1)
  +c3 = Bom.dl("mpn", Bom.mpn(o), Bom.mpn(n), c2)
  +c4 = Bom.dl("footprint", Bom.footprint(o), Bom.footprint(n), c3)
  Bom.dl("value", Bom.value(o), Bom.value(n), c4)

def Bom.yes.if(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      ""

# what a part is, as deltas from nothing (an added part)
def Bom.facts(+p: Part) -> List<&2, Dl>:
  +c0 = Bom.fdiff.new(Bom.fields(p), Nil{})
  +c1 = Bom.dl("dnp", "", Bom.yes.if(Bom.dnp(p)), c0)
  +c2 = Bom.dl("mfr", "", Bom.mfr(p), c1)
  +c3 = Bom.dl("mpn", "", Bom.mpn(p), c2)
  +c4 = Bom.dl("footprint", "", Bom.footprint(p), c3)
  Bom.dl("value", "", Bom.value(p), c4)

def Bom.flip(ds: List<&2, Dl>) -> List<&2, Dl>:
  match ds:
    case Nil{}:
      Nil{}
    case Dl{f, w, n} <> t:
      Dl{f, n, w} <> Bom.flip(t)

# the change between two parts of one reference (none when alike)
def Bom.chg.k(ds: List<&2, Dl>, ref: String) -> List<&2, Chg>:
  match ds:
    case Nil{}:
      Nil{}
    case _:
      [Chg{ref, "changed", ds}]

def Bom.chg(+o: Part, n: Part) -> List<&2, Chg>:
  Bom.chg.k(Bom.changes(o, n), Bom.ref(o))

def Bom.push(c: List<&2, Chg>, acc: List<&2, Chg>) -> List<&2, Chg>:
  match c:
    case Nil{}:
      acc
    case x <> _:
      x <> acc

def Bom.side.of(c: Cmp) -> Nat:
  match c:
    case LT{}:
      1n
    case EQ{}:
      0n
    case GT{}:
      2n

# which side goes next: 0 both (same reference), 1 the old, 2 the new
def Bom.side(os: List<&2, Part>, ns: List<&2, Part>) -> Nat:
  match os ns:
    case +o <> _ +n <> _:
      Bom.side.of(Bom.cmp.ref(Bom.ref(o), Bom.ref(n)))
    case _ <> _ Nil{}:
      1n
    case Nil{} _:
      2n

# both sorted and unique; n bounds the steps
def Bom.walk(n: Nat, k: Nat, os: List<&2, Part>, ns: List<&2, Part>, acc: List<&2, Chg>) -> List<&2, Chg>:
  match n k os ns:
    case 1n+m 0n +o <> +ot +p <> +nt:
      Bom.walk(m, Bom.side(ot, nt), ot, nt, Bom.push(Bom.chg(o, p), acc))
    case 1n+m 1n +o <> +ot +ns2:
      Bom.walk(m, Bom.side(ot, ns2), ot, ns2, Chg{Bom.ref(o), "removed", Bom.flip(Bom.facts(o))} <> acc)
    case 1n+m 2n +os2 +p <> +nt:
      Bom.walk(m, Bom.side(os2, nt), os2, nt, Chg{Bom.ref(p), "added", Bom.facts(p)} <> acc)
    case _ _ _ _:
      List.reverse(&2, Chg, acc)

def Bom.diff.k(+os: List<&2, Part>, +ns: List<&2, Part>) -> List<&2, Chg>:
  Bom.walk(Nat.add(List.length(&2, Part, os), List.length(&2, Part, ns)), Bom.side(os, ns), os, ns, Nil{})

# the changes from one BOM to another, by reference, in natural order
def Bom.diff(old: List<&2, Part>, new: List<&2, Part>) -> List<&2, Chg>:
  Bom.diff.k(Bom.norm(old), Bom.norm(new))

def Bom.count.k(b: Bool) -> Nat:
  match b:
    case True{}:
      1n
    case False{}:
      0n

def Bom.count(+kind: String, cs: List<&2, Chg>) -> Nat:
  match cs:
    case Nil{}:
      0n
    case Chg{_, k, _} <> t:
      Nat.add(Bom.count.k(String.eq(k, kind)), Bom.count(kind, t))

def Bom.label.if(none: Bool, mpn: String, v: String, f: String) -> String:
  match none:
    case True{}:
      String.join([v, f], " ")
    case False{}:
      mpn

def Bom.label.k(+mpn: String, +v: String, +f: String) -> String:
  Bom.label.if(String.is_empty(mpn), mpn, v, f)

# Parts summary
# -------------

# a part as the buyer sees it: its MPN, else its value and footprint
def Bom.label(+p: Part) -> String:
  Bom.label.k(Bom.mpn(p), Bom.value(p), Bom.footprint(p))

type Tal is Data:
  Tal{part: String, n: Nat}

# one part's quantity in the old BOM and in the new
type Sum is Data:
  Sum{part: String, was: Nat, now: Nat}

def Bom.label.le(a: Part, b: Part) -> Bool:
  String.is_le(Bom.label(a), Bom.label(b))

type Ts is Data:
  Ts{cur: Tal, acc: List<&2, Tal>}

def Bom.tstep.k(same: Bool, +l: String, cur: Tal, acc: List<&2, Tal>) -> Ts:
  match same:
    case True{}:
      match cur:
        case Tal{p, n}:
          Ts{Tal{p, Nat.add(n, 1n)}, acc}
    case False{}:
      Ts{Tal{l, 1n}, cur <> acc}

def Bom.tal.part(t: Tal) -> String:
  match t:
    case Tal{p, _}:
      p

def Bom.tstep(st: Ts, +l: String) -> Ts:
  match st:
    case Ts{+cur, acc}:
      Bom.tstep.k(String.eq(l, Bom.tal.part(cur)), l, cur, acc)

def Bom.tally.go(ps: List<&2, Part>, st: Ts) -> List<&2, Tal>:
  match ps:
    case Nil{}:
      match st:
        case Ts{cur, acc}:
          List.reverse(&2, Tal, cur <> acc)
    case +p <> t:
      Bom.tally.go(t, Bom.tstep(st, Bom.label(p)))

def Bom.tally.k(ps: List<&2, Part>) -> List<&2, Tal>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Bom.tally.go(t, Ts{Tal{Bom.label(p), 1n}, Nil{}})

# quantity of each part (by label), labels ascending
def Bom.tally(ps: List<&2, Part>) -> List<&2, Tal>:
  Bom.tally.k(List.sort(~Part, ~Bom.label.le, Bom.uniq(Bom.sort(ps))))

def Bom.sum.side(os: List<&2, Tal>, ns: List<&2, Tal>) -> Nat:
  match os ns:
    case Tal{a, _} <> _ Tal{b, _} <> _:
      Bom.side.of(String.order(a, b))
    case _ <> _ Nil{}:
      1n
    case Nil{} _:
      2n

def Bom.sum.walk(n: Nat, k: Nat, os: List<&2, Tal>, ns: List<&2, Tal>, acc: List<&2, Sum>) -> List<&2, Sum>:
  match n k os ns:
    case 1n+m 0n Tal{p, a} <> +ot Tal{_, b} <> +nt:
      Bom.sum.walk(m, Bom.sum.side(ot, nt), ot, nt, Sum{p, a, b} <> acc)
    case 1n+m 1n Tal{p, a} <> +ot +ns2:
      Bom.sum.walk(m, Bom.sum.side(ot, ns2), ot, ns2, Sum{p, a, 0n} <> acc)
    case 1n+m 2n +os2 Tal{p, b} <> +nt:
      Bom.sum.walk(m, Bom.sum.side(os2, nt), os2, nt, Sum{p, 0n, b} <> acc)
    case _ _ _ _:
      List.reverse(&2, Sum, acc)

def Bom.summary.k(+os: List<&2, Tal>, +ns: List<&2, Tal>) -> List<&2, Sum>:
  Bom.sum.walk(Nat.add(List.length(&2, Tal, os), List.length(&2, Tal, ns)), Bom.sum.side(os, ns), os, ns, Nil{})

# each part's quantity in the old BOM and the new
def Bom.summary(old: List<&2, Part>, new: List<&2, Part>) -> List<&2, Sum>:
  Bom.summary.k(Bom.tally(old), Bom.tally(new))

# Rules
# -----

# rule id, "error" or "warning", the reference, the message
type Fnd is Data:
  Fnd{id: String, sev: String, ref: String, msg: String}

def Bom.fnd.if(hit: Bool, f: Fnd, rest: List<&2, Fnd>) -> List<&2, Fnd>:
  match hit:
    case True{}:
      f <> rest
    case False{}:
      rest

def Bom.unannotated.of(+r: String) -> Bool:
  Bool.or(String.is_empty(r), String.ends_with(r, "?"))

def Bom.r.unannotated(ps: List<&2, Part>) -> List<&2, Fnd>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Bom.fnd.if(Bom.unannotated.of(Bom.ref(p)), Fnd{"bom_unannotated", "error", Bom.ref(p), "reference not annotated"}, Bom.r.unannotated(t))

def Bom.r.footprint(ps: List<&2, Part>) -> List<&2, Fnd>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Bom.fnd.if(String.is_empty(Bom.footprint(p)), Fnd{"bom_missing_footprint", "warning", Bom.ref(p), "no footprint"}, Bom.r.footprint(t))

def Bom.r.value(ps: List<&2, Part>) -> List<&2, Fnd>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Bom.fnd.if(String.is_empty(Bom.value(p)), Fnd{"bom_missing_value", "warning", Bom.ref(p), "no value"}, Bom.r.value(t))

def Bom.r.dnp(ps: List<&2, Part>) -> List<&2, Fnd>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Bom.fnd.if(Bool.and(Bom.dnp(p), Bom.inbom(p)), Fnd{"bom_dnp_in_bom", "warning", Bom.ref(p), "DNP part is still in the BOM"}, Bom.r.dnp(t))

def Bom.mpn.some(ps: List<&2, Part>) -> Bool:
  match ps:
    case +p <> _:
      Bool.not(String.is_empty(Bom.mpn(p)))
    case Nil{}:
      False{}

def Bom.has.go(ps: List<&2, Part>, hit: Bool) -> Bool:
  match ps hit:
    case _ True{}:
      True{}
    case _ <> +t False{}:
      Bom.has.go(t, Bom.mpn.some(t))
    case Nil{} _:
      False{}

def Bom.has.mpn(+ps: List<&2, Part>) -> Bool:
  Bom.has.go(ps, Bom.mpn.some(ps))

# a part without an MPN, when other parts have one
def Bom.r.mpn.each(ps: List<&2, Part>) -> List<&2, Fnd>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Bom.fnd.if(Bool.and(Bom.inbom(p), String.is_empty(Bom.mpn(p))), Fnd{"bom_missing_mpn", "warning", Bom.ref(p), "no MPN, though other parts have one"}, Bom.r.mpn.each(t))

def Bom.r.mpn.if(any: Bool, ps: List<&2, Part>) -> List<&2, Fnd>:
  match any:
    case True{}:
      Bom.r.mpn.each(ps)
    case False{}:
      Nil{}

def Bom.r.mpn(+ps: List<&2, Part>) -> List<&2, Fnd>:
  Bom.r.mpn.if(Bom.has.mpn(ps), ps)

# a reference twice (reported once), over the sorted parts
def Bom.r.dup.go(ps: List<&2, Part>, +last: String, rep: Bool) -> List<&2, Fnd>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Bom.fnd.if(Bool.and(String.eq(Bom.ref(p), last), Bool.not(rep)), Fnd{"bom_duplicate_ref", "error", Bom.ref(p), "reference used twice"}, Bom.r.dup.go(t, Bom.ref(p), String.eq(Bom.ref(p), last)))

def Bom.r.dup(ps: List<&2, Part>) -> List<&2, Fnd>:
  Bom.r.dup.go(Bom.sort(ps), "\0", False{})

# the MPN's run so far: its first footprint, whether another showed, its
# references, and the findings of the finished runs
type Rn is Data:
  Rn{mpn: String, fp: String, mixed: Bool, refs: List<&2, String>, out: List<&2, Fnd>}

def Bom.rn.msg(mpn: String, fp: String) -> String:
  String.join(["MPN", mpn, "is used with different footprints"], " ")

def Bom.rn.emit(refs: List<&2, String>, +mpn: String, rest: List<&2, Fnd>) -> List<&2, Fnd>:
  match refs:
    case Nil{}:
      rest
    case +r <> t:
      Fnd{"bom_mpn_footprint", "error", r, Bom.rn.msg(mpn, "")} <> Bom.rn.emit(t, mpn, rest)

def Bom.rn.flush.k(mixed: Bool, refs: List<&2, String>, mpn: String, out: List<&2, Fnd>) -> List<&2, Fnd>:
  match mixed:
    case True{}:
      Bom.rn.emit(refs, mpn, out)
    case False{}:
      out

def Bom.rn.flush(r: Rn) -> List<&2, Fnd>:
  match r:
    case Rn{mpn, _, mixed, refs, out}:
      Bom.rn.flush.k(mixed, refs, mpn, out)

def Bom.rn.same(same: Bool, +p: Part, r: Rn) -> Rn:
  match same:
    case True{}:
      match r:
        case Rn{m, +fp, mixed, refs, out}:
          Rn{m, fp, Bool.or(mixed, Bool.not(String.eq(fp, Bom.footprint(p)))), Bom.ref(p) <> refs, out}
    case False{}:
      Rn{Bom.mpn(p), Bom.footprint(p), False{}, [Bom.ref(p)], Bom.rn.flush(r)}

def Bom.rn.mpn(r: Rn) -> String:
  match r:
    case Rn{m, _, _, _, _}:
      m

def Bom.rn.step.k(none: Bool, same: Bool, p: Part, r: Rn) -> Rn:
  match none:
    case True{}:
      r
    case False{}:
      Bom.rn.same(same, p, r)

def Bom.rn.step(+r: Rn, +p: Part) -> Rn:
  Bom.rn.step.k(String.is_empty(Bom.mpn(p)), String.eq(Bom.mpn(p), Bom.rn.mpn(r)), p, r)

def Bom.rn.go(ps: List<&2, Part>, r: Rn) -> List<&2, Fnd>:
  match ps:
    case Nil{}:
      Bom.rn.flush(r)
    case +p <> t:
      Bom.rn.go(t, Bom.rn.step(r, p))

def Bom.mpn.le.k(+a: Part, +b: Part) -> Bool:
  Cmp.is_le(Bom.then(String.order(Bom.mpn(a), Bom.mpn(b)), Bom.cmp.part(a, b)))

def Bom.mpn.le(a: Part, b: Part) -> Bool:
  Bom.mpn.le.k(a, b)

# one MPN on parts of different footprints
def Bom.r.mpnfp(ps: List<&2, Part>) -> List<&2, Fnd>:
  Bom.rn.go(List.sort(~Part, ~Bom.mpn.le, Bom.uniq(Bom.sort(ps))), Rn{"", "", False{}, Nil{}, Nil{}})

# every finding of the design checks, over `Bom.parts`
def Bom.rules(+ps: List<&2, Part>) -> List<&2, Fnd>:
  List.concat(&2, Fnd, [Bom.r.dup(ps), Bom.r.unannotated(ps), Bom.r.footprint(ps), Bom.r.value(ps), Bom.r.mpn(ps), Bom.r.mpnfp(ps), Bom.r.dnp(ps)])

# Output
# ------

def Bom.nl() -> String:
  "\n"

def Bom.dq.k(quote: Bool, c: Char, rest: String) -> String:
  match quote:
    case True{}:
      SCon{c, SCon{c, rest}}
    case False{}:
      SCon{c, rest}

def Bom.dq(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+c, t}:
      Bom.dq.k(Char.is_eq(c, '"'), c, Bom.dq(t))

# a CSV cell: quoted when it holds a comma, a quote or a line break
def Bom.q.if(plain: Bool, s: String) -> String:
  match plain:
    case True{}:
      s
    case False{}:
      String.concat(["\"", Bom.dq(s), "\""])

def Bom.q(+s: String) -> String:
  Bom.q.if(Bool.not(Bool.or(Bool.or(String.contains(s, ","), String.contains(s, "\"")), Bool.or(String.contains(s, "\n"), String.contains(s, "\r")))), s)

def Bom.row.csv(l: Line) -> String:
  match l:
    case Line{_, q, v, f, m, mf, d}:
      String.concat([Bom.q(Bom.refs(l)), ",", Nat.show(q), ",", Bom.q(v), ",", Bom.q(f), ",", Bom.q(m), ",", Bom.q(mf), ",", Bom.yes.if(d), "\n"])

def Bom.rows.csv(ls: List<&2, Line>) -> String:
  match ls:
    case Nil{}:
      ""
    case l <> t:
      Bom.row.csv(l) ++ Bom.rows.csv(t)

# KiCad-ish CSV of a BOM's lines
def Bom.csv(ls: List<&2, Line>) -> String:
  "Reference,Qty,Value,Footprint,MPN,Manufacturer,DNP\n" ++ Bom.rows.csv(ls)

def Bom.c.if(pipe: Bool, nl: Bool, cr: Bool, c: Char, rest: String) -> String:
  match pipe nl cr:
    case True{} _ _:
      SCon{Char.from_u32(92), SCon{c, rest}}
    case _ True{} _:
      SCon{Char.from_u32(32), rest}
    case _ _ True{}:
      rest
    case _ _ _:
      SCon{c, rest}

def Bom.c.of(+x: U32, c: Char, rest: String) -> String:
  Bom.c.if(U32.is_eq(x, 124), U32.is_eq(x, 10), U32.is_eq(x, 13), c, rest)

def Bom.c.k(c: Char, rest: String) -> String:
  Bom.c.of(Char.to_u32(c), c, rest)

# a Markdown table cell: pipes escaped, line breaks flattened
def Bom.c(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+c, t}:
      Bom.c.k(c, Bom.c(t))

def Bom.cells(cs: List<&2, String>) -> String:
  match cs:
    case Nil{}:
      "|"
    case c <> t:
      "| " ++ Bom.c(c) ++ " " ++ Bom.cells(t)

def Bom.row.md(cs: List<&2, String>) -> String:
  Bom.cells(cs) ++ "\n"

def Bom.line.cells(l: Line) -> List<&2, String>:
  match l:
    case Line{_, q, v, f, m, mf, d}:
      [Bom.refs(l), Nat.show(q), v, f, m, mf, Bom.yes.if(d)]

def Bom.rows.md(ls: List<&2, Line>) -> String:
  match ls:
    case Nil{}:
      ""
    case l <> t:
      Bom.row.md(Bom.line.cells(l)) ++ Bom.rows.md(t)

# a BOM's lines as a GFM table
def Bom.md(ls: List<&2, Line>) -> String:
  Bom.row.md(["Reference", "Qty", "Value", "Footprint", "MPN", "Manufacturer", "DNP"]) ++ "| --- | --- | --- | --- | --- | --- | --- |\n" ++ Bom.rows.md(ls)

def Bom.line.k(total: Nat, a: Nat, r: Nat, c: Nat) -> String:
  match total:
    case 0n:
      "No changes"
    case _:
      String.concat([Nat.show(a), " added, ", Nat.show(r), " removed, ", Nat.show(c), " changed"])

# "3 added, 1 removed, 2 changed", or "No changes"
def Bom.line(a: Nat, r: Nat, c: Nat) -> String:
  Bom.line.k(Nat.add(a, Nat.add(r, c)), a, r, c)

def Bom.pick(was: Bool, w: String, n: String) -> String:
  match was:
    case True{}:
      w
    case False{}:
      n

def Bom.dls.if(none: Bool, s: String, rest: List<&2, String>) -> List<&2, String>:
  match none:
    case True{}:
      rest
    case False{}:
      s <> rest

def Bom.dls.k(+v: String, f: String, rest: List<&2, String>) -> List<&2, String>:
  Bom.dls.if(String.is_empty(v), String.concat([f, ": ", v]), rest)

def Bom.dls(ds: List<&2, Dl>, was: Bool) -> List<&2, String>:
  match ds:
    case Nil{}:
      Nil{}
    case Dl{f, w, n} <> t:
      Bom.dls.k(Bom.pick(was, w, n), f, Bom.dls(t, was))

def Bom.rows.chg(cs: List<&2, Chg>) -> String:
  match cs:
    case Nil{}:
      ""
    case Chg{r, k, ds} <> t:
      Bom.row.md([r, k, String.join(Bom.dls(ds, True{}), "; "), String.join(Bom.dls(ds, False{}), "; ")]) ++ Bom.rows.chg(t)

def Bom.rows.sum.k(same: Bool, p: String, w: Nat, n: Nat, rest: String) -> String:
  match same:
    case True{}:
      rest
    case False{}:
      Bom.row.md([p, Nat.show(w), Nat.show(n)]) ++ rest

def Bom.rows.sum(ss: List<&2, Sum>) -> String:
  match ss:
    case Nil{}:
      ""
    case Sum{p, w, n} <> t:
      Bom.rows.sum.k(Nat.is_eq(w, n), p, w, n, Bom.rows.sum(t))

def Bom.diff.table(cs: List<&2, Chg>) -> String:
  Bom.row.md(["Ref", "Change", "Was", "Now"]) ++ "| --- | --- | --- | --- |\n" ++ Bom.rows.chg(cs)

def Bom.sum.table(ss: List<&2, Sum>) -> String:
  Bom.row.md(["Part", "Was", "Now"]) ++ "| --- | --- | --- |\n" ++ Bom.rows.sum(ss)

def Bom.sum.n.k(same: Bool, rest: Nat) -> Nat:
  match same:
    case True{}:
      rest
    case False{}:
      Nat.add(rest, 1n)

# how many parts changed quantity
def Bom.sum.n(ss: List<&2, Sum>) -> Nat:
  match ss:
    case Nil{}:
      0n
    case Sum{_, w, n} <> t:
      Bom.sum.n.k(Nat.is_eq(w, n), Bom.sum.n(t))

def Bom.sum.any(ss: List<&2, Sum>) -> Bool:
  Bool.not(Nat.is_eq(Bom.sum.n(ss), 0n))

def Bom.diff.sum.md(ss: List<&2, Sum>, any: Bool) -> String:
  match any:
    case True{}:
      "\n" ++ Bom.sum.table(ss)
    case False{}:
      ""

def Bom.diff.md.k(cs: List<&2, Chg>, ss: List<&2, Sum>, any: Bool) -> String:
  match cs:
    case Nil{}:
      "No changes"
    case _:
      Bom.line(Bom.count("added", cs), Bom.count("removed", cs), Bom.count("changed", cs)) ++ "\n\n" ++ Bom.diff.table(cs) ++ Bom.diff.sum.md(ss, any)

# a diff as Markdown: the summary line, the changes by reference, and the
# parts whose quantity moved
def Bom.diff.md(old: List<&2, Part>, new: List<&2, Part>) -> String:
  Bom.diff.md.k(Bom.diff(old, new), Bom.summary(old, new), Bom.sum.any(Bom.summary(old, new)))

# Small helpers for the laws
# --------------------------

def Bom.mk(ref: String, value: String, footprint: String) -> Part:
  Part{ref, value, footprint, "", "", Nil{}, False{}, True{}, "", "", 1n}

# three parts out of order, two alike
def Bom.sample() -> List<&2, Part>:
  [Bom.mk("R2", "10k", "0603"), Bom.mk("R1", "10k", "0603"), Bom.mk("C1", "1u", "0402")]

def Bom.line.qty(l: Line) -> Nat:
  match l:
    case Line{_, q, _, _, _, _, _}:
      q

def Bom.line.n(l: Line) -> Nat:
  match l:
    case Line{rs, _, _, _, _, _, _}:
      List.length(&2, String, rs)

# every line's quantity is the number of its references
def Bom.qty.ok(ls: List<&2, Line>) -> Bool:
  match ls:
    case Nil{}:
      True{}
    case +l <> t:
      Bool.and(Nat.is_eq(Bom.line.qty(l), Bom.line.n(l)), Bom.qty.ok(t))
