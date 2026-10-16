// Low-level regular-file primitives. Protocol and repair policy live in Bend.
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

#ifdef CID(MailFile.open)
static void mailfile_open_call(IoWork* w) {
  char *slash = strrchr(w->data, '/');
  int code = 0, fd = -1;
  if (!slash || !slash[1] || io_nul(w->data, w->size)) code = EINVAL;
  else {
    *slash = 0;
    int dir = open(w->data, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (dir < 0) code = errno;
    else {
      int flags = w->word ? O_RDWR | O_CREAT : O_RDONLY;
      fd = openat(dir, slash + 1, flags | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0600);
      if (fd < 0) code = errno;
      else {
        struct stat st;
        if (fstat(fd, &st)) code = errno;
        else if (!S_ISREG(st.st_mode)) code = EINVAL;
        // A writable body file must not be a hard link to a file elsewhere.
        else if (w->word && st.st_nlink != 1) code = EINVAL;
      }
      if (close(dir) && !code) code = errno;
    }
  }
  if (code && fd >= 0) close(fd);
  w->made = fd; w->code = code;
}
static Term mailfile_open_pack(Env e, IoWork* w) {
  free(w->data);
  return w->code ? io_fail(e, w->code, NULL) : io_done(e, io_hand(w->made));
}
Term mailfile_open_run(Env e, Term* f, IoWork* w) {
  w->data = io_cstr(e, f[0], &w->size);
  w->word = (u32)f[1];
  return io_work(w, mailfile_open_call, mailfile_open_pack);
}
static void __attribute__((constructor)) mailfile_open_use(void) {
  io_eff(CID(MailFile.open), mailfile_open_run);
}
#endif

#ifdef CID(MailFile.finish)
static void mailfile_finish_call(IoWork* w) {
  int fd = (int)w->hand, code = 0;
  if (ftruncate(fd, (off_t)w->word)) code = errno;
  if (!code && lseek(fd, 0, SEEK_END) < 0) code = errno;
  uint64_t at = 0;
  while (!code && at < w->size) {
    ssize_t n = write(fd, w->data + at, w->size - at);
    if (n < 0) { if (errno != EINTR) code = errno; }
    else if (n == 0) code = EIO;
    else at += (uint64_t)n;
  }
  if (close(fd) && !code) code = errno;
  w->code = code;
}
static Term mailfile_finish_pack(Env e, IoWork* w) {
  free(w->data);
  return w->code ? io_fail(e, w->code, NULL) : io_done(e, term_pak(CID(Unit), 0));
}
Term mailfile_finish_run(Env e, Term* f, IoWork* w) {
  w->hand = io_hand_v(f[0]); w->word = (u32)f[1];
  w->data = io_cstr(e, f[2], &w->size);
  return io_work(w, mailfile_finish_call, mailfile_finish_pack);
}
static void __attribute__((constructor)) mailfile_finish_use(void) {
  io_eff(CID(MailFile.finish), mailfile_finish_run);
}
#endif
