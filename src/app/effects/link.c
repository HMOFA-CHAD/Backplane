// Bounded hostname resolution and connect, and byte-exact handshake reads.
// DNS runs on a detached worker: the Bend event loop never waits in libc.
#include <netdb.h>
#include <pthread.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

#ifdef CID_LINK_CONNECT

typedef struct {
  char* host;
  int fd;
} LinkResolve;

typedef struct {
  int code;
  struct sockaddr_in addr;
} LinkAddress;

typedef struct {
  u64 deadline;
  int phase;
  uint16_t port;
} LinkDial;

static void* link_resolve(void* arg) {
  LinkResolve* job = arg;
  struct addrinfo hint = {0}, *addrs = NULL;
  hint.ai_family = AF_INET;
  hint.ai_socktype = SOCK_STREAM;
  LinkAddress answer = {0};
  int code = getaddrinfo(job->host, NULL, &hint, &addrs);
  if (code || !addrs) {
    answer.code = EHOSTUNREACH;
  } else {
    memcpy(&answer.addr, addrs->ai_addr, sizeof(answer.addr));
  }
  if (addrs) freeaddrinfo(addrs);
  // The window may already have timed out and closed its endpoint.
  send(job->fd, &answer, sizeof(answer), MSG_NOSIGNAL);
  close(job->fd);
  free(job->host);
  free(job);
  return NULL;
}

static Term link_connect_end(Env e, IoWork* w, int code) {
  int fd = (int)w->hand;
  free(w->data);
  if (code) {
    close(fd);
    return io_fail(e, code, NULL);
  }
  return io_done(e, io_hand(fd));
}

static Term link_connect_more(Env e, IoWork* w) {
  LinkDial* dial = (LinkDial*)w->data;
  int fd = (int)w->hand;
  if (io_tick() >= dial->deadline) return link_connect_end(e, w, ETIMEDOUT);
  if (dial->phase == 0) {
    LinkAddress answer;
    ssize_t n = recv(fd, &answer, sizeof(answer), 0);
    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      return io_wait_on(w, fd, POLLIN, dial->deadline, link_connect_more);
    }
    if (n != sizeof(answer)) return link_connect_end(e, w, EHOSTUNREACH);
    if (answer.code) return link_connect_end(e, w, answer.code);
    answer.addr.sin_port = htons(dial->port);
    close(fd);
    fd = socket(AF_INET, SOCK_STREAM, 0);
    w->hand = fd;
    if (fd < 0) return link_connect_end(e, w, errno);
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0 || fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) < 0) {
      return link_connect_end(e, w, errno);
    }
    int code = connect(fd, (struct sockaddr*)&answer.addr, sizeof(answer.addr)) < 0 ? errno : 0;
    if (code != EINPROGRESS) return link_connect_end(e, w, code);
    dial->phase = 1;
    return io_wait_on(w, fd, POLLOUT, dial->deadline, link_connect_more);
  }
  int code = 0;
  socklen_t size = sizeof(code);
  if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &code, &size) < 0) code = errno;
  return link_connect_end(e, w, code);
}

Term link_connect_run(Env e, Term* f, IoWork* w) {
  u64 len = 0;
  char* host = io_cstr(e, f[0], &len);
  if (io_nul(host, len)) {
    free(host);
    return io_fail(e, EINVAL, NULL);
  }
  int pair[2];
  if (socketpair(AF_UNIX, SOCK_DGRAM, 0, pair) < 0) {
    free(host);
    return io_fail(e, errno, NULL);
  }
  if (fcntl(pair[0], F_SETFD, FD_CLOEXEC) < 0 || fcntl(pair[1], F_SETFD, FD_CLOEXEC) < 0 || fcntl(pair[0], F_SETFL, fcntl(pair[0], F_GETFL) | O_NONBLOCK) < 0) {
    int code = errno;
    close(pair[0]); close(pair[1]); free(host);
    return io_fail(e, code, NULL);
  }
  LinkResolve* job = io_mem(malloc(sizeof(*job)));
  job->host = host;
  job->fd = pair[1];
  pthread_t worker;
  int code = pthread_create(&worker, NULL, link_resolve, job);
  if (code) {
    close(pair[0]); close(pair[1]); free(host); free(job);
    return io_fail(e, code, NULL);
  }
  pthread_detach(worker);
  LinkDial* dial = io_mem(malloc(sizeof(*dial)));
  dial->deadline = io_tick() + (u64)f[2] * 1000000ull;
  dial->phase = 0;
  dial->port = (uint16_t)f[1];
  w->data = (char*)dial;
  w->hand = pair[0];
  return io_wait_on(w, pair[0], POLLIN, dial->deadline, link_connect_more);
}

static void __attribute__((constructor)) link_connect_use(void) {
  io_eff(CID_LINK_CONNECT, link_connect_run, 0);
}
#endif

#ifdef CID_LINK_POLL
static Term link_poll_end(Env e, IoWork* w, Term result) {
  free(w->data);
  return io_tup(e, io_hand(w->hand), result);
}

static Term link_poll_more(Env e, IoWork* w) {
  int fd = (int)w->hand;
  u64 deadline = io_wait_time(w);
  ssize_t n = recv(fd, w->data, (size_t)w->made, 0);
  if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
    return io_tick() < deadline ? io_wait_on(w, fd, POLLIN, deadline, link_poll_more)
      : link_poll_end(e, w, io_done(e, term_pak(CID_NONE, 0)));
  }
  if (n < 0) return link_poll_end(e, w, io_fail(e, errno, NULL));
  Term bytes = term_pak(CID_NIL, 0);
  for (ssize_t i = n; i > 0; i--) bytes = io_node(e, CID_CON, (Term)(uint8_t)w->data[i - 1], bytes);
  return link_poll_end(e, w, io_done(e, io_box(e, CID_SOME, bytes)));
}

Term link_poll_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->made = 65536;
  w->data = io_mem(malloc((size_t)w->made));
  return io_wait_on(w, (int)w->hand, POLLIN, io_tick() + (u64)f[1] * 1000000ull, link_poll_more);
}

static void __attribute__((constructor)) link_poll_use(void) {
  io_eff(CID_LINK_POLL, link_poll_run, 0);
}
#endif
