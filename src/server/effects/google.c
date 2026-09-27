// The Google OAuth client baked in at build time: scripts/build-app.sh
// writes bp_google.h beside the compile units from a git-ignored .env (or
// the build's environment). Without it every value is "" and Backplane's
// own G.Google.shared (or Own client) is used.

#if __has_include("bp_google.h")
#include "bp_google.h"
#endif
#ifndef BP_GOOGLE_CLIENT_ID
#define BP_GOOGLE_CLIENT_ID ""
#endif
#ifndef BP_GOOGLE_CLIENT_SECRET
#define BP_GOOGLE_CLIENT_SECRET ""
#endif

#include <stdlib.h>
#include <string.h>

#ifdef CID_GF_BAKED

Term gf_baked_run(Env e, Term* f, IoWork* w) {
  u64 len = 0;
  char* name = io_cstr(e, f[0], &len);
  const char* v = "";
  if (strcmp(name, "BACKPLANE_GOOGLE_CLIENT_ID") == 0) {
    v = BP_GOOGLE_CLIENT_ID;
  } else if (strcmp(name, "BACKPLANE_GOOGLE_CLIENT_SECRET") == 0) {
    v = BP_GOOGLE_CLIENT_SECRET;
  }
  free(name);
  return io_str(e, v, strlen(v));
}

static void __attribute__((constructor)) gf_baked_use(void) {
  io_eff(CID_GF_BAKED, gf_baked_run, 0);
}

#endif
