// End to end: connecting Google with the shared client (docs/bots.md) on
// headless hubs, against a stand-in for Google's token, revoke and
// Calendar endpoints. Connect asks for Calendar only and needs nothing
// pasted; the redirect finishes the sign-in; a bot's calendar_events works
// and its gmail_* tools are refused; a client of the user's own wins and
// asks for Gmail too; a build with no shared client says so. Prints
// "ok ..." / "FAIL ..." lines.
//
//   bun test/tools/google_e2e.ts [BINARY] [WIREDIR]
//
// BINARY defaults to build/backplane; WIREDIR to build/wire (bend
// test/wire/index.html -o build/wire).
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync, chmodSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const [bin = "build/backplane", wire = "build/wire"] = process.argv.slice(2);
for (const f of readdirSync(wire).filter((f) => f.endsWith(".js"))) (0, eval)(readFileSync(`${wire}/${f}`, "utf8"));
const W = (globalThis as any).Wire;

let failed = false;
const check = (name: string, ok: boolean, got?: unknown) => {
  console.log(ok ? `ok ${name}` : `FAIL ${name}: ${JSON.stringify(got)?.slice(0, 400)}`);
  if (!ok) failed = true;
};
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
async function until<T>(ms: number, f: () => T | undefined | null | false): Promise<T | undefined> {
  const end = Date.now() + ms;
  for (;;) {
    const v = f();
    if (v) return v;
    if (Date.now() > end) return undefined;
    await sleep(50);
  }
}
function freePort(): number {
  const s = Bun.listen({ hostname: "127.0.0.1", port: 0, socket: { data() {} } });
  const p = s.port;
  s.stop(true);
  return p;
}

// Google, as far as the hub sees it
const b64u = (s: string) => Buffer.from(s).toString("base64url");
const grants: Record<string, string>[] = [];
const google = Bun.serve({
  hostname: "127.0.0.1",
  port: 0,
  async fetch(req) {
    const u = new URL(req.url);
    if (req.method === "POST" && u.pathname === "/token") {
      const f = Object.fromEntries(new URLSearchParams(await req.text()));
      grants.push(f);
      const id_token = `${b64u("{}")}.${b64u(JSON.stringify({ email: "cat@example.com" }))}.sig`;
      return Response.json({ access_token: "at-" + grants.length, expires_in: 3600, refresh_token: "rt-1", id_token, token_type: "Bearer" });
    }
    if (u.pathname === "/revoke") return new Response("{}");
    if (u.pathname === "/calendar/v3/calendars/primary/events")
      return Response.json({ timeZone: "UTC", items: [{ id: "ev1", summary: "Board bring-up", start: { dateTime: "2026-09-28T09:00:00Z" }, end: { dateTime: "2026-09-28T10:00:00Z" } }] });
    return new Response("not here", { status: 404 });
  },
});
const G = `http://127.0.0.1:${google.port}`;

const root = mkdtempSync(join(tmpdir(), "bp-google-e2e-"));
const fake = join(root, "bin");
mkdirSync(fake);
for (const n of ["claude", "codex", "grok"]) {
  writeFileSync(join(fake, n), "#!/bin/sh\nexit 1\n");
  chmodSync(join(fake, n), 0o755);
}

