// Agents kept through a restart in place (src/server/adopt.bend; the
// decisions are src/core/adopt.bend's). A record of every Claude process
// the hub started: thread, pid, start identity (boot id and the process's
// start time, /proc/<pid>/stat field 22, so a pid reused by another
// process never matches) and a descriptor on its socket, kept in memory
// and written to the record file on each change. Before an exec the
// descriptors lose FD_CLOEXEC (bp_adopt_exec, called by host.c's
// Sys.exec), so the new image can read and write the same processes.
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#if defined(CID(Adopt.record)) || defined(CID(Adopt.keep)) || defined(CID(Adopt.drop)) || defined(CID(Adopt.ident)) || defined(CID(Adopt.take)) || defined(CID(Adopt.stop))

typedef struct bp_adopt { char *thread; unsigned pid; char ident[96]; int fd; struct bp_adopt *next; } bp_adopt;
static bp_adopt *bp_adopts;
static char bp_adopt_path[4096];

// boot id and start time ("" when the process is gone or unreadable)
static void bp_adopt_ident(unsigned pid, char *out, size_t cap) {
  out[0] = 0;
  if (pid <= 1) return;
  char path[64], buf[4096], boot[64] = "";
  snprintf(path, sizeof path, "/proc/%u/stat", pid);
  FILE *f = fopen(path, "re");
  if (!f) return;
  size_t n = fread(buf, 1, sizeof buf - 1, f);
  fclose(f);
  buf[n] = 0;
  char *p = strrchr(buf, ')');
  if (!p) return;
  // after "comm)": field 3 (state) onwards; start time is field 22
  int field = 2;
  char *start = NULL;
  for (char *q = p + 1; *q; q++) {
    if (*q == ' ') {
      field++;
      if (field == 22) { start = q + 1; break; }
    }
  }
  if (!start) return;
  char *end = start;
  while (*end >= '0' && *end <= '9') end++;
  if (end == start) return;
  FILE *b = fopen("/proc/sys/kernel/random/boot_id", "re");
  if (b) {
    if (fgets(boot, sizeof boot, b)) boot[strcspn(boot, "\n")] = 0;
    fclose(b);
  }
  snprintf(out, cap, "%s:%.*s", boot, (int)(end - start), start);
}

static void bp_adopt_write(void) {
  if (!bp_adopt_path[0]) return;
  char tmp[4200];
  snprintf(tmp, sizeof tmp, "%s.tmp", bp_adopt_path);
  FILE *f = fopen(tmp, "we");
  if (!f) return;
  for (bp_adopt *a = bp_adopts; a; a = a->next) fprintf(f, "%s\t%u\t%s\t%d\n", a->thread, a->pid, a->ident, a->fd);
  fclose(f);
  rename(tmp, bp_adopt_path);
}

static void bp_adopt_remove(const char *thread, unsigned pid, int any) {
  bp_adopt **at = &bp_adopts;
  while (*at) {
    bp_adopt *a = *at;
    if (!strcmp(a->thread, thread) && (any || a->pid == pid)) {
      *at = a->next;
      if (a->fd > 2) close(a->fd);
      free(a->thread);
      free(a);
    } else {
      at = &a->next;
    }
  }
}

#endif

// Before an exec (keep 1) each recorded descriptor survives it; after an
// exec that failed (keep 0) they are close-on-exec again. host.c calls it
// through a weak reference, so a program without this file still links.
void bp_adopt_exec(int keep) {
#if defined(CID(Adopt.record)) || defined(CID(Adopt.keep)) || defined(CID(Adopt.drop)) || defined(CID(Adopt.ident)) || defined(CID(Adopt.take)) || defined(CID(Adopt.stop))
  for (bp_adopt *a = bp_adopts; a; a = a->next) {
    if (a->fd > 2) fcntl(a->fd, F_SETFD, keep ? 0 : FD_CLOEXEC);
  }
  if (keep) bp_adopt_write();
#endif
}

#ifdef CID(Adopt.record)
// the record's file; the record starts empty (and is written so)
Term adopt_record_run(Env e, Term* f, IoWork* w) {
  u64 len = 0;
  char *path = io_cstr(e, f[0], &len);
  snprintf(bp_adopt_path, sizeof bp_adopt_path, "%s", path);
  free(path);
  while (bp_adopts) bp_adopt_remove(bp_adopts->thread, 0, 1);
  bp_adopt_write();
  return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) adopt_record_use(void) { io_eff(CID(Adopt.record), adopt_record_run); }
#endif

