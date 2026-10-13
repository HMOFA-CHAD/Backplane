# Sourced by the scripts: the verdict on a `bend F --check-only` or `bend PROOF.bend` run.
# Bend 2.0.36 prints "ALL PROOFS CHECK", or, for a program that relies on
# foreign (C/JS effect) code, "SOME PROOFS FAIL" with "N defs rely on unsafe
# or foreign code:" and a list, and exits 1 even though everything checked.
#
#   bend_verdict STATUS OUTPUT   0 only for: status 0 with a success line, or
#                                status 1 with that foreign-code notice and no
#                                other line. A checker killed before it printed
#                                anything, or any other output, is a failure.
#   bend_check FILE              --check-only, print the report unless it passes.
_bend_clean() {
  _rest=$(printf '%s\n' "$1" | grep -v -E '^(All terms check\.?|ALL PROOFS CHECK|Use --verdict.*|SOME PROOFS FAIL|Error: [0-9]+ defs? (relies|rely) on unsafe or foreign code:|- [^ ]+|)$' || true)
  [ -z "$_rest" ]
}
bend_verdict() {
  case $2 in
    *"All terms check"*|*"ALL PROOFS CHECK"*) [ "$1" = 0 ] && _bend_clean "$2" ;;
    *"SOME PROOFS FAIL"*)
      [ "$1" = 1 ] || return 1
      case $2 in *"on unsafe or foreign code"*) _bend_clean "$2" ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
}
bend_check() {
  _rc=0
  _out=$(bend "$1" --check-only 2>&1) || _rc=$?
  bend_verdict "$_rc" "$_out" || { echo "$1 (status $_rc):"; echo "$_out"; return 1; }
}