type Hub = { port: number; proc: ReturnType<typeof Bun.spawn>; ws: WebSocket; seen: any[]; replies: Map<number, any>; n: number };
async function start(name: string, env: Record<string, string>): Promise<Hub> {
  const port = freePort();
  const proc = Bun.spawn([resolve(bin), "--home", join(root, name), "--port", String(port), "--no-tailscale"], {
    env: { ...process.env, HOME: join(root, "user"), DISPLAY: "", WAYLAND_DISPLAY: "", BACKPLANE_NO_UPDATE: "1", BACKPLANE_PEERS: "",
      BACKPLANE_GOOGLE_OAUTH: G, BACKPLANE_GOOGLE_API: G, PATH: `${fake}:${process.env.PATH}`, ...env },
    stdout: "ignore",
    stderr: process.env.E2E_LOG ? "inherit" : "ignore",
  });
  for (let i = 0; i < 100; i++) {
    try {
      if ((await fetch(`http://127.0.0.1:${port}/hello`)).status === 200) break;
    } catch {}
    await sleep(100);
  }
  const h: Hub = { port, proc, ws: null as any, seen: [], replies: new Map(), n: 0 };
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  ws.binaryType = "arraybuffer";
  ws.onmessage = (e) => {
    const o = JSON.parse(W.decode(new Uint8Array(e.data as ArrayBuffer)));
    for (const c of o.items ?? []) h.seen.push(c);
    if (o.t === "reply") h.replies.set(Number(o.id), o);
  };
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  h.ws = ws;
  return h;
}
async function rpc(h: Hub, m: string, p: object): Promise<any> {
  const id = ++h.n;
  h.ws.send(W.encode(JSON.stringify({ id, m, p })));
  return await until(10000, () => h.replies.get(id));
}
const op = (h: Hub, o: string, extra: object = {}) => rpc(h, "bots.google", { op: o, clientId: "", clientSecret: "", pasted: "", ...extra });
const tool = (h: Hub, th: string, name: string) =>
  fetch(`http://127.0.0.1:${h.port}/mcp/${th}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 9, method: "tools/call", params: { name, arguments: {} } }),
  }).then((r) => r.json()).then((r: any) => String(r?.result?.content?.[0]?.text ?? JSON.stringify(r)));

const hubs: Hub[] = [];
try {
  mkdirSync(join(root, "user"));
  const a = await start("shared", { BACKPLANE_GOOGLE_CLIENT_ID: "shared-id.apps.googleusercontent.com", BACKPLANE_GOOGLE_CLIENT_SECRET: "shared-secret" });
  hubs.push(a);

  const s0 = await op(a, "status");
  check("status before: not connected", s0?.ok && s0.google === "Not connected.", s0);

  const c = await op(a, "connect");
  const url = new URL(c?.googleUrl ?? "http://x/");
  const scope = url.searchParams.get("scope") ?? "";
  check("connect needs nothing pasted", c?.ok && url.host === "accounts.google.com", c);
  check("connect uses the shared client", url.searchParams.get("client_id") === "shared-id.apps.googleusercontent.com", url.search);
  check("the shared client asks for Calendar only", scope.includes("calendar.events") && !scope.includes("gmail"), scope);
  check("with PKCE", url.searchParams.get("code_challenge_method") === "S256" && (url.searchParams.get("code_challenge") ?? "").length === 43);

  const pend = await op(a, "status");
  check("status while waiting", String(pend?.google).startsWith("Waiting for Google"), pend);

  const back = await fetch(`http://127.0.0.1:${a.port}/oauth/google?state=${url.searchParams.get("state")}&code=4%2F0Ab&scope=${encodeURIComponent(scope)}`);
  const page = await back.text();
  check("the redirect finishes the sign-in", back.status === 200 && page.includes("Google is connected"), page.slice(0, 300));
  const g = grants.at(-1) ?? {};
  check("the code is traded with the shared client and the verifier",
    g.grant_type === "authorization_code" && g.client_id === "shared-id.apps.googleusercontent.com" && g.client_secret === "shared-secret" && (g.code_verifier ?? "").length > 40, g);

  const s1 = await op(a, "status");
  check("status after: connected, Calendar", s1?.google === "Connected as cat@example.com (Calendar).", s1);

  const bot = await rpc(a, "bots.create", { name: "miso" });
  const set = await until(8000, () => a.seen.find((x) => x.$ === "BotSet" && x.id === bot?.bot));
  const th: string = set?.thread ?? "";
  check("a bot to call from", !!th, bot);
  const ev = await tool(a, th, "calendar_events");
  check("calendar_events works on the shared link", ev.includes("Board bring-up"), ev);
  const gm = await tool(a, th, "gmail_search");
  check("gmail tools are refused on the shared link", ev !== gm && gm.includes("Gmail is not linked"), gm);

  const d = await op(a, "disconnect");
  check("disconnect", d?.google === "Not connected.", d);

  const own = await op(a, "connect", { clientId: "own-id", clientSecret: "own-secret" });
  const ou = new URL(own?.googleUrl ?? "http://x/");
  check("a client of your own wins", ou.searchParams.get("client_id") === "own-id", own);
  check("and asks for Gmail too", (ou.searchParams.get("scope") ?? "").includes("gmail.modify"), ou.search);
  const back2 = await fetch(`http://127.0.0.1:${a.port}/oauth/google?state=${ou.searchParams.get("state")}&code=4%2F0Ac`);
  await back2.text();
  const s2 = await op(a, "status");
  check("own client: Gmail and Calendar", s2?.google === "Connected as cat@example.com (Gmail and Calendar).", s2);
  const gm2 = await tool(a, th, "gmail_search");
  check("own client: gmail tools run", !gm2.includes("Gmail is not linked"), gm2);

  const b = await start("bare", {});
  hubs.push(b);
  const s3 = await op(b, "status");
  check("no shared client: status says so", String(s3?.google).includes("no shared Google client"), s3);
  const c3 = await op(b, "connect");
  check("no shared client: connect asks for one", c3?.ok === false || String(c3?.error ?? "").includes("no shared Google client"), c3);
} finally {
  for (const h of hubs) {
    h.ws?.close();
    h.proc.kill();
    await h.proc.exited;
  }
  google.stop(true);
  rmSync(root, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);
