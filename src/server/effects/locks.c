#include <sys/file.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#ifdef __linux__
#include <sys/syscall.h>
#endif
#if defined(__GLIBC__) && (__GLIBC__ > 2 || (__GLIBC__ == 2 && __GLIBC_MINOR__ >= 34))
#include <spawn.h>
#define BP_LOCK_SPAWN 1
extern char **environ;
#endif

struct bp_lock_guard { char *name, *holder; int pipe; pid_t pid; struct bp_lock_guard *next; };
static struct bp_lock_guard *bp_lock_guards;
static int bp_lock_name(const char *s) {
  size_t n = strlen(s);
  if (!n || n > 64) return 0;
  for (; *s; s++) if (!((*s >= 'a' && *s <= 'z') || (*s >= 'A' && *s <= 'Z') || (*s >= '0' && *s <= '9') || *s == '-' || *s == '_')) return 0;
  return 1;
}
#ifdef CID(Guard.take)
Term guard_take_run(Env e, Term *f, IoWork *w) {
  u64 len; char *name = io_cstr(e, f[0], &len), *holder = io_cstr(e, f[1], &len);
  char *home = io_cstr(e, f[2], &len), *script = io_cstr(e, f[3], &len);
  int ok = 0;
  if (!bp_lock_name(name) || !*holder) goto done;
  for (struct bp_lock_guard *g = bp_lock_guards; g; g = g->next) {
    if (strcmp(g->name, name) == 0) { ok = strcmp(g->holder, holder) == 0; goto done; }
  }
  const char *dir = getenv("BACKPLANE_LOCK_DIR"); if (!dir || !*dir) dir = "/tmp";
  char path[4096]; if (snprintf(path, sizeof(path), "%s/bp-%s.lock", dir, name) >= sizeof(path)) goto done;
  int opened = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
  if (opened < 0) goto done;
  int fd = fcntl(opened, F_DUPFD_CLOEXEC, 3); close(opened);
  if (fd < 0) goto done;
  if (flock(fd, LOCK_EX | LOCK_NB)) { close(fd); goto done; }
  int raw[2]; if (pipe(raw)) { close(fd); goto done; }
  int p[2];
  p[0] = fcntl(raw[0], F_DUPFD_CLOEXEC, 3);
  p[1] = fcntl(raw[1], F_DUPFD_CLOEXEC, 3);
  close(raw[0]); close(raw[1]);
  if (p[0] < 0 || p[1] < 0) { if (p[0] >= 0) close(p[0]); if (p[1] >= 0) close(p[1]); close(fd); goto done; }
  long maxfd = sysconf(_SC_OPEN_MAX); if (maxfd < 0) maxfd = 65536;
#ifdef BP_LOCK_SPAWN
  // posix_spawn, not fork: a fork of the hub copied its page tables (GBs of
  // heap) on every lock taken, tens of ms with the hub's loop waiting. The
  // child gets the same: stdin the pipe, fd 3 the flock (kept across exec),
  // stdout and stderr /dev/null, nothing else open.
  if (fd == 3) { int moved = fcntl(fd, F_DUPFD_CLOEXEC, 4); if (moved < 0) { close(fd); close(p[0]); close(p[1]); goto done; } close(fd); fd = moved; }
  pid_t pid = -1;
  posix_spawn_file_actions_t fa;
  if (posix_spawn_file_actions_init(&fa) == 0) {
    char *argv[] = { "sh", "-c", script, "sh", home, holder, NULL };
    if (posix_spawn_file_actions_adddup2(&fa, p[0], 0) == 0 && posix_spawn_file_actions_adddup2(&fa, fd, 3) == 0
        && posix_spawn_file_actions_addopen(&fa, 1, "/dev/null", O_WRONLY, 0) == 0 && posix_spawn_file_actions_adddup2(&fa, 1, 2) == 0
        && posix_spawn_file_actions_addclosefrom_np(&fa, 4) == 0) {
      if (posix_spawn(&pid, "/bin/sh", &fa, NULL, argv, environ) != 0) pid = -1;
    }
    posix_spawn_file_actions_destroy(&fa);
  }
#else
  pid_t pid = fork();
  if (!pid) {
    // Only async-signal-safe operations after fork in the threaded runtime.
    #ifdef __linux__
    unsigned lo = fd < p[0] ? fd : p[0], hi = fd > p[0] ? fd : p[0];
    int closed = syscall(SYS_close_range, 0u, lo - 1u, 0u);
    if (hi > lo + 1u && syscall(SYS_close_range, lo + 1u, hi - 1u, 0u) < 0) closed = -1;
    if (syscall(SYS_close_range, hi + 1u, ~0u, 0u) < 0) closed = -1;
    if (closed < 0) for (int n = 0; n < maxfd; n++) if (n != fd && n != p[0]) close(n);
#else
    for (int n = 0; n < maxfd; n++) if (n != fd && n != p[0]) close(n);
#endif
    // fd 3 survives exec and protects the work throughout cleanup. Duplicate
    // the pipe first: its original descriptor may itself be 3.
    if (dup2(p[0], 0) < 0 || dup2(fd, 3) < 0 || fcntl(3, F_SETFD, 0) < 0) _exit(127);
    execl("/bin/sh", "sh", "-c", script, "sh", home, holder, (char *)NULL);
    _exit(127);
  }
#endif
  close(p[0]); close(fd);
  if (pid < 0) { close(p[1]); goto done; }
  struct bp_lock_guard *g = calloc(1, sizeof(*g));
  if (!g) { close(p[1]); waitpid(pid, 0, 0); goto done; }
  g->name = strdup(name); g->holder = strdup(holder); g->pipe = p[1]; g->pid = pid;
  g->next = bp_lock_guards; bp_lock_guards = g; ok = 1;
done:
  free(name); free(holder); free(home); free(script); return term_pak(ok ? CID(True) : CID(False), 0);
}
static void __attribute__((constructor)) guard_take_use(void) { io_eff(CID(Guard.take), guard_take_run); }
#endif
#ifdef CID(Guard.drop)
Term guard_drop_run(Env e, Term *f, IoWork *w) {
  u64 len; char *name = io_cstr(e, f[0], &len), *holder = io_cstr(e, f[1], &len);
  struct bp_lock_guard **at = &bp_lock_guards;
  while (*at) {
    struct bp_lock_guard *g = *at;
    if (!strcmp(g->name, name) && !strcmp(g->holder, holder)) {
      *at = g->next; close(g->pipe);
      while (waitpid(g->pid, 0, 0) < 0 && errno == EINTR) {}
      free(g->name); free(g->holder); free(g); break;
    }
    at = &g->next;
  }
  free(name); free(holder); return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) guard_drop_use(void) { io_eff(CID(Guard.drop), guard_drop_run); }
#endif
