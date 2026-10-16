// backplane-cef: a CEF browser drawn as a native child of an X11 window.
//
//   backplane-cef [--parent XID] [--url URL] [--size WxH] [--at XxY]
//                 [--cache DIR] [--port N]
//
// --parent embeds the browser in that window (Backplane's); without it the
// host makes its own top-level test window. --port opens Chromium's remote
// debugging endpoint (CDP) on 127.0.0.1, so automation (Playwright's
// connectOverCDP) drives the very page the person sees. --cache is the root
// cache (profile) directory; it must not be a Chrome profile in use.
//
// stdout: one JSON object per line ({"event": ...}); stdin: one command a
// line (see README.md). Diagnostics go to stderr.

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <atomic>
#include <iostream>
#include <string>
#include <thread>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_command_line.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/wrapper/cef_helpers.h"
#include "include/base/cef_callback.h"

namespace {

// wall-clock ms, so a bench can line our events up with its own clock
double now_ms() {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

std::string json_str(const std::string& s) {
  std::string o = "\"";
  for (unsigned char c : s) {
    if (c == '"' || c == '\\') { o += '\\'; o += c; }
    else if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); o += b; }
    else o += c;
  }
  return o + "\"";
}

void emit(const std::string& body) {
  // one line, flushed: the reader is a pipe
  printf("{%s,\"t\":%.1f}\n", body.c_str(), now_ms());
  fflush(stdout);
}

struct Opts {
  unsigned long parent = 0;
  std::string url = "about:blank";
  int w = 800, h = 600, x = 0, y = 0;
  std::string cache;
  int port = 0;
};

Opts g_opts;
Display* g_dpy = nullptr;     // our own connection, for the test window and moves
Window g_parent = 0;
CefRefPtr<CefBrowser> g_browser;
std::atomic<bool> g_quitting{false};

class Client : public CefClient,
               public CefLifeSpanHandler,
               public CefLoadHandler,
               public CefDisplayHandler {
 public:
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }

  // popups (window.open, target=_blank) open in the same child: the person
  // and the agent keep one page, never a stray top-level window
  bool OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int popup_id,
                     const CefString& target_url, const CefString& target_frame_name,
                     WindowOpenDisposition target_disposition, bool user_gesture,
                     const CefPopupFeatures& popupFeatures, CefWindowInfo& windowInfo,
                     CefRefPtr<CefClient>& client, CefBrowserSettings& settings,
                     CefRefPtr<CefDictionaryValue>& extra_info, bool* no_javascript_access) override {
    emit("\"event\":\"popup\",\"url\":" + json_str(target_url.ToString()));
    if (!target_url.empty()) frame->GetBrowser()->GetMainFrame()->LoadURL(target_url);
    return true;
  }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    g_browser = browser;
    char b[160];
    snprintf(b, sizeof b, "\"event\":\"ready\",\"xid\":%lu,\"parent\":%lu,\"port\":%d",
             (unsigned long)browser->GetHost()->GetWindowHandle(), (unsigned long)g_parent, g_opts.port);
    emit(b);
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    g_browser = nullptr;
    emit("\"event\":\"closed\"");
    CefQuitMessageLoop();
  }

  void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int code) override {
    if (!frame->IsMain()) return;
    emit("\"event\":\"load\",\"url\":" + json_str(frame->GetURL().ToString()) + ",\"code\":" + std::to_string(code));
  }

  void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) override {
    if (frame->IsMain()) emit("\"event\":\"navigated\",\"url\":" + json_str(url.ToString()));
  }

  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override {
    emit("\"event\":\"title\",\"title\":" + json_str(title.ToString()));
  }

 private:
  IMPLEMENT_REFCOUNTING(Client);
};

class App : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

  void OnBeforeCommandLineProcessing(const CefString& type, CefRefPtr<CefCommandLine> cl) override {
    // the hub's Chrome profile lock and keyring stay out of it
    cl->AppendSwitchWithValue("password-store", "basic");
    cl->AppendSwitch("use-mock-keychain");
    if (getenv("BACKPLANE_CEF_NO_GPU")) cl->AppendSwitch("disable-gpu");
  }

  void OnContextInitialized() override {
    CEF_REQUIRE_UI_THREAD();
    CefWindowInfo wi;
    wi.SetAsChild((CefWindowHandle)g_parent, CefRect(g_opts.x, g_opts.y, g_opts.w, g_opts.h));
    // Alloy: a plain content area with no Chrome UI of its own, the shape a
    // panel inside another app wants
    wi.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
    CefBrowserSettings bs;
    CefBrowserHost::CreateBrowser(wi, new Client, g_opts.url, bs, nullptr, nullptr);
  }

 private:
  IMPLEMENT_REFCOUNTING(App);
};

// Commands from stdin, run on the UI thread
// -----------------------------------------

void place(int x, int y, int w, int h) {
  if (!g_browser) return;
  Window child = (Window)g_browser->GetHost()->GetWindowHandle();
  XMoveResizeWindow(g_dpy, child, x, y, w > 0 ? w : 1, h > 0 ? h : 1);
  XFlush(g_dpy);
  g_browser->GetHost()->WasResized();
}

