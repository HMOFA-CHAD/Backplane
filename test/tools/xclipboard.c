// An X11 clipboard fixture: MIME bytes, optionally INCR or legacy text.
// cc test/tools/xclipboard.c -lX11 -o build/xclipboard
// DISPLAY=:92 build/xclipboard image/png FILE [incr|legacy|string]
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  if (argc < 3) return 2;
  FILE *f = fopen(argv[2], "rb");
  if (!f) return 2;
  fseek(f, 0, SEEK_END);
  long length = ftell(f);
  rewind(f);
  unsigned char *bytes = malloc((size_t)length + 1);
  if (!bytes || fread(bytes, 1, length, f) != (size_t)length) return 2;
  fclose(f);
  Display *d = XOpenDisplay(NULL);
  if (!d) return 2;
  Window own = XCreateSimpleWindow(d, DefaultRootWindow(d), 0, 0, 1, 1, 0, 0, 0);
  Atom clip = XInternAtom(d, "CLIPBOARD", False);
  Atom targets = XInternAtom(d, "TARGETS", False);
  Atom mime = XInternAtom(d, argv[1], False);
  Atom utf8 = XInternAtom(d, "UTF8_STRING", False);
  Atom incr = XInternAtom(d, "INCR", False);
  int incremental = argc > 3 && !strcmp(argv[3], "incr");
  int legacy = argc > 3 && (!strcmp(argv[3], "legacy") || !strcmp(argv[3], "string"));
  int plain = argc > 3 && !strcmp(argv[3], "string");
  Window receiver = None;
  Atom property = None;
  long offset = 0;
  XSetSelectionOwner(d, clip, own, CurrentTime);
  XFlush(d);
  fprintf(stderr, "clipboard ready %ld bytes\n", length);
  for (;;) {
    XEvent ev;
    XNextEvent(d, &ev);
    if (ev.type == SelectionRequest) {
      XSelectionRequestEvent *q = &ev.xselectionrequest;
      Atom prop = q->property == None ? q->target : q->property;
      char *asked = XGetAtomName(d, q->target);
      fprintf(stderr, "requested %s\n", asked);
      XFree(asked);
      XEvent answer = {0};
      answer.xselection.type = SelectionNotify;
      answer.xselection.display = d;
      answer.xselection.requestor = q->requestor;
      answer.xselection.selection = q->selection;
      answer.xselection.target = q->target;
      answer.xselection.time = q->time;
      answer.xselection.property = None;
      if (q->target == targets && !legacy) {
        // Offer text first too: an image paste must still choose its MIME.
        Atom offered[] = { targets, utf8, XA_STRING, mime };
        XChangeProperty(d, q->requestor, prop, XA_ATOM, 32, PropModeReplace, (unsigned char *)offered, 4);
        answer.xselection.property = prop;
      } else if (q->target == mime || (legacy && q->target == (plain ? XA_STRING : utf8))) {
        if (incremental) {
          receiver = q->requestor;
          property = prop;
          offset = 0;
          XSelectInput(d, receiver, PropertyChangeMask);
          unsigned long total = (unsigned long)length;
          XChangeProperty(d, receiver, prop, incr, 32, PropModeReplace, (unsigned char *)&total, 1);
          fprintf(stderr, "INCR started\n");
        } else {
          XChangeProperty(d, q->requestor, prop, q->target, 8, PropModeReplace, bytes, length);
        }
        answer.xselection.property = prop;
      }
      XSendEvent(d, q->requestor, False, NoEventMask, &answer);
      XFlush(d);
    } else if (ev.type == PropertyNotify && ev.xproperty.window == receiver &&
               ev.xproperty.atom == property && ev.xproperty.state == PropertyDelete) {
      long n = length - offset;
      if (n > 65536) n = 65536;
      XChangeProperty(d, receiver, property, mime, 8, PropModeReplace, bytes + offset, n);
      XFlush(d);
      offset += n;
      if (n == 0) {
        fprintf(stderr, "INCR finished %ld bytes\n", offset);
        receiver = None;
      }
    } else if (ev.type == SelectionClear) {
      break;
    }
  }
  free(bytes);
  XCloseDisplay(d);
  return 0;
}
