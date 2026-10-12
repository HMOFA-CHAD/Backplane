import Base
import ./check.bend as C
import ../src/core/bom.bend as B
import ../src/core/utf8.bend as U

# placed symbols as a KiCad 8/9 schematic writes them
def symu(+lib: String, +ref: String, +value: String, +fp: String, +extra: String, +flags: String, +inst: String, +unit: String) -> String:
  "(symbol (lib_id \"" ++ lib ++ "\") (at 10 10 0) (unit " ++ unit ++ ") " ++ flags ++ " (uuid \"u-" ++ ref ++ "\") (property \"Reference\" \"" ++ ref ++ "\" (at 0 0 0) (effects (font (size 1 1)))) (property \"Value\" \"" ++ value ++ "\" (at 0 0 0)) (property \"Footprint\" \"" ++ fp ++ "\" (at 0 0 0) (effects (hide yes))) (property \"Datasheet\" \"~\" (at 0 0 0)) " ++ extra ++ inst ++ ")\n"

def sym(+lib: String, +ref: String, +value: String, +fp: String, +extra: String, +flags: String, +inst: String) -> String:
  symu(lib, ref, value, fp, extra, flags, inst, "1")

def flags(dnp: String) -> String:
  "(exclude_from_sim no) (in_bom yes) (on_board yes) (dnp " ++ dnp ++ ")"

def prop(+k: String, +v: String) -> String:
  "(property \"" ++ k ++ "\" \"" ++ v ++ "\" (at 0 0 0)) "

def r(+ref: String, +value: String, +extra: String, +dnp: String) -> String:
  sym("Device:R", ref, value, "Resistor_SMD:R_0603", extra, flags(dnp), "")

def file(+body: String) -> String:
  "(kicad_sch (version 20250114) (generator \"eeschema\") (uuid \"root\") (lib_symbols (symbol \"Device:R\" (property \"Reference\" \"R\" (at 0 0 0)) (symbol \"R_0_1\" (rectangle (start 0 0) (end 1 1))))) " ++ body ++ " (sheet_instances (path \"/\" (page \"1\"))))\n"

def sheet(+path: String, +body: String) -> B.Sheet:
  B.Sheet{path, U.Utf8.encode(file(body))}

def u1() -> String:
  sym("MCU:Dual", "U1", "OPA2", "Package_SO:SOIC-8", prop("MPN", "OPA2134"), flags("no"), "") ++ symu("MCU:Dual", "U1", "OPA2", "Package_SO:SOIC-8", prop("MPN", "OPA2134"), flags("no"), "", "2")

def pwr() -> String:
  sym("power:GND", "#PWR01", "GND", "", "", flags("no"), "") ++ sym("Device:R", "#FLG02", "X", "", "", flags("no"), "")

# version one
def v1() -> String:
  r("R10", "22k", prop("MPN", "RC-B"), "no") ++ r("R2", "10k", prop("MPN", "RC-A"), "no") ++ r("R1", "10k", prop("mpn", "RC-A"), "no")
    ++ sym("Device:C", "C1", "100n", "Capacitor_SMD:C_0402", "", flags("no"), "")
    ++ sym("Device:LED", "D1", "LED", "LED_SMD:LED_0603", prop("Manufacturer", "Acme") ++ prop("Datasheet", "x"), flags("no"), "")
    ++ u1() ++ pwr()

# version two: R1 changed, R10 DNP, C1 gone, C2 added, D1 gains an LCSC field
def v2() -> String:
  r("R10", "22k", prop("MPN", "RC-B"), "yes") ++ r("R2", "10k", prop("MPN", "RC-A"), "no") ++ r("R1", "4k7", prop("MPN", "RC-C"), "no")
    ++ sym("Device:C", "C2", "1u", "Capacitor_SMD:C_0603", "", flags("no"), "")
    ++ sym("Device:LED", "D1", "LED", "LED_SMD:LED_0603", prop("Manufacturer", "Acme") ++ prop("LCSC", "C2286"), flags("no"), "")
    ++ u1() ++ pwr()

def is_u1(p: B.Part) -> Bool:
  String.eq(B.Bom.ref(p), "U1")

def yn(b: Bool) -> String:
  B.Bom.yes(b)

def p1() -> List<&2, B.Part>:
  B.Bom.parts("", [sheet("a.kicad_sch", v1())])

def p2() -> List<&2, B.Part>:
  B.Bom.parts("", [sheet("a.kicad_sch", v2())])

