// End to end: one uberbot on two machines (core/ubersync.bend, docs/uber.md
// "Sync"). Two headless hubs that pair by themselves (as far_e2e.ts) with a
// short grace (BACKPLANE_UBER_GRACE=30; the holder beats every 15 s). Checks: a bot promoted on alpha is
// offered to beta; beta joins; memory saved on either machine reaches the
// other's replica; a routine made on alpha runs on exactly one machine (the
// holder); alpha stopped, beta takes the lease within the grace and a
// minute and runs the routine; alpha started again steps down (a higher
// term) and does not run it. Agents are stand-ins. Prints "ok ..." /
// "FAIL ..." lines.
//
//   bun test/tools/uber_e2e.ts [BINARY] [WIREDIR]
//
// BINARY defaults to build/backplane-serve; WIREDIR to build/wire.
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync, chmodSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const args = process.argv.slice(2);
const [bin = "build/backplane-serve", wire = "build/wire"] = args.filter((a) => !a.startsWith("--"));
for (const f of readdirSync(wire).filter((f) => f.endsWith(".js"))) (0, eval)(readFileSync(`${wire}/${f}`, "utf8"));
const W = (globalThis as any).Wire;

let failed = false;
const check = (name: string, ok: boolean, got?: unknown) => {
  console.log(ok ? `ok ${name}` : `FAIL ${name}: ${JSON.stringify(got)?.slice(0, 600)}`);
  if (!ok) failed = true;
};
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
function freePort(): number {
  const s = Bun.listen({ hostname: "127.0.0.1", port: 0, socket: { data() {} } });
  const p = s.port;
  s.stop(true);
  return p;
}

const root = mkdtempSync(join(tmpdir(), "bp-uber-e2e-"));
const fake = join(root, "bin");
mkdirSync(fake);
const claude = `#!/bin/sh
n=0
while IFS= read -r line; do
  case "$line" in
    *'"type":"user"'*)
      n=$((n + 1))
      printf '%s\\n' '{"type":"assistant","message":{"id":"m'"$$-$n"'","content":[{"type":"text","text":"noted"}]}}'
      printf '%s\\n' '{"type":"result","is_error":false,"result":"noted"}' ;;
  esac
done
`;
for (const n of ["claude", "codex", "grok", "muse"]) {
  writeFileSync(join(fake, n), n === "claude" ? claude : "#!/bin/sh\nexit 1\n");
  chmodSync(join(fake, n), 0o755);
}

type Hub = { name: string; home: string; port: number; peers: string; proc: ReturnType<typeof Bun.spawn> | null };
type Client = { ws: WebSocket; seen: any[]; replies: Map<number, any>; n: number; info: any };

function spawn(h: Hub) {
  h.proc = Bun.spawn([resolve(bin), "--home", h.home, "--port", String(h.port), "--no-tailscale"], {
    env: { ...process.env, DISPLAY: "", WAYLAND_DISPLAY: "", BACKPLANE_NAME: h.name, BACKPLANE_NO_UPDATE: "1", BACKPLANE_PEERS: h.peers, BACKPLANE_UBER_GRACE: "30", PATH: `${fake}:/usr/bin:/bin` },
    stdout: "ignore",
    stderr: "ignore",
  });
}