#ifdef CID(Adopt.keep)
// a process the hub started for a thread: recorded with a descriptor of
// its own on the socket (close-on-exec until an exec keeps it); an
// earlier one for the thread leaves the record
Term adopt_keep_run(Env e, Term* f, IoWork* w) {
  u64 len = 0;
  char *thread = io_cstr(e, f[0], &len);
  unsigned pid = (unsigned)(uint32_t)f[1];
  int fd = (int)io_hand_v(f[2]);
  bp_adopt_remove(thread, 0, 1);
  int got = fcntl(fd, F_DUPFD_CLOEXEC, 3);
  bp_adopt *a = calloc(1, sizeof *a);
  if (a && pid > 1) {
    a->thread = thread;
    a->pid = pid;
    a->fd = got;
    bp_adopt_ident(pid, a->ident, sizeof a->ident);
    a->next = bp_adopts;
    bp_adopts = a;
  } else {
    if (got > 2) close(got);
    free(a);
    free(thread);
  }
  bp_adopt_write();
  return io_hand(fd);
}
static void __attribute__((constructor)) adopt_keep_use(void) { io_eff(CID(Adopt.keep), adopt_keep_run); }
#endif

#ifdef CID(Adopt.drop)
// the process ended: its entry goes (only if it is still that pid's)
Term adopt_drop_run(Env e, Term* f, IoWork* w) {
  u64 len = 0;
  char *thread = io_cstr(e, f[0], &len);
  bp_adopt_remove(thread, (unsigned)(uint32_t)f[1], 0);
  free(thread);
  bp_adopt_write();
  return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) adopt_drop_use(void) { io_eff(CID(Adopt.drop), adopt_drop_run); }
#endif

#ifdef CID(Adopt.ident)
Term adopt_ident_run(Env e, Term* f, IoWork* w) {
  char id[96];
  bp_adopt_ident((unsigned)(uint32_t)f[0], id, sizeof id);
  return io_str(e, id, strlen(id));
}
static void __attribute__((constructor)) adopt_ident_use(void) { io_eff(CID(Adopt.ident), adopt_ident_run); }
#endif

#ifdef CID(Adopt.take)
// a descriptor an exec kept: a socket again (close-on-exec, non-blocking),
// or an error when it is no socket
Term adopt_take_run(Env e, Term* f, IoWork* w) {
  int fd = (int)(uint32_t)f[0];
  struct stat sb;
  if (fd <= 2 || fstat(fd, &sb) < 0 || !S_ISSOCK(sb.st_mode)) return io_fail(e, EBADF, NULL);
  fcntl(fd, F_SETFD, FD_CLOEXEC);
  fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
  return io_done(e, io_hand(fd));
}
static void __attribute__((constructor)) adopt_take_use(void) { io_eff(CID(Adopt.take), adopt_take_run); }
#endif

#ifdef CID(Adopt.stop)
// whether pid is this process or one of its ancestors
static int bp_adopt_ancestor(unsigned pid) {
  unsigned p = (unsigned)getpid();
  for (int depth = 0; depth < 64 && p > 1; depth++) {
    if (p == pid) return 1;
    char path[64], buf[4096];
    snprintf(path, sizeof path, "/proc/%u/stat", p);
    FILE *f = fopen(path, "re");
    if (!f) return 0;
    size_t n = fread(buf, 1, sizeof buf - 1, f);
    fclose(f);
    buf[n] = 0;
    char *q = strrchr(buf, ')');
    unsigned pp = 0;
    if (!q || sscanf(q + 1, " %*c %u", &pp) != 1) return 0;
    p = pp;
  }
  return p == pid;
}

// SIGTERM to pid, only when it is still the process recorded (same start
// identity), never 0 or 1, this process or an ancestor; answers whether
// it was signalled
Term adopt_stop_run(Env e, Term* f, IoWork* w) {
  unsigned pid = (unsigned)(uint32_t)f[0];
  u64 len = 0;
  char *want = io_cstr(e, f[1], &len);
  char now[96];
  int ok = 0;
  if (pid > 1 && len > 0 && !bp_adopt_ancestor(pid)) {
    bp_adopt_ident(pid, now, sizeof now);
    if (now[0] && !strcmp(now, want)) ok = kill((pid_t)pid, SIGTERM) == 0;
  }
  free(want);
  return term_pak(ok ? CID(True) : CID(False), 0);
}
static void __attribute__((constructor)) adopt_stop_use(void) { io_eff(CID(Adopt.stop), adopt_stop_run); }
#endif