def refs(+ps: List<&2, B.Part>) -> String:
  match ps:
    case Nil{}:
      ""
    case +p <> t:
      B.Bom.ref(p) ++ " " ++ refs(t)

def vals(+ps: List<&2, B.Part>) -> String:
  match ps:
    case Nil{}:
      ""
    case +p <> t:
      B.Bom.ref(p) ++ "=" ++ B.Bom.value(p) ++ "/" ++ B.Bom.mpn(p) ++ "/" ++ B.Bom.mfr(p) ++ " " ++ vals(t)

def dls(+ds: List<&2, B.Dl>) -> String:
  match ds:
    case Nil{}:
      ""
    case B.Dl{+f, +w, +n} <> t:
      f ++ "[" ++ w ++ ">" ++ n ++ "]" ++ dls(t)

def chg(+cs: List<&2, B.Chg>) -> String:
  match cs:
    case Nil{}:
      ""
    case B.Chg{+r, +k, ds} <> t:
      r ++ ":" ++ k ++ ":" ++ dls(ds) ++ " " ++ chg(t)

def sums(+ss: List<&2, B.Sum>) -> String:
  match ss:
    case Nil{}:
      ""
    case B.Sum{+p, +w, +n} <> t:
      p ++ ":" ++ Nat.show(w) ++ ">" ++ Nat.show(n) ++ " " ++ sums(t)

def fnds(+fs: List<&2, B.Fnd>) -> String:
  match fs:
    case Nil{}:
      ""
    case B.Fnd{+i, +s, +r, _} <> t:
      i ++ "/" ++ s ++ "/" ++ r ++ " " ++ fnds(t)

# a sheet used twice: instances give each reference
def multi() -> String:
  sym("Device:R_Potentiometer", "RV?", "10k", "Potentiometer_THT:Pot", "", flags("no"), "(instances (project \"main\" (path \"/a/b\" (reference \"RV201\") (unit 1)) (path \"/a/c\" (reference \"RV301\") (unit 1))) (project \"old\" (path \"/z\" (reference \"RV9\") (unit 1))))")

def dup() -> String:
  r("R1", "1k", "", "no") ++ r("R1", "2k", "", "no") ++ r("R4?", "", "", "no") ++ r("R5", "1k", prop("MPN", "X1"), "yes") ++ sym("Device:R", "R6", "1k", "Resistor_SMD:R_0402", prop("MPN", "X1"), flags("no"), "")