async function up(h: Hub) {
  for (let i = 0; i < 200; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${h.port}/hello`);
      if (r.status === 200) return;
    } catch {}
    await sleep(100);
  }
  throw new Error(`${h.name} did not start`);
}

async function connect(h: Hub): Promise<Client> {
  const c: Client = { ws: null as any, seen: [], replies: new Map(), n: 0, info: {} };
  const ws = new WebSocket(`ws://127.0.0.1:${h.port}/ws`);
  ws.binaryType = "arraybuffer";
  ws.onmessage = (e) => {
    const o = JSON.parse(W.decode(new Uint8Array(e.data as ArrayBuffer)));
    for (const x of o.items ?? []) c.seen.push(x);
    if (o.t === "reply") c.replies.set(Number(o.id), o);
    if (o.info) c.info = { ...c.info, ...o.info };
  };
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  c.ws = ws;
  return c;
}

async function until<T>(ms: number, f: () => T | undefined | null | false): Promise<T | undefined> {
  const end = Date.now() + ms;
  for (;;) {
    const v = f();
    if (v) return v;
    if (Date.now() > end) return undefined;
    await sleep(50);
  }
}

async function rpc(c: Client, m: string, p: object): Promise<any> {
  const id = ++c.n;
  c.ws.send(W.encode(JSON.stringify({ id, m, p })));
  return await until(30000, () => c.replies.get(id));
}

// the setting value a client's log last gave a key
const setting = (c: Client, key: string) => c.seen.filter((x) => x.$ === "SettingSet" && x.key === key).at(-1)?.value as string | undefined;
// the uberbot's ops a client has, with their bodies parsed
const ops = (c: Client) => c.seen.filter((x) => x.$ === "UberOp").map((x) => ({ ...x, body: JSON.parse(x.op) }));
const leases = (c: Client) => ops(c).filter((o) => o.body.k === "lease");
const routineRuns = (c: Client, thread: string) => c.seen.filter((x) => x.$ === "MessagePosted" && x.thread === thread && String(x.text).startsWith("[routine:"));

const pa = freePort();
const pb = freePort();
const a: Hub = { name: "alpha", home: join(root, "alpha"), port: pa, peers: `http://127.0.0.1:${pb}`, proc: null };
const b: Hub = { name: "beta", home: join(root, "beta"), port: pb, peers: `http://127.0.0.1:${pa}`, proc: null };
const clients: Client[] = [];
try {
  spawn(a);
  spawn(b);
  await up(a);
  await up(b);
  let ca = await connect(a);
  let cb = await connect(b);
  clients.push(ca, cb);
  const knows = (c: Client, port: number) => String(c.info?.machines ?? "").includes(`127.0.0.1:${port}`);
  const both = await until(130000, () => knows(ca, pb) && knows(cb, pa));
  check("each hub lists the other as the owner's", !!both, [ca.info?.machines, cb.info?.machines]);
  // linked by an invite (the hubs' own pairing waits on the machines
  // lists, which is slow and not what this tests)
  const inv = await rpc(ca, "bots.invite", { url: `http://127.0.0.1:${pa}` });
  const jn = await rpc(cb, "bots.join", { invite: inv?.invite ?? "" });
  const peer = await until(20000, () => cb.seen.find((c) => c.$ === "PeerSet" && !c.revoked) && ca.seen.find((c) => c.$ === "PeerSet" && !c.revoked));
  check("the hubs are linked", !!inv?.ok && !!jn?.ok && !!peer, [inv, jn]);

  // each machine makes its id
  const idA = await until(10000, () => setting(ca, "machine.id"));
  const idB = await until(10000, () => setting(cb, "machine.id"));
  check("each machine has an id of its own", !!idA && !!idB && idA !== idB, [idA, idB]);

  // promote on alpha
  const kit = await rpc(ca, "bots.create", { name: "kit", persona: "the uberbot" });
  check("bots.create on alpha", !!kit?.ok, kit);
  const kitBot = kit?.bot as string;
  await rpc(ca, "bots.remember", { bot: kitBot, key: "colour", kind: "fact", text: "blue", tags: "" });
  const promoted = await rpc(ca, "bots.uber", { bot: kitBot });
  check("bots.uber on alpha", !!promoted?.ok && !!promoted?.uid, promoted);
  const uid = promoted?.uid as string;
  const first = await until(20000, () => leases(ca).find((o) => o.body.holder === idA));
  check("promotion logs its first ops (lease, term 1)", !!first && first.body.term === 1, ops(ca).map((o) => o.body.k));
  check("including its memory", !!ops(ca).find((o) => o.body.k === "mem" && o.body.key === "colour"), ops(ca).map((o) => o.body));

  // beta is offered it
  const offer = await until(150000, () => { const o = setting(cb, "uber.offer"); return o ? JSON.parse(o) : undefined; });
  check("beta is offered the uberbot", !!offer && offer.uid === uid && offer.name === "kit", offer);

  // beta joins
  const joined = await rpc(cb, "bots.uber_join", { uid });
  check("bots.uber_join on beta", !!joined?.ok && !!joined?.bot, joined);
  const bbot = joined?.bot as string;
  const bset = await until(5000, () => cb.seen.find((c) => c.$ === "BotSet" && c.id === bbot));
  const bthread = bset?.thread as string;
  check("beta's replica is an ordinary bot", !!bset && !!bthread, bset);
  const mem = await until(60000, () => cb.seen.find((c) => c.$ === "MemorySaved" && c.bot === bbot && c.key === "colour"));
  check("alpha's memory arrives on beta's replica", !!mem && mem.text === "blue", cb.seen.filter((c) => c.$ === "MemorySaved"));

  // memory both ways
  const t0 = Date.now();
  await rpc(cb, "bots.remember", { bot: bbot, key: "pet", kind: "fact", text: "a cat", tags: "" });
  const onA = await until(60000, () => ca.seen.find((c) => c.$ === "MemorySaved" && c.bot === kitBot && c.key === "pet"));
  check("a memory saved on beta reaches alpha", !!onA && onA.text === "a cat", ca.seen.filter((c) => c.$ === "MemorySaved"));
  console.log(`  beta to alpha in ${Date.now() - t0} ms`);
  const t1 = Date.now();
  await rpc(ca, "bots.remember", { bot: kitBot, key: "city", kind: "fact", text: "Oslo", tags: "" });
  const onB = await until(60000, () => cb.seen.find((c) => c.$ === "MemorySaved" && c.bot === bbot && c.key === "city"));
  check("a memory saved on alpha reaches beta", !!onB && onB.text === "Oslo", cb.seen.filter((c) => c.$ === "MemorySaved"));
  console.log(`  alpha to beta in ${Date.now() - t1} ms`);
  await rpc(ca, "bots.forget", { bot: kitBot, key: "pet" });
  const gone = await until(60000, () => cb.seen.find((c) => c.$ === "MemoryForgot" && c.bot === bbot && c.key === "pet"));
  check("a forget travels as well", !!gone);
  const sets = ops(ca).filter((o) => o.origin === idA).map((o) => o.n);
  check("alpha's ops are numbered 1, 2, 3...", sets.every((n, i) => n === i + 1), sets);

  // a routine made on alpha (every minute) runs on the holder only
  const athread = ca.seen.find((c) => c.$ === "BotSet" && c.id === kitBot && c.thread)?.thread as string;
  const routine = await rpc(ca, "bots.routine", { bot: kitBot, name: "tick", cron: "* * * * *", prompt: "say tick", on: true });
  check("a routine is made on alpha", !!routine?.ok, routine);
  const onBr = await until(60000, () => cb.seen.find((c) => c.$ === "RoutineSet" && c.bot === bbot && c.name === "tick"));
  check("it reaches beta under a global id", !!onBr && String(onBr.id).includes(":"), onBr);
  const ranA = await until(150000, () => routineRuns(ca, athread).length >= 1);
  check("it runs on alpha, the holder", !!ranA, routineRuns(ca, athread));
  const fired = await until(30000, () => ops(cb).find((o) => o.body.k === "fired"));
  check("alpha says it ran (a fired op reaches beta)", !!fired, ops(cb).map((o) => o.body.k));
  await sleep(70000);
  check("and not on beta", routineRuns(cb, bthread).length === 0, routineRuns(cb, bthread));

  // alpha stops: beta takes the lease after the grace
  const before = routineRuns(ca, athread).length;
  ca.ws.close();
  a.proc!.kill();
  await a.proc!.exited;
  a.proc = null;
  const tk = Date.now();
  const took = await until(180000, () => leases(cb).find((o) => o.body.holder === idB && o.body.term === 2));
  check("beta takes the lease (term 2) within the grace and a minute", !!took, leases(cb).map((o) => o.body));
  console.log(`  taken ${Date.now() - tk} ms after alpha stopped`);
  const ranB = await until(150000, () => routineRuns(cb, bthread).length >= 1);
  check("the routine runs on beta now", !!ranB, routineRuns(cb, bthread));

  // alpha comes back: it steps down
  spawn(a);
  await up(a);
  ca = await connect(a);
  clients.push(ca);
  const stepped = await until(150000, () => leases(ca).find((o) => o.body.holder === idB && o.body.term === 2));
  check("alpha learns of the higher term", !!stepped, leases(ca).map((o) => o.body));
  const mark = routineRuns(ca, athread).length;
  const markB = routineRuns(cb, bthread).length;
  await sleep(130000);
  check("alpha no longer runs the routine", routineRuns(ca, athread).length === mark, [mark, routineRuns(ca, athread).length]);
  check("beta does", routineRuns(cb, bthread).length > markB, [markB, routineRuns(cb, bthread).length]);
  void before;
} finally {
  if (process.env.UBER_E2E_DUMP) {
    mkdirSync(process.env.UBER_E2E_DUMP, { recursive: true });
    for (const h of [a, b]) { try { writeFileSync(join(process.env.UBER_E2E_DUMP, `${h.name}.jsonl`), readFileSync(join(h.home, "events.jsonl"))); } catch {} }
  }
  for (const c of clients) { try { c.ws.close(); } catch {} }
  for (const h of [a, b]) if (h.proc) { h.proc.kill(); await h.proc.exited; }
  rmSync(root, { recursive: true, force: true });
}
console.log(failed ? "uber e2e: FAIL" : "uber e2e: ok");
process.exit(failed ? 1 : 0);
