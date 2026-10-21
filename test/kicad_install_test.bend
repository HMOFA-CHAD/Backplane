import Base
import ./check.bend as C
import ../src/core/kicad_install.bend as K

def identity(p: Maybe<&2, K.Package>) -> String:
  match p:
    case Some{K.Package{os, v, _, a, _, f, cli}}: os ++ "/" ++ v ++ "/" ++ a ++ "/" ++ f ++ "/" ++ cli
    case None{}: "unsupported"

def platform.of(p: Maybe<&2, K.Package>) -> String:
  match p:
    case Some{K.Package{p, _, _, _, _, _, _}}: p
    case None{}: "unsupported"

def platform(s: String) -> String:
  platform.of(K.Install.platform(s))

def can(s: String) -> String:
  Bool.pick(String, K.Install.available(K.Install.platform(s)), "yes", "no")

def digest(p: K.Package) -> String:
  match p:
    case K.Package{_, _, _, _, s, _, _}: s

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("Linux keeps bp4 tar", identity(K.Install.platform("Linux x86_64")), "linux-x86_64/10.99.0-bp.4/backplane-kicad-linux-x86_64-10.99.0-bp.4.tar.gz/tar.gz/bin/kicad-cli")
    C.Check.str("Linux pin unchanged", digest(K.Install.linux()), "f60a71817d057f9dcf3faef632b2f85d06a613108dee23807c9de81aae97e0b4")
    C.Check.str("Darwin arm64 tar", identity(K.Install.platform("Darwin arm64")), "darwin-arm64/10.99.0-bp.6/backplane-kicad-darwin-arm64-10.99.0-bp.6.tar.gz/tar.gz/bin/kicad-cli")
    C.Check.str("Darwin pin", digest(K.Install.mac()), "99584fb0ee490354098778d39e3aaed9e0f274ee39972851a9cbeabfb271462d")
    C.Check.str("real Cygwin uname selects Windows ZIP", identity(K.Install.platform("CYGWIN_NT-10.0-26300 x86_64")), "windows-x86_64/10.99.0-bp.6/backplane-kicad-windows-x86_64-10.99.0-bp.6.zip/zip/bin/kicad-cli.exe")
    C.Check.str("Windows published pin", digest(K.Install.windows()), "55f84153c3ba6f9a8e7e005558a02b9c2fa72dd5deeed0211f908336c830870c")
    C.Check.str("Windows architecture alias", platform("Windows_NT AMD64"), "windows-x86_64")
    C.Check.str("MSYS alias", platform("MSYS_NT-10.0-26300 x64"), "windows-x86_64")
    C.Check.str("MINGW alias", platform("MINGW64_NT-10.0 x86_64"), "windows-x86_64")
    C.Check.str("Darwin architecture alias", platform("Darwin aarch64"), "darwin-arm64")
    C.Check.str("whitespace and case", platform("  LINUX   AMD64\n"), "linux-x86_64")
    C.Check.str("Linux arm64 unavailable", can("Linux aarch64"), "no")
    C.Check.str("Darwin x64 unavailable", can("Darwin x86_64"), "no")
    C.Check.str("Windows arm64 unavailable", can("CYGWIN_NT-10.0 arm64"), "no")
    C.Check.str("unknown OS unavailable", can("FreeBSD x86_64"), "no")
    C.Check.str("missing arch unavailable", can("Linux"), "no")
    C.Check.str("failed uname unavailable", can(""), "no")
    C.Check.str("extra uname words unavailable", can("Linux x86_64 unexpected"), "no")
    C.Check.str("can_install Windows", can("CYGWIN_NT-10.0 x86_64"), "yes")
    C.Check.str("can_install Mac", can("Darwin arm64"), "yes")
    C.Check.str("Windows discover exact exe", K.Install.installed(K.Install.platform("CYGWIN_NT-10.0 x86_64")), "10.99.0-bp.6/bin/kicad-cli.exe")
    C.Check.str("Mac discover selected version", K.Install.installed(K.Install.platform("Darwin arm64")), "10.99.0-bp.6/bin/kicad-cli")