void run_command(std::string line) {
  CEF_REQUIRE_UI_THREAD();
  char word[32] = {0};
  sscanf(line.c_str(), "%31s", word);
  std::string cmd = word;
  std::string rest = line.size() > cmd.size() ? line.substr(cmd.size() + 1) : "";
  if (cmd == "quit") {
    g_quitting = true;
    if (g_browser) g_browser->GetHost()->CloseBrowser(true);
    else CefQuitMessageLoop();
    return;
  }
  if (!g_browser) { emit("\"event\":\"error\",\"error\":\"no browser yet\""); return; }
  if (cmd == "url") {
    g_browser->GetMainFrame()->LoadURL(rest);
  } else if (cmd == "place") {
    int x, y, w, h;
    if (sscanf(rest.c_str(), "%d %d %d %d", &x, &y, &w, &h) == 4) place(x, y, w, h);
  } else if (cmd == "show" || cmd == "hide") {
    Window child = (Window)g_browser->GetHost()->GetWindowHandle();
    if (cmd == "show") XMapWindow(g_dpy, child); else XUnmapWindow(g_dpy, child);
    XFlush(g_dpy);
    g_browser->GetHost()->WasHidden(cmd == "hide");
  } else if (cmd == "focus") {
    g_browser->GetHost()->SetFocus(rest != "0");
  } else if (cmd == "back") {
    g_browser->GoBack();
  } else if (cmd == "forward") {
    g_browser->GoForward();
  } else if (cmd == "reload") {
    g_browser->Reload();
  } else {
    emit("\"event\":\"error\",\"error\":" + json_str("unknown command: " + cmd));
    return;
  }
  emit("\"event\":\"ok\",\"cmd\":" + json_str(cmd));
}

void stdin_loop() {
  std::string line;
  while (std::getline(std::cin, line)) {
    if (line.empty()) continue;
    CefPostTask(TID_UI, base::BindOnce(&run_command, line));
  }
  // EOF: the owner went away, so do we
  if (!g_quitting) CefPostTask(TID_UI, base::BindOnce(&run_command, std::string("quit")));
}

int x_error(Display*, XErrorEvent* e) {
  fprintf(stderr, "backplane-cef: X error %d (request %d)\n", e->error_code, e->request_code);
  return 0;
}

void parse(int argc, char** argv) {
  for (int i = 1; i + 1 < argc; i++) {
    std::string a = argv[i];
    const char* v = argv[i + 1];
    if (a == "--parent") g_opts.parent = strtoul(v, nullptr, 0), i++;
    else if (a == "--url") g_opts.url = v, i++;
    else if (a == "--size") sscanf(v, "%dx%d", &g_opts.w, &g_opts.h), i++;
    else if (a == "--at") sscanf(v, "%dx%d", &g_opts.x, &g_opts.y), i++;
    else if (a == "--cache") g_opts.cache = v, i++;
    else if (a == "--port") g_opts.port = atoi(v), i++;
  }
}

}  // namespace

// The zygote changes the stack canary in each child it forks
// (--change-stack-guard-on-fork), so a frame live across the fork must not
// check it: Chromium marks its own entry point the same way.
__attribute__((no_stack_protector)) int main(int argc, char** argv) {
  double t0 = now_ms();
  CefMainArgs args(argc, argv);
  CefRefPtr<App> app = new App;
  // the renderer, GPU and utility processes are this same binary
  int code = CefExecuteProcess(args, app, nullptr);
  if (code >= 0) return code;

  parse(argc, argv);
  XInitThreads();
  g_dpy = XOpenDisplay(nullptr);
  if (!g_dpy) { fprintf(stderr, "backplane-cef: no X display\n"); return 1; }
  XSetErrorHandler(x_error);
  if (g_opts.parent) {
    g_parent = (Window)g_opts.parent;
  } else {
    int s = DefaultScreen(g_dpy);
    g_parent = XCreateSimpleWindow(g_dpy, RootWindow(g_dpy, s), 0, 0, g_opts.w + g_opts.x,
                                   g_opts.h + g_opts.y, 0, 0, WhitePixel(g_dpy, s));
    XStoreName(g_dpy, g_parent, "backplane-cef test");
    XMapWindow(g_dpy, g_parent);
    XSync(g_dpy, False);
  }

  CefSettings st;
  st.no_sandbox = true;
  st.remote_debugging_port = g_opts.port;
  st.log_severity = LOGSEVERITY_WARNING;
  if (!g_opts.cache.empty()) {
    CefString(&st.root_cache_path) = g_opts.cache;
    CefString(&st.cache_path) = g_opts.cache + "/Default";
  }
  if (!CefInitialize(args, st, app, nullptr)) {
    fprintf(stderr, "backplane-cef: CefInitialize failed (code %d)\n", CefGetExitCode());
    return 1;
  }
  char b[64];
  snprintf(b, sizeof b, "\"event\":\"init\",\"ms\":%.1f", now_ms() - t0);
  emit(b);
  std::thread(stdin_loop).detach();
  CefRunMessageLoop();
  CefShutdown();
  XCloseDisplay(g_dpy);
  return 0;
}
