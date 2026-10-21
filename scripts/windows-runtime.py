#!/usr/bin/env python3
"""Prepare pinned Bend C for the Windows Cygwin target.

Windows x64 passes Env (two machine words) indirectly. Bend's musttail
segments reuse that argument after the caller's frame is gone. Use SysV
for the internal functions marked PRESERVE and their matching function
pointers: Env then travels in registers. Foreign/Win32 functions retain
Windows' normal ABI. This changes no Bend terms or laws.
"""
from pathlib import Path
import re
import sys

source, output = map(Path, sys.argv[1:])
text = source.read_text()
pattern = r"(?m)^#define PRESERVE\(A\)[^\n]*$"
if len(re.findall(pattern, text)) != 2:
    sys.exit("windows-runtime: pinned Bend PRESERVE declarations changed")
text = re.sub(pattern, "#define PRESERVE(A) __attribute__((sysv_abi))", text)
# Base's process effect includes this Linux-only header outside its syscall
# feature guards. Cygwin has the portable POSIX fallback used below them.
text = text.replace("#include <sys/syscall.h>", "#if defined(__linux__)\n#include <sys/syscall.h>\n#endif")
# Base only selects getrandom on non-Apple hosts. Use Windows' system RNG
# without modifying the pinned compiler installation.
random_call = "  io_sys_end(w, getrandom(&w->word, sizeof(w->word), 0));"
if random_call in text:
    if text.count(random_call) != 1:
        sys.exit("windows-runtime: pinned Bend random effect changed")
    text = text.replace(random_call, """#ifdef __CYGWIN__
  w->code = BCryptGenRandom(NULL, (PUCHAR)&w->word, sizeof(w->word),
                           BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0 ? 0 : EIO;
#else
""" + random_call + "\n#endif")
    text = text.replace("#include <sys/random.h>\n#endif",
                        "#include <sys/random.h>\n#elif defined(__CYGWIN__)\n#include <windows.h>\n#include <bcrypt.h>\n#endif")
# Base 2.0.36 uses glibc's closefrom spawn action for process.run. Cygwin
# lacks that extension. Its fixed hard RLIMIT_NOFILE/OPEN_MAX covers every
# possible descriptor, so queue supported close actions for the entire range,
# including holes and descriptors opened after action preparation. Do not
# enumerate currently-open descriptors: other IO workers may open more.
process_close = "    p->code = posix_spawn_file_actions_addclosefrom_np(&actions, 3);"
process_marker = "static void process_call(IoWork* w) {"
if process_close in text:
    if text.count(process_close) != 1 or text.count(process_marker) != 1:
        sys.exit("windows-runtime: pinned Bend process closefrom changed")
    close_helper = r"""#ifdef __CYGWIN__
#include <spawn.h>
#include <sys/resource.h>
#include <limits.h>
#include <errno.h>
static int bp_cygwin_spawn_addclosefrom(posix_spawn_file_actions_t *actions,
                                       int from) {
  struct rlimit limit;
  if (from < 0) return EBADF;
  if (getrlimit(RLIMIT_NOFILE, &limit) != 0) return errno;
  // Cygwin's descriptor table cannot grow beyond OPEN_MAX. Reject a runtime
  // whose hard bound differs from the headers, rather than leak descriptors.
  if (limit.rlim_max != (rlim_t)OPEN_MAX) return ENOTSUP;
  for (int fd = from; fd < OPEN_MAX; ++fd) {
    int code = posix_spawn_file_actions_addclose(actions, fd);
    if (code != 0) return code;
  }
  return 0;
}
#endif
"""
    text = text.replace(process_marker, close_helper + "\n" + process_marker)
    text = text.replace(process_close, "#ifdef __CYGWIN__\n"
                        "    p->code = bp_cygwin_spawn_addclosefrom(&actions, 3);\n"
                        "#else\n" + process_close + "\n#endif")
output.write_text(text)
