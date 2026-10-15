// Which clients show which browser page (src/server/castio.bend): a client
// showing a page's Browser tab says so (browser.seen) about every second;
// the hub sends it every frame of that page, and every other client only
// the frames marked "all" (at most --jpeg-fps a second). Kept here, by
// client and page with the monotonic time, not in the hub's state: it is
// only ever asked "who saw this page in the last few seconds".
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if defined(CID(Cast.seen)) || defined(CID(Cast.to))

typedef struct bp_cast { unsigned client; char *page; unsigned long long at; struct bp_cast *next; } bp_cast;
static bp_cast *bp_casts;
// the last time each page's lease was renewed at the helper
typedef struct bp_lease { char *page; unsigned long long at; struct bp_lease *next; } bp_lease;
static bp_lease *bp_leases;

static unsigned long long bp_cast_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (unsigned long long)ts.tv_sec * 1000ull + (unsigned long long)ts.tv_nsec / 1000000ull;
}

// how long a client counts as showing a page after it said so
#define BP_CAST_HOLD 3000ull

static void bp_cast_prune(unsigned long long now) {
  bp_cast **at = &bp_casts;
  while (*at) {
    bp_cast *c = *at;
    if (now - c->at > BP_CAST_HOLD) { *at = c->next; free(c->page); free(c); } else at = &c->next;
  }
}

#endif

#ifdef CID(Cast.seen)
// client shows page now; answers whether the helper's lease is due again
// (none renewed for the page in the last second)
Term cast_seen_run(Env e, Term* f, IoWork* w) {
  unsigned client = (unsigned)(uint32_t)f[0];
  u64 len = 0;
  char *page = io_cstr(e, f[1], &len);
  unsigned long long now = bp_cast_ms();
  bp_cast_prune(now);
  bp_cast *c = bp_casts;
  for (; c; c = c->next) if (c->client == client && !strcmp(c->page, page)) break;
  if (c) c->at = now;
  else {
    c = calloc(1, sizeof *c);
    if (c) { c->client = client; c->page = strdup(page); c->at = now; c->next = bp_casts; bp_casts = c; }
  }
  bp_lease *l = bp_leases;
  for (; l; l = l->next) if (!strcmp(l->page, page)) break;
  int due = 0;
  if (!l) {
    l = calloc(1, sizeof *l);
    if (l) { l->page = strdup(page); l->at = now; l->next = bp_leases; bp_leases = l; due = 1; }
  } else if (now - l->at >= 1000ull) { l->at = now; due = 1; }
  free(page);
  return term_pak(due ? CID(True) : CID(False), 0);
}
static void __attribute__((constructor)) cast_seen_use(void) { io_eff(CID(Cast.seen), cast_seen_run); }
#endif

#ifdef CID(Cast.to)
// the clients that showed page in the last few seconds
Term cast_to_run(Env e, Term* f, IoWork* w) {
  u64 len = 0;
  char *page = io_cstr(e, f[0], &len);
  bp_cast_prune(bp_cast_ms());
  Term xs = term_pak(CID_NIL, 0);
  for (bp_cast *c = bp_casts; c; c = c->next) if (!strcmp(c->page, page)) xs = io_node(e, CID_CON, (Term)(uint32_t)c->client, xs);
  free(page);
  return xs;
}
static void __attribute__((constructor)) cast_to_use(void) { io_eff(CID(Cast.to), cast_to_run); }
#endif