def main() -> IO(Unit):
  +d = B.Bom.diff(p1(), p2())
  +dd = B.Bom.diff(p1(), p1())
  +mp = B.Bom.parts("main", [sheet("m.kicad_sch", multi())])
  +ma = B.Bom.parts("", [sheet("m.kicad_sch", multi())])
  +dp = B.Bom.parts("", [sheet("d.kicad_sch", dup())])
  +both = B.Bom.parts("", [sheet("a.kicad_sch", r("R1", "1k", "", "no")), sheet("b.kicad_sch", r("R2", "1k", "", "no"))])
  +hole = B.Bom.parts("", [sheet("h.kicad_sch", sym("Mech:Hole", "H1", "M3", "", "", "(in_bom no) (dnp no)", "") ++ r("R1", "1k", "", "no"))])
  do IO<Unit>:
    C.Check.str("in_bom no is left out", refs(hole), "R1 ")
    C.Check.str("natural order", refs(p1()), "C1 D1 R1 R2 R10 U1 ")
    C.Check.str("power symbols skipped", refs(p1()), "C1 D1 R1 R2 R10 U1 ")
    C.Check.str("fields", vals(p1()), "C1=100n// D1=LED//Acme R1=10k/RC-A/ R2=10k/RC-A/ R10=22k/RC-B/ U1=OPA2/OPA2134/ ")
    C.Check.str("multi-unit once", Nat.show(List.length(&2, B.Part, List.filter(~B.Part, ~is_u1, p1()))), "1")
    C.Check.str("project filter", refs(mp), "RV201 RV301 ")
    C.Check.str("no project: every instance", refs(ma), "RV9 RV201 RV301 ")
    C.Check.str("sheets together", refs(both), "R1 R2 ")
    C.Check.str("cmp C2 C10", yn(B.Bom.before("C2", "C10")), "yes")
    C.Check.str("cmp R10 R2", yn(B.Bom.before("R10", "R2")), "no")
    C.Check.str("cmp same prefix first", yn(B.Bom.before("C9", "R1")), "yes")
    C.Check.str("group", B.Bom.csv(B.Bom.group(p1())), "Reference,Qty,Value,Footprint,MPN,Manufacturer,DNP\nC1,1,100n,Capacitor_SMD:C_0402,,,\nD1,1,LED,LED_SMD:LED_0603,,Acme,\n\"R1, R2\",2,10k,Resistor_SMD:R_0603,RC-A,,\nR10,1,22k,Resistor_SMD:R_0603,RC-B,,\nU1,1,OPA2,Package_SO:SOIC-8,OPA2134,,\n")
    C.Check.str("quote", B.Bom.q("a,b"), "\"a,b\"")
    C.Check.str("quote doubles quotes", B.Bom.q("5\" tall"), "\"5\"\" tall\"")
    C.Check.str("plain cell", B.Bom.q("10k"), "10k")
    C.Check.str("md", B.Bom.md(B.Bom.group(p2())), "| Reference | Qty | Value | Footprint | MPN | Manufacturer | DNP |\n| --- | --- | --- | --- | --- | --- | --- |\n| C2 | 1 | 1u | Capacitor_SMD:C_0603 |  |  |  |\n| D1 | 1 | LED | LED_SMD:LED_0603 |  | Acme |  |\n| R1 | 1 | 4k7 | Resistor_SMD:R_0603 | RC-C |  |  |\n| R2 | 1 | 10k | Resistor_SMD:R_0603 | RC-A |  |  |\n| R10 | 1 | 22k | Resistor_SMD:R_0603 | RC-B |  | yes |\n| U1 | 1 | OPA2 | Package_SO:SOIC-8 | OPA2134 |  |  |\n")
    C.Check.str("md escapes pipes", B.Bom.c("a|b"), "a\\|b")
    C.Check.str("diff self", chg(dd), "")
    C.Check.str("diff", chg(d), "C1:removed:value[100n>]footprint[Capacitor_SMD:C_0402>] C2:added:value[>1u]footprint[>Capacitor_SMD:C_0603] D1:changed:LCSC[>C2286] R1:changed:value[10k>4k7]mpn[RC-A>RC-C] R10:changed:dnp[no>yes] ")
    C.Check.str("diff line", B.Bom.line(B.Bom.count("added", d), B.Bom.count("removed", d), B.Bom.count("changed", d)), "1 added, 1 removed, 3 changed")
    C.Check.str("summary", sums(B.Bom.summary(p1(), p2())), "100n Capacitor_SMD:C_0402:1>0 1u Capacitor_SMD:C_0603:0>1 LED LED_SMD:LED_0603:1>1 OPA2134:1>1 RC-A:2>1 RC-B:1>1 RC-C:0>1 ")
    C.Check.str("diff md", B.Bom.diff.md(p1(), p2()), "1 added, 1 removed, 3 changed\n\n| Ref | Change | Was | Now |\n| --- | --- | --- | --- |\n| C1 | removed | value: 100n; footprint: Capacitor_SMD:C_0402 |  |\n| C2 | added |  | value: 1u; footprint: Capacitor_SMD:C_0603 |\n| D1 | changed |  | LCSC: C2286 |\n| R1 | changed | value: 10k; mpn: RC-A | value: 4k7; mpn: RC-C |\n| R10 | changed | dnp: no | dnp: yes |\n\n| Part | Was | Now |\n| --- | --- | --- |\n| 100n Capacitor_SMD:C_0402 | 1 | 0 |\n| 1u Capacitor_SMD:C_0603 | 0 | 1 |\n| RC-A | 2 | 1 |\n| RC-C | 0 | 1 |\n")
    C.Check.str("diff md of no change", B.Bom.diff.md(p1(), p1()), "No changes")
    C.Check.str("rules", fnds(B.Bom.rules(dp)), "bom_duplicate_ref/error/R1 bom_unannotated/error/R4? bom_missing_value/warning/R4? bom_missing_mpn/warning/R1 bom_missing_mpn/warning/R1 bom_missing_mpn/warning/R4? bom_mpn_footprint/error/R6 bom_mpn_footprint/error/R5 bom_dnp_in_bom/warning/R5 ")
    C.Check.str("rules: partial MPN", fnds(B.Bom.rules(p1())), "bom_missing_mpn/warning/C1 bom_missing_mpn/warning/D1 ")
    C.Check.str("rules: no MPN anywhere, no rule", fnds(B.Bom.rules(both)), "")
