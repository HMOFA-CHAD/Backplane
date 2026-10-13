// Exercise the foreign JS twin with temporary POSIX flocks, not a live hub.
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
const root = mkdtempSync(join(tmpdir(), "bp-lock-js-"));
process.env.BACKPLANE_LOCK_DIR = root;
(globalThis as any).require = createRequire(import.meta.url);
const effects = new Map<string, Function>();
(globalThis as any).io_eff = (id: string, f: Function) => effects.set(id, f);
const source = readFileSync("src/server/effects/locks.js", "utf8")
  .replaceAll("CID(Guard.take)", '"take"').replaceAll("CID(Guard.drop)", '"drop"');
(0, eval)(source);
const script = "cat >/dev/null\n" + JSON.parse(readFileSync("src/server/lockio.bend", "utf8").split("\n").find(l => l.startsWith('  "'))!.trim());
const take = effects.get("take")!, drop = effects.get("drop")!;
let failures = 0;
let work: ReturnType<typeof Bun.spawn> | undefined;
const check = (yes: boolean, label: string) => { console.log(`${yes ? "ok" : "FAIL"} ${label}`); if (!yes) failures++; };
const raw = () => Bun.spawnSync(["flock", "-n", join(root, "bp-bend.lock"), "true"]).exitCode;
try {
  check(take("bend", "first", root, script).$ === "True", "JS guard acquires POSIX flock");
  check(take("bend", "first", root, script).$ === "True", "JS guard duplicate is idempotent");
  check(take("bend", "second", root, script).$ === "False", "JS guard excludes another holder");
  check(raw() !== 0, "JS guard excludes raw flock");
  drop("bend", "second");
  check(raw() !== 0, "JS guard non-holder drop changes nothing");
  drop("bend", "first");
  await Bun.sleep(200);
  check(raw() === 0, "JS guard release frees raw flock");
  check(take("../bend", "first", root, script).$ === "False", "JS guard rejects path traversal");
  if (process.platform === "linux") {
    const dir = join(root, "work", "w-test"); mkdirSync(dir, { recursive: true });
    work = Bun.spawn(["setsid", "sleep", "30"], { stdout: "ignore", stderr: "ignore" });
    const stat = readFileSync(`/proc/${work.pid}/stat`, "utf8");
    const start = stat.slice(stat.lastIndexOf(")") + 2).split(" ")[19];
    writeFileSync(join(dir, "pid"), String(work.pid));
    writeFileSync(join(dir, "pidid"), readFileSync("/proc/sys/kernel/random/boot_id", "utf8").trim() + ":" + start);
    check(take("owned", "w-test", root, script).$ === "True", "JS owned work guard acquires");
    drop("owned", "w-test");
    const result = await Promise.race([work.exited, Bun.sleep(6000).then(() => -999)]);
    check(result !== -999, "JS guard stops its captured detached work");
  }

} finally { drop("bend", "first"); drop("owned", "w-test"); if (work?.exitCode === null) { try { process.kill(work.pid, "SIGTERM"); } catch (e: any) { if (e.code !== "ESRCH") throw e; } await work.exited; } await Bun.sleep(200); rmSync(root, { recursive: true, force: true }); }
process.exit(failures ? 1 : 0);
