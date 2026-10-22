// The native runtime's own loop: loop.js's twin, which swaps the JS
// runtime onto Bun's event loop, answers "bun" or "sync" there.

#include <string.h>

#ifdef CID(Rt.loop)

Term rt_loop_run(Env e, Term* f, IoWork* w) {
  return io_str(e, "c", 1);
}

static void __attribute__((constructor)) rt_loop_use(void) {
  io_eff(CID(Rt.loop), rt_loop_run);
}

#endif
